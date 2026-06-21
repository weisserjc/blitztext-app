import ObjectiveC
import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Key {
        static let lastInsertionAt = "blitztextLastInsertionAt"
    }

    private let statusLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["Wörtlich", "Verbessert"])
    private let insertButton = UIButton(type: .system)
    private let dictateButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let cardView = UIView()
    private var heightConstraint: NSLayoutConstraint?
    private var isOpeningApp = false
    private var pendingTranscriptTimer: Timer?
    private var lastInsertedText = ""
    private var lastInsertedAt = Date.distantPast
    private var isInsertingTranscript = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startPendingTranscriptPolling()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Die Tastatur ist wieder sichtbar -> der „App wird geöffnet“-Zustand ist vorbei.
        // Verhindert, dass die Tastatur hängen bleibt, wenn man ohne Diktat zurückkommt.
        isOpeningApp = false
        modeControl.selectedSegmentIndex = BlitztextSharedStore.improveEnabled ? 1 : 0
        insertPendingTranscriptIfNeeded()
        refreshStatus()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPendingTranscriptPolling()
    }

    private func setupView() {
        view.backgroundColor = UIColor.black
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 208)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true

        let titleLabel = UILabel()
        titleLabel.text = "Blitztext"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Whisper Keyboard"
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel

        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center

        modeControl.selectedSegmentIndex = BlitztextSharedStore.improveEnabled ? 1 : 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        var dictateConfig = UIButton.Configuration.filled()
        dictateConfig.title = "Diktieren"
        dictateConfig.image = UIImage(systemName: "mic.fill")
        dictateConfig.imagePadding = 6
        dictateConfig.cornerStyle = .capsule
        dictateConfig.baseBackgroundColor = .white
        dictateConfig.baseForegroundColor = .black
        dictateConfig.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        dictateButton.configuration = dictateConfig
        dictateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        dictateButton.addTarget(self, action: #selector(openDictationApp), for: .touchUpInside)

        var insertConfig = UIButton.Configuration.filled()
        insertConfig.image = UIImage(systemName: "text.insert")
        insertConfig.cornerStyle = .capsule
        insertConfig.baseBackgroundColor = UIColor.secondarySystemBackground
        insertConfig.baseForegroundColor = .label
        insertButton.configuration = insertConfig
        insertButton.addTarget(self, action: #selector(insertLastTranscript), for: .touchUpInside)

        var keyboardConfig = UIButton.Configuration.filled()
        keyboardConfig.image = UIImage(systemName: "globe")
        keyboardConfig.cornerStyle = .capsule
        keyboardConfig.baseBackgroundColor = UIColor.secondarySystemBackground
        keyboardConfig.baseForegroundColor = .label
        nextKeyboardButton.configuration = keyboardConfig
        nextKeyboardButton.addTarget(self, action: #selector(advanceToNextInputMode), for: .touchUpInside)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 1

        let header = UIStackView(arrangedSubviews: [titleStack, UIView(), nextKeyboardButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        // Diktieren zentriert (mit beiden Händen erreichbar), Einsetzen klein in der Ecke.
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        insertButton.translatesAutoresizingMaskIntoConstraints = false
        dictateButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(insertButton)
        footer.addSubview(dictateButton)

        let stack = UIStackView(arrangedSubviews: [header, statusLabel, modeControl, footer])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor.systemBackground
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.24
        cardView.layer.shadowRadius = 20
        cardView.layer.shadowOffset = CGSize(width: 0, height: 10)

        view.addSubview(cardView)
        cardView.addSubview(stack)
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 54),
            dictateButton.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            dictateButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            dictateButton.heightAnchor.constraint(equalToConstant: 54),
            dictateButton.widthAnchor.constraint(equalTo: footer.widthAnchor, multiplier: 0.58),
            insertButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            insertButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            insertButton.heightAnchor.constraint(equalToConstant: 46),
            insertButton.widthAnchor.constraint(equalToConstant: 58),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 40),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        refreshStatus()
    }

    private func refreshStatus() {
        guard !isOpeningApp else { return }

        guard hasFullAccess else {
            statusLabel.text = "Bitte „Vollen Zugriff“ für die Blitztext-Tastatur erlauben."
            insertButton.isEnabled = false
            updateInsertButtonAppearance()
            updateDictateButtonAppearance()
            return
        }

        let text = latestTranscriptCandidate()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusLabel.text = "Tippe auf Diktieren"
            insertButton.isEnabled = false
        } else {
            statusLabel.text = "Text bereit – „Einsetzen“ oder erneut diktieren"
            insertButton.isEnabled = true
        }
        updateInsertButtonAppearance()
        updateDictateButtonAppearance()
    }

    // MARK: - App für Aufnahme öffnen

    @objc private func openDictationApp() {
        guard hasFullAccess else {
            statusLabel.text = "Voller Zugriff fehlt: Einstellungen > Allgemein > Tastatur > Blitztext."
            return
        }
        openMainAppForDictation()
    }

    @objc private func modeChanged() {
        BlitztextSharedStore.improveEnabled = modeControl.selectedSegmentIndex == 1
    }

    private func openMainAppForDictation() {
        guard let url = URL(string: "blitztext://record?source=keyboard") else { return }
        do {
            try BlitztextKeychain.save(String(Date().timeIntervalSince1970), for: .keyboardDictationRequest)
        } catch {
            statusLabel.text = "Startauftrag fehlgeschlagen: \(error.localizedDescription)"
            return
        }
        isOpeningApp = true
        statusLabel.text = "Blitztext wird geöffnet ..."
        updateDictateButtonAppearance()
        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.statusLabel.text = "Blitztext wurde geöffnet."
                    return
                }
                // extensionContext.open funktioniert für Keyboards oft nicht – tiefere Wege versuchen.
                if self.openURLThroughApplication(url) {
                    self.statusLabel.text = "Blitztext wird geöffnet."
                    return
                }
                if self.openAppThroughLaunchServices() {
                    self.statusLabel.text = "Blitztext wird geöffnet."
                    return
                }
                if self.openURLThroughResponderChain(url) {
                    self.statusLabel.text = "Blitztext wird geöffnet."
                    return
                }
                self.isOpeningApp = false
                self.statusLabel.text = "Konnte nicht öffnen – Blitztext-App manuell starten."
                self.updateDictateButtonAppearance()
            }
        }
    }

    /// Öffnet eine URL über die Responder-Chain.
    @discardableResult
    private func openURLThroughResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    /// Öffnet die URL über UIApplication.sharedApplication.openURL: via Runtime.
    private func openURLThroughApplication(_ url: URL) -> Bool {
        guard let applicationClass = NSClassFromString("UIApplication") else { return false }
        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard let sharedMethod = class_getClassMethod(applicationClass, sharedSelector) else { return false }
        typealias SharedFn = @convention(c) (AnyClass, Selector) -> AnyObject
        let shared = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedFn.self)
        let application = shared(applicationClass, sharedSelector)

        let openSelector = NSSelectorFromString("openURL:")
        guard let appClass = object_getClass(application),
              let openMethod = class_getInstanceMethod(appClass, openSelector) else { return false }
        typealias OpenFn = @convention(c) (AnyObject, Selector, URL) -> Bool
        let open = unsafeBitCast(method_getImplementation(openMethod), to: OpenFn.self)
        return open(application, openSelector, url)
    }

    /// Öffnet die App über LSApplicationWorkspace.openApplicationWithBundleID: via Runtime.
    private func openAppThroughLaunchServices() -> Bool {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") else { return false }
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        guard let defaultMethod = class_getClassMethod(workspaceClass, defaultSelector) else { return false }
        typealias DefaultFn = @convention(c) (AnyClass, Selector) -> AnyObject
        let defaultWorkspace = unsafeBitCast(method_getImplementation(defaultMethod), to: DefaultFn.self)
        let workspace = defaultWorkspace(workspaceClass, defaultSelector)

        let openSelector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let workspaceObjectClass = object_getClass(workspace),
              let openMethod = class_getInstanceMethod(workspaceObjectClass, openSelector) else { return false }
        typealias OpenAppFn = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(method_getImplementation(openMethod), to: OpenAppFn.self)
        return open(workspace, openSelector, "de.johannesweisser.blitztext.ios" as NSString)
    }

    // MARK: - Texteinfügen

    private func insertPendingTranscriptIfNeeded() {
        // Nur über den geteilten Schlüsselbund – KEIN Lesen der Zwischenablage, da das
        // sonst die iOS-„Einsetzen erlauben?“-Abfrage auslöst (inkl. Universal Clipboard vom Mac).
        guard let text = consumeKeychainPendingTranscript() else { return }
        isOpeningApp = false
        insertTranscriptOnce(text)
    }

    @objc private func insertLastTranscript() {
        let text = latestTranscriptCandidate().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        BlitztextKeychain.delete(.keyboardPendingTranscript)
        insertTranscriptOnce(text)
    }

    private func latestTranscriptCandidate() -> String {
        // Nur Schlüsselbund – kein Zwischenablage-Lesen (vermeidet die Einsetzen-Abfrage).
        BlitztextKeychain.load(.keyboardPendingTranscript)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func consumeKeychainPendingTranscript() -> String? {
        guard let text = BlitztextKeychain.load(.keyboardPendingTranscript)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        BlitztextKeychain.delete(.keyboardPendingTranscript)
        return text
    }

    private func insertTranscriptOnce(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let isDuplicate = normalized == lastInsertedText && Date().timeIntervalSince(lastInsertedAt) < 5
        guard !isDuplicate else { return }

        // Vor dem Aktualisieren prüfen, ob kurz zuvor schon eingefügt wurde (zweites Diktat).
        let recentlyInserted: Bool
        if let last = UserDefaults.standard.object(forKey: Key.lastInsertionAt) as? Date {
            recentlyInserted = Date().timeIntervalSince(last) < 180
        } else {
            recentlyInserted = false
        }

        lastInsertedText = normalized
        lastInsertedAt = Date()
        insertTextInVisibleChunks(normalized, recentlyInserted: recentlyInserted)
        UserDefaults.standard.set(Date(), forKey: Key.lastInsertionAt)
        statusLabel.text = "Eingesetzt."
        insertButton.isEnabled = true
        updateInsertButtonAppearance()
        updateDictateButtonAppearance()
    }

    private func insertTextInVisibleChunks(_ text: String, recentlyInserted: Bool) {
        guard !isInsertingTranscript else { return }
        isInsertingTranscript = true

        let newStartsWithSpace = text.first?.isWhitespace ?? false
        let before = textDocumentProxy.documentContextBeforeInput
        let needsLeadingSpace: Bool
        if let before, !before.isEmpty {
            // Host-App liefert Kontext: nur Leerzeichen, wenn davor kein Whitespace steht.
            needsLeadingSpace = !(before.last?.isWhitespace ?? false) && !newStartsWithSpace
        } else {
            // Kein Kontext (z. B. WhatsApp): Leerzeichen, wenn dies ein Folge-Diktat ist.
            needsLeadingSpace = recentlyInserted && !newStartsWithSpace
        }
        let finalText = needsLeadingSpace ? " " + text : text

        let chunks = makeInsertionChunks(from: finalText, maxLength: 70)
        insertNextChunk(chunks, index: 0)
    }

    private func insertNextChunk(_ chunks: [String], index: Int) {
        guard index < chunks.count else {
            isInsertingTranscript = false
            return
        }

        textDocumentProxy.insertText(chunks[index])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.insertNextChunk(chunks, index: index + 1)
        }
    }

    private func makeInsertionChunks(from text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for part in text.split(separator: " ", omittingEmptySubsequences: false) {
            let next = current.isEmpty ? String(part) : current + " " + part
            if next.count > maxLength, !current.isEmpty {
                chunks.append(current + " ")
                current = String(part)
            } else {
                current = next
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func startPendingTranscriptPolling() {
        stopPendingTranscriptPolling()
        pendingTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.insertPendingTranscriptIfNeeded()
        }
    }

    private func stopPendingTranscriptPolling() {
        pendingTranscriptTimer?.invalidate()
        pendingTranscriptTimer = nil
    }

    // MARK: - Button-Darstellung

    private func updateInsertButtonAppearance() {
        var configuration = insertButton.configuration
        configuration?.baseBackgroundColor = insertButton.isEnabled ? UIColor.secondarySystemBackground : UIColor.tertiarySystemBackground
        configuration?.baseForegroundColor = insertButton.isEnabled ? UIColor.label : UIColor.secondaryLabel
        insertButton.configuration = configuration
        insertButton.alpha = insertButton.isEnabled ? 1.0 : 0.58
    }

    private func updateDictateButtonAppearance() {
        var configuration = dictateButton.configuration
        if isOpeningApp {
            configuration?.title = "..."
            configuration?.image = UIImage(systemName: "arrow.up.forward.app")
            configuration?.baseBackgroundColor = UIColor.secondarySystemBackground
            configuration?.baseForegroundColor = UIColor.secondaryLabel
            dictateButton.isEnabled = false
        } else {
            configuration?.title = "Diktieren"
            configuration?.image = UIImage(systemName: "mic.fill")
            configuration?.baseBackgroundColor = .white
            configuration?.baseForegroundColor = .black
            dictateButton.isEnabled = hasFullAccess
        }
        dictateButton.configuration = configuration
    }
}
