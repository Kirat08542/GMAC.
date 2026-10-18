import CryptoKit
import Foundation

public enum PairingCode {
    public static func digest(
        serverPublicKey: Data,
        clientPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data
    ) -> SHA256.Digest {
        var transcript = Data("GLOTRemote-pair-v1".utf8)
        transcript.append(serverPublicKey)
        transcript.append(clientPublicKey)
        transcript.append(clientNonce)
        transcript.append(serverNonce)
        return SHA256.hash(data: transcript)
    }

    /// Six digits derived from the handshake transcript.
    /// Both screens show this. The user has to compare them. The code is not sent across the network.
    public static func make(
        serverPublicKey: Data,
        clientPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data
    ) -> String {
        let digest = digest(
            serverPublicKey: serverPublicKey,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
        let value = digest.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        return String(format: "%06d", value % 1_000_000)
    }
}

public enum PairingOutcome: Sendable, Equatable {
    case pending
    case approved
    case denied
    case expired
}

public struct PairingGate: Sendable, Equatable {
    public var clientAccepted: Bool?
    public var serverAccepted: Bool?
    public var deadline: Date

    public init(deadline: Date) {
        self.deadline = deadline
    }

    public func result(now: Date) -> PairingOutcome {
        if now >= deadline {
            return .expired
        }
        if clientAccepted == false || serverAccepted == false {
            return .denied
        }
        if clientAccepted == true && serverAccepted == true {
            return .approved
        }
        return .pending
    }
}

public enum TrustDecision: Sendable, Equatable {
    case authenticate
    case pair
    case reject(String)
}

public enum Trust {
    public static func decide(record: PairedPhone?, presentedKey: Data) -> TrustDecision {
        guard let record else {
            return .pair
        }
        if record.revoked {
            return .reject("revoked")
        }
        if record.signingKey != presentedKey {
            return .reject("mismatch")
        }
        return .authenticate
    }
}

public struct PairedPhone: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var signingKey: Data
    public var pairedAt: Date
    public var revoked: Bool
    public var lastConnected: Date?

    public init(
        id: UUID,
        name: String,
        signingKey: Data,
        pairedAt: Date,
        revoked: Bool = false,
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.signingKey = signingKey
        self.pairedAt = pairedAt
        self.revoked = revoked
        self.lastConnected = lastConnected
    }
}

public struct PairedMac: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var tlsPublicKey: Data
    public var observedPeerKey: Data
    public var pairedAt: Date
    public var lastConnected: Date?
    /// MAC address learned from the Mac, for Wake-on-LAN. Nil until a session shares one.
    public var wakeMAC: String?

    public init(
        id: UUID,
        name: String,
        tlsPublicKey: Data,
        observedPeerKey: Data,
        pairedAt: Date,
        lastConnected: Date? = nil,
        wakeMAC: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tlsPublicKey = tlsPublicKey
        self.observedPeerKey = observedPeerKey
        self.pairedAt = pairedAt
        self.lastConnected = lastConnected
        self.wakeMAC = wakeMAC
    }
}

public enum DeviceSignature {
    public static func message(
        challenge: Data,
        serverPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        clientID: UUID
    ) -> Data {
        var data = Data("GLOTRemote-auth-v1".utf8)
        data.append(challenge)
        data.append(serverPublicKey)
        data.append(clientNonce)
        data.append(serverNonce)
        withUnsafeBytes(of: clientID.uuid) { data.append(contentsOf: $0) }
        return data
    }

    public static func sign(_ message: Data, with key: P256.Signing.PrivateKey) throws -> Data {
        let signature = try key.signature(for: message)
        return signature.derRepresentation
    }

    public static func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(rawRepresentation: publicKey),
              let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return key.isValidSignature(parsed, for: message)
    }
}

public enum PeerKey {
    /// `canonical` is the 65-byte uncompressed P-256 point.
    /// `sec_protocol_metadata_copy_peer_public_key` returns a 91-byte SubjectPublicKeyInfo
    /// that ends with that point. Measured on the macOS 27 Network stack.
    public static func matches(canonical: Data, observed: Data) -> Bool {
        guard canonical.count == Limits.tlsPublicKeyLength, canonical.first == 0x04 else {
            return false
        }
        if constantTimeEqual(canonical, observed) {
            return true
        }
        guard observed.count == 91 else {
            return false
        }
        return constantTimeEqual(Data(observed.suffix(canonical.count)), canonical)
    }

    public static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

public enum Fingerprint {
    public static func short(_ key: Data) -> String {
        SHA256.hash(data: key).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SigningIdentity: Sendable {
    public let deviceID: UUID
    public let privateKey: P256.Signing.PrivateKey

    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    public init(deviceID: UUID, privateKey: P256.Signing.PrivateKey) {
        self.deviceID = deviceID
        self.privateKey = privateKey
    }

    public static func ephemeral(id: UUID = UUID()) -> SigningIdentity {
        SigningIdentity(deviceID: id, privateKey: P256.Signing.PrivateKey())
    }
}
