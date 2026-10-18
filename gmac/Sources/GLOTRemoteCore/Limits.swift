import Foundation

public enum Limits {
    public static let protocolVersion: UInt16 = 1
    public static let maxFrame = 65_536
    public static let maxBuffered = 128 * 1024
    public static let maxNameLength = 64
    public static let nonceLength = 32
    public static let signingKeyLength = 64
    public static let tlsPublicKeyLength = 65
    public static let maxTextBytes = 4_000
    public static let maxClipboardBytes = 16_384
    public static let maxPointerSamples = 32
    public static let maxPointerDelta = 10_000
    public static let maxInvalidMessages = 8
    public static let maxMessagesPerSecond = 40
    public static let serviceType = "_glotremote._tcp"
    /// Certificate SAN and TLS server name. Authentication is the pinned key, not this name.
    public static let tlsServerName = "glotremote.local"
}

public struct TransportConfig: Sendable, Equatable {
    public var connectTimeout: Duration
    public var pairingTimeout: Duration
    public var heartbeatInterval: Duration
    public var livenessTimeout: Duration
    public var maxFrameSize: Int
    public var autoReconnect: Bool
    public var reconnectAttempts: Int

    public init(
        connectTimeout: Duration = .seconds(10),
        pairingTimeout: Duration = .seconds(90),
        heartbeatInterval: Duration = .seconds(5),
        livenessTimeout: Duration = .seconds(16),
        maxFrameSize: Int = Limits.maxFrame,
        autoReconnect: Bool = true,
        reconnectAttempts: Int = 8
    ) {
        self.connectTimeout = connectTimeout
        self.pairingTimeout = pairingTimeout
        self.heartbeatInterval = heartbeatInterval
        self.livenessTimeout = livenessTimeout
        self.maxFrameSize = maxFrameSize
        self.autoReconnect = autoReconnect
        self.reconnectAttempts = reconnectAttempts
    }
}

public enum DurationClock {
    public static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

public enum ReconnectPolicy: Sendable {
    /// Delays of 1s, 2s, 4s, 8s, then 15s.
    public static func delay(afterFailedAttempt attempt: Int) -> Duration {
        let shift = min(max(attempt, 0), 4)
        let seconds = min(15, 1 << shift)
        return .seconds(seconds)
    }
}
