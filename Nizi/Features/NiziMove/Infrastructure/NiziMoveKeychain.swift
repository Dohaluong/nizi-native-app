import Foundation
import Security

enum NiziMoveKeychain {
    private static let service = "vn.ima.Nizi.move-import"

    static func save(accessToken: String, sessionID: String) throws {
        let data = Data(accessToken.utf8)
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: sessionID]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NiziMoveError.server("KEYCHAIN_\(status)") }
    }

    static func accessToken(sessionID: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: sessionID,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NiziMoveError.server("KEYCHAIN_\(status)")
        }
        return value
    }

    static func delete(sessionID: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: sessionID] as CFDictionary)
    }
}
