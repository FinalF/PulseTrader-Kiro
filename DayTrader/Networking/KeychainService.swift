// KeychainService.swift — secure storage for API credentials
import Foundation
import Security

enum KeychainService {

    enum Key: String {
        case alpacaAPIKey    = "com.daytrader.alpaca.apiKey"
        case alpacaAPISecret = "com.daytrader.alpaca.apiSecret"
    }

    // MARK: - Write

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key.rawValue,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    static func load(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Convenience

    static var alpacaAPIKey: String?    { load(.alpacaAPIKey) }
    static var alpacaAPISecret: String? { load(.alpacaAPISecret) }
    static var hasAlpacaCredentials: Bool {
        guard let k = alpacaAPIKey, let s = alpacaAPISecret else { return false }
        return !k.isEmpty && !s.isEmpty
    }
}
