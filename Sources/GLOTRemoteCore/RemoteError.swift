import Foundation

public enum RemoteError: Error, Sendable, Equatable {
    case closed
    case timeout
    case oversized
    case unauthorized
    case revoked
    case pairingFailed
    case pairingExpired
    case tlsUntrusted
    case notReady
    case versionMismatch
    case cancelled
    case busy
    case keychain(String)
    case crypto(String)
    case invalid(String)

    public var safeDescription: String {
        switch self {
        case .closed:
            "The connection closed."
        case .timeout:
            "The connection timed out."
        case .oversized:
            "A message was larger than the protocol allows."
        case .unauthorized:
            "The command was rejected because the session is not authenticated."
        case .revoked:
            "This iPhone was revoked on the Mac."
        case .pairingFailed:
            "Pairing was denied."
        case .pairingExpired:
            "Pairing expired. Try again."
        case .tlsUntrusted:
            "The Mac identity did not match the paired device."
        case .notReady:
            "The session is not ready."
        case .versionMismatch:
            "The other device speaks a different protocol version."
        case .cancelled:
            "The connection was cancelled."
        case .busy:
            "The Mac is already in a session."
        case .keychain(let detail):
            "Keychain error: \(detail)"
        case .crypto(let detail):
            "Cryptography error: \(detail)"
        case .invalid(let detail):
            detail
        }
    }
}
