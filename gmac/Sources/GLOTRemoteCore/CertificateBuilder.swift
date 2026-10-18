import Foundation
import Security

enum DER {
    static func tlv(_ tag: UInt8, _ body: Data) -> Data {
        var out = Data([tag])
        out.append(length(body.count))
        out.append(body)
        return out
    }

    static func length(_ count: Int) -> Data {
        if count < 128 {
            return Data([UInt8(count)])
        }
        if count <= 0xFF {
            return Data([0x81, UInt8(count)])
        }
        return Data([0x82, UInt8(count >> 8), UInt8(count & 0xFF)])
    }

    static func sequence(_ body: Data) -> Data { tlv(0x30, body) }
    static func bitString(_ body: Data) -> Data { tlv(0x03, Data([0x00]) + body) }
    static func octetString(_ body: Data) -> Data { tlv(0x04, body) }
    static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
    static func utf8(_ value: String) -> Data { tlv(0x0C, Data(value.utf8)) }
    static func ia5(_ value: String) -> Data { tlv(0x16, Data(value.utf8)) }

    static func integer(_ raw: Data) -> Data {
        var body = Data(raw)
        while body.count > 1, body.first == 0 {
            body.removeFirst()
        }
        if let first = body.first, first >= 0x80 {
            body.insert(0, at: 0)
        }
        if body.isEmpty {
            body = Data([0])
        }
        return tlv(0x02, body)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(formatter.string(from: date).utf8))
    }

    static func explicit(_ number: UInt8, _ body: Data) -> Data {
        tlv(0xA0 + number, body)
    }
}

public enum CertificateBuilder {
    private static let ecPublicKey: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let prime256v1: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    private static let ecdsaSHA256: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    private static let commonName: [UInt8] = [0x55, 0x04, 0x03]
    private static let basicConstraints: [UInt8] = [0x55, 0x1D, 0x13]
    private static let keyUsage: [UInt8] = [0x55, 0x1D, 0x0F]
    private static let extendedKeyUsage: [UInt8] = [0x55, 0x1D, 0x25]
    private static let subjectAltName: [UInt8] = [0x55, 0x1D, 0x11]
    private static let serverAuth: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]

    public static func makeIdentity(privateKey: SecKey, commonName name: String) throws -> (certificate: SecCertificate, identity: SecIdentity, der: Data) {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw RemoteError.crypto("The TLS key has no public key.")
        }
        var copyError: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(publicKey, &copyError) as Data? else {
            throw RemoteError.crypto("The TLS public key could not be exported.")
        }
        guard external.count == Limits.tlsPublicKeyLength, external.first == 0x04 else {
            throw RemoteError.crypto("The TLS public key is not an uncompressed P-256 point.")
        }
        let der = try certificateDER(publicPoint: external, privateKey: privateKey, commonName: name)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw RemoteError.crypto("macOS rejected the generated certificate.")
        }
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw RemoteError.crypto("The certificate does not match its private key.")
        }
        return (certificate, identity, der)
    }

    public static func canonicalPublicKey(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw RemoteError.crypto("The TLS key has no public key.")
        }
        var error: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw RemoteError.crypto("The TLS public key could not be exported.")
        }
        return external
    }

    private static func certificateDER(publicPoint: Data, privateKey: SecKey, commonName name: String) throws -> Data {
        let algorithm = DER.sequence(DER.oid(ecdsaSHA256))
        let subject = directoryName(name)
        let now = Date()
        let validity = DER.sequence(
            DER.utcTime(now.addingTimeInterval(-86_400)) + DER.utcTime(now.addingTimeInterval(60 * 60 * 24 * 365 * 5))
        )
        let spki = DER.sequence(
            DER.sequence(DER.oid(ecPublicKey) + DER.oid(prime256v1)) + DER.bitString(publicPoint)
        )
        let tbsBody = DER.explicit(0, DER.integer(Data([0x02])))
            + DER.integer(serial())
            + algorithm
            + subject
            + validity
            + subject
            + spki
            + DER.explicit(3, DER.sequence(extensions(name: name)))
        let tbs = DER.sequence(tbsBody)
        let signature = try sign(tbs, privateKey: privateKey)
        return DER.sequence(tbs + algorithm + DER.bitString(signature))
    }

    private static func sign(_ tbs: Data, privateKey: SecKey) throws -> Data {
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw RemoteError.crypto("This key cannot sign a TLS certificate.")
        }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, tbs as CFData, &error) as Data? else {
            throw RemoteError.crypto("The TLS certificate signature failed.")
        }
        return signature
    }

    private static func serial() -> Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] &= 0x7F
        if bytes.allSatisfy({ $0 == 0 }) {
            bytes[7] = 1
        }
        return Data(bytes)
    }

    private static func directoryName(_ name: String) -> Data {
        let attribute = DER.sequence(DER.oid(commonName) + DER.utf8(name))
        return DER.sequence(DER.tlv(0x31, attribute))
    }

    private static func extensions(name _: String) -> Data {
        let constraintsValue = DER.sequence(DER.tlv(0x01, Data([0x00])))
        let constraints = extensionBlock(basicConstraints, critical: true, value: constraintsValue)
        let usageBits = DER.tlv(0x03, Data([0x07, 0x80]))
        let usage = extensionBlock(keyUsage, critical: true, value: usageBits)
        let ekuValue = DER.sequence(DER.oid(serverAuth))
        let eku = extensionBlock(extendedKeyUsage, critical: false, value: ekuValue)
        let sanValue = DER.sequence(DER.tlv(0x82, Data(Limits.tlsServerName.utf8)))
        let san = extensionBlock(subjectAltName, critical: false, value: sanValue)
        return constraints + usage + eku + san
    }

    private static func extensionBlock(_ oid: [UInt8], critical: Bool, value: Data) -> Data {
        var body = DER.oid(oid)
        if critical {
            body.append(DER.tlv(0x01, Data([0xFF])))
        }
        body.append(DER.octetString(value))
        return DER.sequence(body)
    }
}
