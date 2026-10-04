import Foundation
import Security

/// Storage abstraction for provider secrets. Conformances decide where the
/// secret lives (Keychain in the app, memory in test fixtures).
public protocol SecretStore {
    func secret(account: String) -> String?
    func setSecret(_ value: String, account: String) throws
    func deleteSecret(account: String) throws
}

/// Keychain-backed secret storage (generic passwords). API keys never touch JSON files.
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = AppConstants.keychainService) {
        self.service = service
    }

    func secret(account: String) -> String? {
        var query: [String: Any] = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            updateStatus = SecItemAdd(query as CFDictionary, nil)
        }
        guard updateStatus == errSecSuccess else {
            throw SecretStoreError.keychainStatus(updateStatus)
        }
    }

    func deleteSecret(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum SecretStoreError: LocalizedError {
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            return "Keychain operation failed (OSStatus \(status))."
        }
    }
}
