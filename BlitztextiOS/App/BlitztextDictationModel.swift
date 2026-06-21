import Combine
import Foundation
import UIKit

@MainActor
final class BlitztextDictationModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case done
        case error(String)
    }

    @Published var phase: Phase = .idle {
        didSet { updateIdleTimer() }
    }
    @Published var apiKeyDraft = ""
    @Published var customTermsText = ""
    @Published var language = BlitztextSharedStore.language
    @Published var lastTranscript = BlitztextSharedStore.lastTranscript
    @Published var statusText = ""
    @Published var recordingElapsed: TimeInterval = 0
    @Published var isKeyboardDictationSession = false
    /// false = wörtlich, true = per LLM verbessert/gekürzt. Geteilt mit der Tastatur.
    @Published var improveEnabled = BlitztextSharedStore.improveEnabled {
        didSet { BlitztextSharedStore.improveEnabled = improveEnabled }
    }

    let recorder = BlitztextAudioRecorder()
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var lastHandledKeyboardRequest = ""

    var hasAPIKey: Bool {
        BlitztextKeychain.load(.openAIAPIKey) != nil
    }

    init() {
        customTermsText = BlitztextSharedStore.customTerms.joined(separator: ", ")
    }

    /// Wird die App über die Tastatur geöffnet, startet hier automatisch eine Aufnahme.
    func handleKeyboardDictationRequestIfNeeded() {
        guard let request = BlitztextKeychain.load(.keyboardDictationRequest),
              request != lastHandledKeyboardRequest else {
            return
        }
        lastHandledKeyboardRequest = request
        BlitztextKeychain.delete(.keyboardDictationRequest)
        startKeyboardDictationSession()
    }

    func startKeyboardDictationSession() {
        // Von der Tastatur gesetzten Modus übernehmen.
        improveEnabled = BlitztextSharedStore.improveEnabled
        isKeyboardDictationSession = true
        guard hasAPIKey else {
            phase = .error("Bitte zuerst im Tab „Einstellungen“ einen OpenAI API Key speichern.")
            return
        }
        statusText = "Diktat von der Tastatur gestartet."
        startRecording()
    }

    /// Nach dem Rücksprung (App ging in den Hintergrund) die Session zurücksetzen,
    /// damit das nächste Diktat sauber startet.
    func endSessionIfFinished() {
        guard isKeyboardDictationSession else { return }
        switch phase {
        case .done, .error, .idle:
            isKeyboardDictationSession = false
            phase = .idle
        default:
            break
        }
    }

    func closeKeyboardSessionUI() {
        if case .recording = phase {
            stopElapsedTimer()
            _ = recorder.stopRecording()
            recorder.discardRecording()
        }
        isKeyboardDictationSession = false
        phase = .idle
    }

    func saveSettings() {
        let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do {
                try BlitztextKeychain.save(trimmedKey, for: .openAIAPIKey)
                apiKeyDraft = ""
                statusText = "API Key gespeichert."
            } catch {
                phase = .error(error.localizedDescription)
            }
        }

        let terms = customTermsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        BlitztextSharedStore.customTerms = terms
        BlitztextSharedStore.language = language
    }

    func startRecording() {
        Task {
            guard await recorder.requestPermission() else {
                phase = .error("Mikrofonzugriff fehlt.")
                return
            }
            saveSettings()
            recorder.startRecording()
            if let error = recorder.errorMessage {
                phase = .error(error)
            } else {
                startElapsedTimer()
                phase = .recording
            }
        }
    }

    func stopAndTranscribe() {
        stopElapsedTimer()
        guard let url = recorder.stopRecording() else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        guard recorder.lastRecordingDuration >= 0.3 else {
            recorder.discardRecording()
            phase = .error("Aufnahme war zu kurz.")
            return
        }

        guard let apiKey = BlitztextKeychain.load(.openAIAPIKey) else {
            phase = .error("Bitte zuerst OpenAI API Key speichern.")
            return
        }

        phase = .transcribing
        let shouldImprove = improveEnabled
        Task {
            do {
                var text = try await OpenAITranscriptionClient.transcribe(
                    audioURL: url,
                    apiKey: apiKey,
                    customTerms: BlitztextSharedStore.customTerms,
                    language: language
                )
                try? FileManager.default.removeItem(at: url)

                if shouldImprove {
                    statusText = "Wird verbessert ..."
                    do {
                        text = try await BlitztextTextImprovementClient.improve(
                            text: text,
                            apiKey: apiKey,
                            customTerms: BlitztextSharedStore.customTerms
                        )
                    } catch {
                        // Verbesserung fehlgeschlagen: Rohtranskript verwenden, Flow nicht abbrechen.
                        statusText = "Verbesserung nicht möglich – Rohtext verwendet."
                    }
                }

                BlitztextSharedStore.lastTranscript = text
                // Für die Tastatur bereitlegen: geteilter Schlüsselbund + Zwischenablage.
                try? BlitztextKeychain.save(text, for: .keyboardPendingTranscript)
                UIPasteboard.general.string = text
                lastTranscript = text
                statusText = isKeyboardDictationSession
                    ? "Fertig! Tippe oben links auf „‹ Zurück“ – der Text wird eingesetzt."
                    : "Transkribiert und in die Zwischenablage kopiert."
                phase = .done
            } catch {
                try? FileManager.default.removeItem(at: url)
                phase = .error(error.localizedDescription)
            }
        }
    }

    func copyLastTranscript() {
        UIPasteboard.general.string = lastTranscript
        statusText = "Kopiert."
    }

    func deleteAPIKey() {
        BlitztextKeychain.delete(.openAIAPIKey)
        apiKeyDraft = ""
        // statusText ist @Published und löst ein Neuzeichnen aus, damit hasAPIKey neu ausgewertet wird.
        statusText = "API Key entfernt."
    }

    private func startElapsedTimer() {
        recordingTimer?.invalidate()
        recordingStartedAt = Date()
        recordingElapsed = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartedAt else { return }
                self.recordingElapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopElapsedTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartedAt = nil
    }

    /// Verhindert die automatische Display-Sperre, solange aufgenommen oder transkribiert
    /// wird. Sonst sperrt das iPhone mitten im Diktat und der iOS-„‹ Zurück“-Knopf
    /// verschwindet nach dem Entsperren.
    private func updateIdleTimer() {
        switch phase {
        case .recording, .transcribing:
            UIApplication.shared.isIdleTimerDisabled = true
        case .idle, .done, .error:
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
