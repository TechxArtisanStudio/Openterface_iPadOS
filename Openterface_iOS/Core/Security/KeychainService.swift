//
//  KeychainService.swift
//  Openterface_iOS
//

import Foundation
import Security

final class KeychainService {

    static let shared = KeychainService()

    private let service = Bundle.main.bundleIdentifier ?? "openterface.kvm.ipados"

    private init() {}

    // MARK: - Public API

    func set(string: String, key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Try to update first; if it doesn't exist, add it
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        print("🔑 Keychain: set(key=\(key)) — SecItemUpdate status: \(updateStatus) (errSecSuccess=\(errSecSuccess))")
        if updateStatus == errSecSuccess {
            return true
        }

        let addQuery = query.merging([kSecValueData as String: data]) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        print("🔑 Keychain: set(key=\(key)) — SecItemAdd status: \(addStatus)")
        return addStatus == errSecSuccess
    }

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        print("🔑 Keychain: get(key=\(key)) — SecItemCopyMatching status: \(status)")

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        print("🔑 Keychain: delete(key=\(key)) — SecItemDelete status: \(status)")
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
