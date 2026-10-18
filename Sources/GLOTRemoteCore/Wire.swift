import Foundation
import Security

public enum ErrorCode {
    public static let revoked = "revoked"
    public static let mismatch = "mismatch"
    public static let denied = "denied"
    public static let expired = "expired"
    public static let unauthorized = "unauthorized"
    public static let unsupported = "unsupported"
    public static let invalid = "invalid"
    public static let version = "version"
    public static let busy = "busy"
}

public enum WireType {
    public static let hello = "hello"
    public static let helloAck = "helloAck"
    public static let pairConfirm = "pairConfirm"
    public static let pairResult = "pairResult"
    public static let authChallenge = "authChallenge"
    public static let authResponse = "authResponse"
    public static let authResult = "authResult"
    public static let heartbeat = "heartbeat"
    public static let ack = "ack"
    public static let test = "test"
    public static let error = "error"
    public static let bye = "bye"
    public static let pointer = "pointer"
    public static let mouse = "mouse"
    public static let scroll = "scroll"
    public static let key = "key"
    public static let text = "text"
    public static let media = "media"
    public static let launch = "launch"
    public static let apps = "apps"
    public static let system = "system"
    public static let clipPush = "clipPush"
    public static let clipPull = "clipPull"
    public static let clipData = "clipData"

    public static let session: Set<String> = [
        hello, helloAck, pairConfirm, pairResult,
        authChallenge, authResponse, authResult,
    ]

    public static let control: Set<String> = [
        pointer, mouse, scroll, key, text, media, launch, system, clipPush, clipPull, clipData,
    ]
}

public struct Envelope: Codable, Sendable, Equatable {
    public var v: UInt16
    public var id: UUID
    public var type: String
    public var payload: Data

    public init(type: String, payload: Data = Data(), id: UUID = UUID(), version: UInt16 = Limits.protocolVersion) {
        self.v = version
        self.id = id
        self.type = type
        self.payload = payload
    }
}

public struct ClientHello: Codable, Sendable, Equatable {
    public var versions: [UInt16]
    public var deviceID: UUID
    public var name: String
    public var publicKey: Data
    public var nonce: Data
    /// Set when the iPhone has no pinned Mac key and must compare pairing codes before it trusts the session.
    public var wantsPairing: Bool

    public init(versions: [UInt16], deviceID: UUID, name: String, publicKey: Data, nonce: Data, wantsPairing: Bool) {
        self.versions = versions
        self.deviceID = deviceID
        self.name = name
        self.publicKey = publicKey
        self.nonce = nonce
        self.wantsPairing = wantsPairing
    }
}

public struct ServerHello: Codable, Sendable, Equatable {
    public var version: UInt16
    public var deviceID: UUID
    public var name: String
    public var publicKey: Data
    public var nonce: Data
    public var paired: Bool
    /// MAC address of the Mac's Wi-Fi interface, for Wake-on-LAN. Nil when unavailable.
    public var macAddress: String?

    public init(version: UInt16, deviceID: UUID, name: String, publicKey: Data, nonce: Data, paired: Bool, macAddress: String? = nil) {
        self.version = version
        self.deviceID = deviceID
        self.name = name
        self.publicKey = publicKey
        self.nonce = nonce
        self.paired = paired
        self.macAddress = macAddress
    }
}

public struct PairConfirm: Codable, Sendable, Equatable {
    public var accept: Bool
    public init(accept: Bool) { self.accept = accept }
}

public struct PairResult: Codable, Sendable, Equatable {
    public var paired: Bool
    public var reason: String
    public init(paired: Bool, reason: String) {
        self.paired = paired
        self.reason = reason
    }
}

public struct AuthChallenge: Codable, Sendable, Equatable {
    public var challenge: Data
    public init(challenge: Data) { self.challenge = challenge }
}

public struct AuthResponse: Codable, Sendable, Equatable {
    public var signature: Data
    public init(signature: Data) { self.signature = signature }
}

public struct AuthResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public init(ok: Bool) { self.ok = ok }
}

public struct HeartbeatBody: Codable, Sendable, Equatable {
    public var seq: UInt64
    public init(seq: UInt64) { self.seq = seq }
}

public struct AckBody: Codable, Sendable, Equatable {
    public var ref: UUID
    public var ok: Bool
    public init(ref: UUID, ok: Bool) {
        self.ref = ref
        self.ok = ok
    }
}

public struct TestBody: Codable, Sendable, Equatable {
    public var nonce: Data
    public init(nonce: Data) { self.nonce = nonce }
}

public struct ErrorBody: Codable, Sendable, Equatable {
    public var ref: UUID?
    public var code: String
    public var message: String
    public init(ref: UUID?, code: String, message: String) {
        self.ref = ref
        self.code = code
        self.message = message
    }
}

public struct ByeBody: Codable, Sendable, Equatable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

public struct PointerSample: Codable, Sendable, Equatable {
    public var dx: Int32
    public var dy: Int32
    public init(dx: Int32, dy: Int32) {
        self.dx = dx
        self.dy = dy
    }
}

public struct PointerBatch: Codable, Sendable, Equatable {
    public var samples: [PointerSample]
    public init(samples: [PointerSample]) { self.samples = samples }
}

public struct MouseButtonBody: Codable, Sendable, Equatable {
    public var button: String
    public var phase: String
    public init(button: String, phase: String) {
        self.button = button
        self.phase = phase
    }
}

public struct ScrollBody: Codable, Sendable, Equatable {
    public var dx: Int32
    public var dy: Int32
    public init(dx: Int32, dy: Int32) {
        self.dx = dx
        self.dy = dy
    }
}

public struct KeyBody: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [String]
    public var phase: String
    public init(key: String, modifiers: [String], phase: String) {
        self.key = key
        self.modifiers = modifiers
        self.phase = phase
    }
}

public struct TextBody: Codable, Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct MediaBody: Codable, Sendable, Equatable {
    public var action: String
    public init(action: String) { self.action = action }
}

public struct LaunchBody: Codable, Sendable, Equatable {
    public var bundleID: String
    public init(bundleID: String) { self.bundleID = bundleID }
}

public struct AppRecord: Codable, Sendable, Equatable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct AppCatalog: Codable, Sendable, Equatable {
    public var apps: [AppRecord]
    public init(apps: [AppRecord]) { self.apps = apps }
}

public struct SystemBody: Codable, Sendable, Equatable {
    public var action: String
    public var confirmed: Bool
    public init(action: String, confirmed: Bool) {
        self.action = action
        self.confirmed = confirmed
    }
}

public struct ClipboardBody: Codable, Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public enum WireCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encodePayload<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    public static func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw RemoteError.invalid("The message payload is not valid.")
        }
    }

    public static func envelope<T: Encodable>(type: String, body: T, id: UUID = UUID()) throws -> Envelope {
        Envelope(type: type, payload: try encodePayload(body), id: id)
    }
}

public struct FrameBuffer: Sendable {
    private var storage = Data()

    public init() {}

    public mutating func append(_ chunk: Data, maxFrame: Int) throws -> [Data] {
        if chunk.count > Limits.maxBuffered || storage.count > Limits.maxBuffered - chunk.count {
            throw RemoteError.oversized
        }
        storage.append(chunk)
        var frames: [Data] = []
        while storage.count >= 4 {
            let declared = Self.readLength(storage)
            if declared <= 0 || declared > maxFrame {
                throw RemoteError.oversized
            }
            let total = 4 + declared
            if storage.count < total {
                break
            }
            frames.append(storage.subdata(in: 4..<total))
            storage.removeSubrange(0..<total)
        }
        return frames
    }

    private static func readLength(_ data: Data) -> Int {
        data.prefix(4).reduce(0) { partial, byte in
            (partial << 8) | Int(byte)
        }
    }
}

public enum FrameCodec {
    public static func encode(_ envelope: Envelope, maxFrame: Int = Limits.maxFrame) throws -> Data {
        let body = try WireCoding.encoder().encode(envelope)
        if body.count > maxFrame || body.isEmpty {
            throw RemoteError.oversized
        }
        var frame = Data(capacity: 4 + body.count)
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    public static func decode(_ frame: Data, maxFrame: Int = Limits.maxFrame) throws -> Envelope {
        if frame.count > maxFrame || frame.isEmpty {
            throw RemoteError.oversized
        }
        do {
            return try WireCoding.decoder().decode(Envelope.self, from: frame)
        } catch {
            throw RemoteError.invalid("The message could not be read.")
        }
    }
}

public enum DeviceName {
    public static func sanitize(_ raw: String, fallback: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar.value >= 32 && scalar.value != 127
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return fallback
        }
        return String(cleaned.prefix(Limits.maxNameLength))
    }
}

public enum RandomBytes {
    public static func generate(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw RemoteError.crypto("The system random generator failed.")
        }
        return Data(bytes)
    }
}
