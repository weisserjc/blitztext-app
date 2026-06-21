import AVFoundation
import Foundation
import Combine

/// Nimmt Audio über AVAudioEngine + Input-Tap auf (nicht AVAudioRecorder).
/// In iOS-Keyboard-Extensions liefert AVAudioRecorder oft kein Signal (0,0 s / -120 dB),
/// während ein AVAudioEngine-Input-Tap das Mikrofon zuverlässig abgreift.
/// Die Tap-Puffer (Hardware-Format, meist 48 kHz Float) werden per AVAudioConverter
/// in 16 kHz/mono/Int16 WAV gewandelt – exakt das Format, das die OpenAI-Whisper-API
/// erwartet und das bereits end-to-end verifiziert wurde.
final class BlitztextAudioRecorder: NSObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    @Published var recordingURL: URL?
    @Published var errorMessage: String?
    @Published var lastRecordingDuration: TimeInterval = 0
    /// Lautester gemessener Pegel der letzten Aufnahme in dB (für Diagnose).
    /// Werte um -120..-160 dB bedeuten stumme Aufnahme (kein Mikrofon-Input).
    private(set) var peakPower: Float = -160

    /// Welche Audio-Konfiguration die Aufnahme erfolgreich gestartet hat (Diagnose).
    private(set) var activeConfiguration = ""

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: Date?
    private var lastLevelUpdate = Date.distantPast

    private struct SessionConfiguration {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        let label: String
    }

    private static let sessionConfigurations: [SessionConfiguration] = [
        SessionConfiguration(category: .playAndRecord, mode: .default,
                             options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth], label: "playAndRecord+mix"),
        SessionConfiguration(category: .record, mode: .default,
                             options: [.allowBluetooth], label: "record"),
        SessionConfiguration(category: .playAndRecord, mode: .measurement,
                             options: [.mixWithOthers, .allowBluetooth], label: "measurement+mix"),
        SessionConfiguration(category: .playAndRecord, mode: .spokenAudio,
                             options: [.allowBluetooth, .duckOthers], label: "spokenAudio+duck")
    ]

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording() {
        errorMessage = nil
        recordingURL = nil
        lastRecordingDuration = 0
        peakPower = -160
        activeConfiguration = ""

        // Mehrere Audio-Konfigurationen nacheinander versuchen. In Keyboard-Extensions
        // ist sehr geräte-/iOS-abhängig, welche Kombination das Mikrofon freigibt.
        var lastError: Error?
        for configuration in Self.sessionConfigurations {
            do {
                try startEngine(with: configuration)
                activeConfiguration = configuration.label
                startedAt = Date()
                isRecording = true
                return
            } catch {
                lastError = error
                teardownAfterFailedAttempt()
            }
        }

        let nsError = lastError as NSError?
        let domain = nsError?.domain ?? "?"
        let code = nsError?.code ?? 0
        errorMessage = "Mikrofon nicht verfügbar (\(domain) \(code)): \(lastError?.localizedDescription ?? "unbekannt")"
        isRecording = false
    }

    private func startEngine(with configuration: SessionConfiguration) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
        try session.setActive(true, options: [])

        engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "Blitztext", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon-Eingang verfügbar."])
        }

        // WAV als 16 kHz/mono/Int16 auf die Platte schreiben (Whisper-kompatibel).
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-ios-\(UUID().uuidString).wav")
        currentURL = url
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        audioFile = file

        // WICHTIG: AVAudioFile.write erwartet Puffer im processingFormat (Float32),
        // NICHT im Datei-/Disk-Format. Konverter daher auf processingFormat ausrichten,
        // sonst Format-Mismatch beim Schreiben -> Crash.
        let processingFormat = file.processingFormat
        outputFormat = processingFormat
        converter = AVAudioConverter(from: inputFormat, to: processingFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    private func teardownAfterFailedAttempt() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        audioFile = nil
        converter = nil
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        currentURL = nil
    }

    func stopRecording() -> URL? {
        if let started = startedAt {
            lastRecordingDuration = Date().timeIntervalSince(started)
        }
        cleanupEngine()
        audioFile = nil // schließt und finalisiert die WAV-Datei
        converter = nil
        startedAt = nil
        isRecording = false
        audioLevel = 0
        recordingURL = currentURL
        currentURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
    }

    func discardRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        recordingURL = nil
        currentURL = nil
    }

    private func cleanupEngine() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        updateLevels(from: buffer)

        guard let converter, let outputFormat, let audioFile else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, outBuffer.frameLength > 0 else { return }
        try? audioFile.write(from: outBuffer)
    }

    private func updateLevels(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var peak: Float = 0
        for i in 0..<count {
            let value = abs(channel[i])
            if value > peak { peak = value }
        }
        let db = peak > 0 ? 20 * log10(peak) : -160
        let level = max(0, min(1, (db + 50) / 50))

        // peakPower (einfacher Wert, nur für Diagnose) direkt setzen.
        peakPower = max(peakPower, db)

        // audioLevel (@Published, UI) nur ~10x/s aktualisieren, um den Main-Thread
        // nicht mit hunderten Dispatches pro Sekunde zu fluten (Aufhänger-Gefahr).
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) > 0.1 else { return }
        lastLevelUpdate = now
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }
}

extension BlitztextAudioRecorder: ObservableObject {}
