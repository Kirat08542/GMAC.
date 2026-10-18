import Foundation
import Network
import Security

public final class TLSMaterial: @unchecked Sendable {
    public let privateKey: SecKey
    public let certificate: SecCertificate
    public let identity: SecIdentity
    public let secIdentity: sec_identity_t
    public let canonicalPublicKey: Data
    public let certificateDER: Data

    init(
        privateKey: SecKey,
        certificate: SecCertificate,
        identity: SecIdentity,
        secIdentity: sec_identity_t,
        canonicalPublicKey: Data,
        certificateDER: Data
    ) {
        self.privateKey = privateKey
        self.certificate = certificate
        self.identity = identity
        self.secIdentity = secIdentity
        self.canonicalPublicKey = canonicalPublicKey
        self.certificateDER = certificateDER
    }

    public static func ephemeral(commonName: String = "GLOT Remote Mac") throws -> TLSMaterial {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw RemoteError.crypto("A TLS key could not be created.")
        }
        return try make(privateKey: privateKey, commonName: commonName)
    }

    public static func make(privateKey: SecKey, certificateDER: Data? = nil, commonName: String = "GLOT Remote Mac") throws -> TLSMaterial {
        let built: (certificate: SecCertificate, identity: SecIdentity, der: Data)
        if let certificateDER {
            guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
                throw RemoteError.crypto("The stored TLS certificate is not valid.")
            }
            guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
                throw RemoteError.crypto("The stored TLS certificate does not match its key.")
            }
            built = (certificate, identity, certificateDER)
        } else {
            built = try CertificateBuilder.makeIdentity(privateKey: privateKey, commonName: commonName)
        }
        guard let secIdentity = sec_identity_create(built.identity) else {
            throw RemoteError.crypto("The TLS identity could not be prepared.")
        }
        let publicKey = try CertificateBuilder.canonicalPublicKey(privateKey)
        return TLSMaterial(
            privateKey: privateKey,
            certificate: built.certificate,
            identity: built.identity,
            secIdentity: secIdentity,
            canonicalPublicKey: publicKey,
            certificateDER: built.der
        )
    }
}

public enum TLSPin: Sendable, Equatable {
    case acceptForPairing
    case pinned(canonical: Data, observed: Data)
}

final class PeerKeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    func store(_ data: Data) {
        lock.lock()
        key = data
        lock.unlock()
    }

    func load() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }
}

enum TLSConfiguration {
    static func serverParameters(identity: TLSMaterial) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.connectionTimeout = 10
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(security, identity.secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv13)
        sec_protocol_options_set_tls_tickets_enabled(security, false)
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }

    static func clientParameters(pin: TLSPin, observedKey: PeerKeyBox) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.connectionTimeout = 10
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv13)
        sec_protocol_options_set_tls_tickets_enabled(security, false)
        sec_protocol_options_set_peer_authentication_required(security, true)
        sec_protocol_options_set_tls_server_name(security, Limits.tlsServerName)
        sec_protocol_options_set_verify_block(security, { metadata, _, complete in
            guard let key = copyPeerKey(metadata), !key.isEmpty else {
                switch pin {
                case .acceptForPairing:
                    complete(true)
                case .pinned:
                    complete(false)
                }
                return
            }
            observedKey.store(key)
            switch pin {
            case .acceptForPairing:
                complete(true)
            case .pinned(let canonical, let observed):
                complete(key == observed || PeerKey.matches(canonical: canonical, observed: key))
            }
        }, DispatchQueue.global(qos: .userInitiated))
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }

    static func copyPeerKey(_ metadata: sec_protocol_metadata_t) -> Data? {
        guard let raw = sec_protocol_metadata_copy_peer_public_key(metadata) else {
            return nil
        }
        let dispatchData = raw as DispatchData
        var data = Data()
        data.reserveCapacity(dispatchData.count)
        for region in dispatchData.regions {
            data.append(contentsOf: region)
        }
        return data.isEmpty ? nil : data
    }

    static func isTLS13(_ connection: NWConnection) -> Bool {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return false
        }
        return sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata) == .TLSv13
    }
}
