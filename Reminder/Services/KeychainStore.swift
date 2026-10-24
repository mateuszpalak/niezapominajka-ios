import Foundation
import Security

/// Proste przechowywanie sekretów (klucz Claude API, token TickTick) w Keychain.
enum KeychainStore {
    private static let service = "software.plq.niezapominajka"
    private static let apiKeyAccount = "claude-api-key"
    private static let tickTickAccount = "ticktick-token"

    static func saveAPIKey(_ key: String) { save(key, account: apiKeyAccount) }
    static func loadAPIKey() -> String? { load(account: apiKeyAccount) }

    static func saveTickTickToken(_ token: String) { save(token, account: tickTickAccount) }
    static func loadTickTickToken() -> String? { load(account: tickTickAccount) }

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
