import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    static let service = "com.glot.remote"

    static func save(account: String, data: Data) throws {
        try delete(account: account)
        var query = base(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrSynchronizable as String] = false
        if dataProtection {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(silent(query) as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RemoteError.keychain(describe(status))
        }
    }

    static func load(account: String) throws -> Data? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(silent(query) as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw RemoteError.keychain(describe(status))
        }
        return item as? Data
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(silent(base(account: account)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteError.keychain(describe(status))
        }
    }

    static func savePrivateKey(_ key: SecKey, tag: Data) throws {
        let query = keyQuery(tag: tag)
        SecItemDelete(silent(query) as CFDictionary)
        var add = keyQuery(tag: tag)
        add[kSecValueRef as String] = key
        add[kSecAttrSynchronizable as String] = false
        if dataProtection {
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(silent(add) as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RemoteError.keychain(describe(status))
        }
    }

    static func loadPrivateKey(tag: Data) throws -> SecKey? {
        var query = keyQuery(tag: tag)
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeECSECPrimeRandom
        query[kSecReturnRef as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(silent(query) as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let item else {
            throw RemoteError.keychain(describe(status))
        }
        guard CFGetTypeID(item) == SecKeyGetTypeID() else {
            throw RemoteError.keychain("The stored TLS key has the wrong type.")
        }
        return (item as! SecKey)
    }

    /// The data-protection keychain needs a keychain-access-groups entitlement.
    /// A sandboxed Mac app does not have that entitlement, and SecItemAdd then
    /// fails with errSecMissingEntitlement. The Mac uses its login keychain instead.
    private static var dataProtection: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    private static func base(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func keyQuery(tag: Data) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// Fails the item call instead of showing a keychain prompt.
    private static func silent(_ query: [String: Any]) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private static func describe(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "status \(status)"
    }
}

public enum PersistentIdentity {
    private static let phoneAccount = "phone.signing"
    private static let macIDAccount = "mac.device-id"
    private static let macCertAccount = "mac.tls.cert"
    private static let macKeyTag = Data("com.glot.remote.mac.tls.p256".utf8)

    public static func loadOrCreatePhone() throws -> SigningIdentity {
        if let data = try KeychainStore.load(account: phoneAccount) {
            let stored = try JSONDecoder().decode(StoredSigningKey.self, from: data)
            let key = try P256.Signing.PrivateKey(rawRepresentation: stored.privateKey)
            return SigningIdentity(deviceID: stored.deviceID, privateKey: key)
        }
        let created = SigningIdentity.ephemeral()
        let stored = StoredSigningKey(deviceID: created.deviceID, privateKey: created.privateKey.rawRepresentation)
        try KeychainStore.save(account: phoneAccount, data: JSONEncoder().encode(stored))
        return created
    }

    public static func loadOrCreateMacIdentity() throws -> (id: UUID, material: TLSMaterial) {
        let id = try loadOrCreateMacID()
        if let key = try KeychainStore.loadPrivateKey(tag: macKeyTag),
           let der = try KeychainStore.load(account: macCertAccount) {
            let material = try TLSMaterial.make(privateKey: key, certificateDER: der)
            return (id, material)
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw RemoteError.crypto("A TLS key could not be created.")
        }
        let material = try TLSMaterial.make(privateKey: privateKey)
        try KeychainStore.savePrivateKey(privateKey, tag: macKeyTag)
        try KeychainStore.save(account: macCertAccount, data: material.certificateDER)
        return (id, material)
    }

    private static func loadOrCreateMacID() throws -> UUID {
        if let data = try KeychainStore.load(account: macIDAccount),
           let string = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: string) {
            return id
        }
        let id = UUID()
        guard let data = id.uuidString.data(using: .utf8) else {
            throw RemoteError.crypto("The Mac identifier could not be stored.")
        }
        try KeychainStore.save(account: macIDAccount, data: data)
        return id
    }
}

private struct StoredSigningKey: Codable {
    var deviceID: UUID
    var privateKey: Data
}
