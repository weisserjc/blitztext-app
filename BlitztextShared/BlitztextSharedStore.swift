import Foundation

enum BlitztextSharedStore {
    static let appGroupIdentifier = "group.app.blitztext.shared"

    private enum Key {
        static let lastTranscript = "lastTranscript"
        static let customTerms = "customTerms"
        static let language = "language"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var lastTranscript: String {
        get { defaults.string(forKey: Key.lastTranscript) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastTranscript) }
    }

    static var customTerms: [String] {
        get { defaults.stringArray(forKey: Key.customTerms) ?? [] }
        set { defaults.set(newValue, forKey: Key.customTerms) }
    }

    static var language: String {
        get { defaults.string(forKey: Key.language) ?? "de" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.language) }
    }

    /// Diktat-Modus: false = wörtlich, true = per LLM verbessert/gekürzt.
    /// Liegt im geteilten Schlüsselbund, damit Tastatur und App denselben Wert sehen.
    static var improveEnabled: Bool {
        get { BlitztextKeychain.load(.improveModeEnabled) == "1" }
        set { try? BlitztextKeychain.save(newValue ? "1" : "0", for: .improveModeEnabled) }
    }
}
