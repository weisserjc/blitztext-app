import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BlitztextDictationModel

    private let languageOptions = [
        ("de", "Deutsch"),
        ("en", "Englisch"),
        ("", "Automatisch")
    ]

    var body: some View {
        if model.isKeyboardDictationSession {
            KeyboardDictationSessionView(model: model)
        } else {
            TabView {
                mainTab
                    .tabItem { Label("Diktat", systemImage: "mic.fill") }

                settingsTab
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
            }
        }
    }

    // MARK: - Tabs

    private var mainTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    dictationPanel
                    transcriptPanel
                    keyboardPanel
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Blitztext")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    apiKeyPanel
                    preferencesPanel
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Hauptschirm

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blitztext")
                .font(.system(size: 34, weight: .bold))
            Text("Schnelles Whisper-Diktat für iPhone. Diktiere direkt über die Blitztext-Tastatur in jeder App – der Text wird ohne Umweg eingesetzt. Hier kannst du auch direkt in der App diktieren.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var dictationPanel: some View {
        VStack(spacing: 18) {
            Button {
                switch model.phase {
                case .recording:
                    model.stopAndTranscribe()
                default:
                    model.startRecording()
                }
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 42, weight: .semibold))
                    Text(model.phase == .recording ? "Aufnahme stoppen" : "Diktat starten")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .foregroundStyle(.white)
                .background(recordButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            modePicker

            phaseView
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(panelBackground)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Modus", selection: $model.improveEnabled) {
                Text("Wörtlich").tag(false)
                Text("Verbessert").tag(true)
            }
            .pickerStyle(.segmented)
            Text(model.improveEnabled
                 ? "Text wird korrigiert, verbessert und gekürzt – Sinn bleibt erhalten."
                 : "Text wird 1:1 transkribiert.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch model.phase {
        case .idle:
            statusRow(icon: model.hasAPIKey ? "checkmark.circle.fill" : "key.fill",
                      text: model.hasAPIKey ? "Bereit" : "API Key fehlt – unter Einstellungen eintragen",
                      color: model.hasAPIKey ? .green : .orange)
        case .recording:
            VStack(spacing: 10) {
                ProgressView(value: Double(model.recorder.audioLevel))
                    .tint(.red)
                statusRow(icon: "waveform", text: "Ich höre zu", color: .red)
            }
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Wird transkribiert")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .done:
            statusRow(icon: "checkmark.circle.fill", text: "Text ist kopiert", color: .green)
        case .error(let message):
            statusRow(icon: "exclamationmark.triangle.fill", text: message, color: .orange)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Letzte Ausgabe") {
                Button {
                    model.copyLastTranscript()
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                .disabled(model.lastTranscript.isEmpty)
            }

            Text(model.lastTranscript.isEmpty ? "Noch kein Transkript." : model.lastTranscript)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !model.statusText.isEmpty {
                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keyboardPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tastatur")
            Text("Aktiviere Blitztext unter Einstellungen > Allgemein > Tastatur > Tastaturen und erlaube vollen Zugriff. Danach wechselst du in jeder App auf die Blitztext-Tastatur, tippst auf Start, sprichst und tippst auf Stop – der Text wird direkt eingesetzt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Einstellungen

    private var apiKeyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("OpenAI API Key")

            if model.hasAPIKey {
                Label("Gespeichert", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Text("Trage unten einen neuen Key ein, um den gespeicherten zu ersetzen, oder entferne ihn.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Der Key wird sicher im Schlüsselbund gespeichert und mit der Tastatur geteilt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField(model.hasAPIKey ? "Neuen Key eintragen (ersetzt den alten)" : "API Key eintragen", text: $model.apiKeyDraft)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    model.saveSettings()
                } label: {
                    Label("Key speichern", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.hasAPIKey {
                    Button(role: .destructive) {
                        model.deleteAPIKey()
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                            .font(.headline)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !model.statusText.isEmpty {
                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(panelBackground)
    }

    private var preferencesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Diktat")

            VStack(alignment: .leading, spacing: 8) {
                Text("Standard-Modus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                modePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sprache")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Sprache", selection: $model.language) {
                    ForEach(languageOptions, id: \.0) { code, title in
                        Text(title).tag(code)
                    }
                }
                .pickerStyle(.segmented)
            }

            labeledField(title: "Fachbegriffe") {
                TextField("z.B. Eigennamen, Befundbegriffe", text: $model.customTermsText, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
            }

            Button {
                model.saveSettings()
            } label: {
                Label("Einstellungen speichern", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .background(panelBackground)
    }

    // MARK: - Bausteine

    private var recordButtonColor: Color {
        switch model.phase {
        case .recording:
            return .red
        case .transcribing:
            return .gray
        default:
            return .blue
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.tertiarySystemBackground))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    private func statusRow(icon: String, text: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            trailing()
                .font(.callout.weight(.medium))
        }
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Fokussierter Aufnahme-Screen, wenn die App über die Tastatur gestartet wurde.
private struct KeyboardDictationSessionView: View {
    @ObservedObject var model: BlitztextDictationModel
    @State private var hintAnimate = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.04, green: 0.05, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                Spacer(minLength: 20)

                VStack(spacing: 24) {
                    waveform
                    statusText
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 28)

                if model.phase == .recording {
                    modeToggle
                        .padding(.horizontal, 28)
                        .padding(.bottom, 18)
                }

                if showsBottomButton {
                    bottomControls
                        .padding(.horizontal, 28)
                        .padding(.bottom, 34)
                }
            }

            if model.phase == .done {
                backHint
            }
        }
    }

    private var showsBottomButton: Bool {
        switch model.phase {
        case .recording, .error: return true
        default: return false
        }
    }

    /// Animierter Hinweis oben links auf den iOS-„‹ Zurück“-Chip.
    private var backHint: some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.green)
                    .offset(x: hintAnimate ? -6 : 4, y: hintAnimate ? -6 : 4)
                Text("Tippe oben links\nauf „‹ Zurück“")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                Spacer()
            }
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 2)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                hintAnimate = true
            }
        }
    }

    private var modeToggle: some View {
        VStack(spacing: 6) {
            Picker("Modus", selection: $model.improveEnabled) {
                Text("Wörtlich").tag(false)
                Text("Verbessert").tag(true)
            }
            .pickerStyle(.segmented)

            Text(model.improveEnabled ? "Wird verbessert & gekürzt" : "Wird 1:1 transkribiert")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var topBar: some View {
        HStack {
            // Im „Fertig“-Zustand bleibt oben links Platz für den Zurück-Hinweis.
            if model.phase != .done {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blitztext")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Diktat aus der Tastatur")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            Spacer()
            Button {
                model.closeKeyboardSessionUI()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var waveform: some View {
        ZStack {
            Circle().fill(recordingColor.opacity(0.16)).frame(width: 220, height: 220)
            Circle().stroke(recordingColor.opacity(0.45), lineWidth: 2).frame(width: 182, height: 182)
            Image(systemName: waveformIcon)
                .font(.system(size: 78, weight: .medium))
                .symbolEffect(.pulse, options: .repeating, isActive: model.phase == .recording || model.phase == .transcribing)
                .foregroundStyle(recordingColor)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.phase {
        case .recording:
            VStack(spacing: 10) {
                Text("Ich höre zu")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                Text(formatElapsed(model.recordingElapsed))
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        case .transcribing:
            VStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("Wird transkribiert")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        case .done:
            VStack(spacing: 12) {
                Text("Text ist bereit")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Sobald du zurück in deiner App bist, wird der Text automatisch eingesetzt.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
            }
        case .error(let message):
            VStack(spacing: 10) {
                Text("Das hat nicht geklappt")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
            }
        default:
            Text("Bereit")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            Button {
                switch model.phase {
                case .recording:
                    model.stopAndTranscribe()
                case .error:
                    model.startRecording()
                default:
                    break
                }
            } label: {
                ZStack {
                    Circle().fill(controlColor).frame(width: 112, height: 112)
                    Image(systemName: controlIcon)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Text(controlLabel)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
    }

    private var recordingColor: Color {
        switch model.phase {
        case .recording: return .red
        case .transcribing: return .blue
        case .done: return .green
        case .error: return .orange
        default: return .white
        }
    }

    private var waveformIcon: String {
        switch model.phase {
        case .done: return "checkmark"
        case .error: return "exclamationmark"
        default: return "waveform"
        }
    }

    private var controlColor: Color {
        switch model.phase {
        case .recording: return .red
        case .error: return .blue
        case .done: return .green
        default: return Color.white.opacity(0.16)
        }
    }

    private var controlIcon: String {
        switch model.phase {
        case .recording: return "stop.fill"
        case .error: return "mic.fill"
        case .done: return "arrow.uturn.left"
        default: return "hourglass"
        }
    }

    private var controlLabel: String {
        switch model.phase {
        case .recording: return "Zum Beenden tippen"
        case .transcribing: return "Einen Moment"
        case .done: return "Zurück zur App"
        case .error: return "Erneut starten"
        default: return ""
        }
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
