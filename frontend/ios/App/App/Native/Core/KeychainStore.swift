import Foundation
import Security

/// Minimal Keychain wrapper for the auth session.
///
/// The session lives in the Keychain rather than UserDefaults because it
/// carries a refresh token: UserDefaults is readable from a device backup,
/// the Keychain item below is not (`ThisDeviceOnly`).
enum KeychainStore {

    private static let service = "me.big3.app.auth"

    static func save(_ data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insertStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            if insertStatus != errSecSuccess {
                NSLog("[Keychain] insert failed for \(key): \(insertStatus)")
            }
        } else if status != errSecSuccess {
            NSLog("[Keychain] update failed for \(key): \(status)")
        }
    }

    static func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                NSLog("[Keychain] read failed for \(key): \(status)")
            }
            return nil
        }
        return item as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("[Keychain] delete failed for \(key): \(status)")
        }
    }
}
