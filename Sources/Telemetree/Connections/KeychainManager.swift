import Foundation
import Security

/// Stores connection passwords in the macOS Keychain, keyed by profile id.
/// Never persist passwords anywhere else (no plaintext files, no logs).
enum KeychainManager {
    private static let service = "com.telemetree.app"

    static func savePassword(_ password: String, for profileID: UUID) {
        let query = baseQuery(for: profileID)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func readPassword(for profileID: UUID) -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for profileID: UUID) {
        SecItemDelete(baseQuery(for: profileID) as CFDictionary)
    }

    private static func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}
