import Foundation
import Security

/// Stores the Anthropic API key in the macOS Keychain as a generic-password
/// item owned by this (sandboxed) app. The key never touches the repo, the
/// JSON store, or logs — only the Keychain. The user pastes it into the in-app
/// settings field; nothing else reads or writes it.
enum Keychain {
    // The app's own bundle ID (from Config/Doba.xcconfig) — no identifier hardcoded.
    private static let service = Bundle.main.bundleIdentifier ?? "com.example.Doba"
    private static let account = "anthropic-api-key"

    /// The stored key, or nil if none is set.
    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static var hasKey: Bool { apiKey?.isEmpty == false }

    /// Save (insert or replace) the key. Empty string clears it.
    @discardableResult
    static func set(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return clear() }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(trimmed.utf8)

        // Try update first; if the item doesn't exist, add it.
        let updated = SecItemUpdate(base as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        if updated == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
