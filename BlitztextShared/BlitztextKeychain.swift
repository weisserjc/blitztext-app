import Foundation
import Security

enum BlitztextCredentialKey: String {
    case openAIAPIKey = "openAIAPIKey"
    /// Token, das die Tastatur setzt, um in der App eine Aufnahme zu starten.
    case keyboardDictationRequest = "keyboardDictationRequest"
    /// Fertiger Transkript-Text, den die App für die Tastatur bereitlegt.
    case keyboardPendingTranscript = "keyboardPendingTranscript"
    /// "1" = Diktat wird per LLM verbessert/gekürzt, sonst wörtlich. Geteilt App<->Tastatur.
    case improveModeEnabled = "improveModeEnabled"
}

enum BlitztextKeychain {
    private static let service = "app.blitztext.ios.credentials"
    private static let sharedAccessGroup = "43AUMU7SS5.de.johannesweisser.blitztext.shared"

    static func save(_ value: String, for key: BlitztextCredentialKey) throws {
        let data = Data(value.utf8)
        let accessGroup = sharedAccessGroup
        var query = baseQuery(for: key, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: key, accessGroup: accessGroup) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw BlitztextKeychainError.saveFailed(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw BlitztextKeychainError.saveFailed(status)
        }
    }

    static func load(_ key: BlitztextCredentialKey) -> String? {
        if let value = load(key, accessGroup: sharedAccessGroup) {
            return value
        }

        if let legacyValue = load(key, accessGroup: nil) {
            try? save(legacyValue, for: key)
            return legacyValue
        }

        return nil
    }

    static func delete(_ key: BlitztextCredentialKey) {
        SecItemDelete(baseQuery(for: key, accessGroup: sharedAccessGroup) as CFDictionary)
        SecItemDelete(baseQuery(for: key, accessGroup: nil) as CFDictionary)
    }

    private static func load(_ key: BlitztextCredentialKey, accessGroup: String?) -> String? {
        var query = baseQuery(for: key, accessGroup: accessGroup)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func baseQuery(for key: BlitztextCredentialKey, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum BlitztextKeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "API Key konnte nicht gespeichert werden. Status: \(status)"
        }
    }
}
