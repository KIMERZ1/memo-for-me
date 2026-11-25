import Foundation
import CryptoKit
import Security

public protocol KeyProvider: Sendable {
    func key() throws -> SymmetricKey
}

public enum KeyProviderError: Error { case keychain(OSStatus) }

/// 256-bit key stored in the login Keychain, this device only. Created on first use.
public struct KeychainKeyProvider: KeyProvider {
    private let service: String
    private let account = "secure-notes-master-key"

    public init(service: String = "com.kimerz.stickynotes") { self.service = service }

    public func key() throws -> SymmetricKey {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw KeyProviderError.keychain(status) }

        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeyProviderError.keychain(addStatus) }
        return fresh
    }
}
