import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.himem.app"

    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // `AfterFirstUnlock` — readable any time after the user
            // has unlocked the phone once since boot. The previous
            // class (`WhenUnlocked`) made the entry inaccessible
            // during the device-locked window, so background launches
            // (CloudKit push, watch sync, notification fetch) that
            // created the AuthService singleton during a locked
            // window read nil and stuck `isAuthenticated=false`
            // until next app cold-start. AfterFirstUnlock removes
            // that window. Still `ThisDeviceOnly` — no iCloud
            // Keychain sync, same security profile as before.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
