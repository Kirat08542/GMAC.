import Foundation

/// Types into the focused Mac app. The Mac app supplies the implementation.
public protocol RemoteKeyboard: Sendable {
    func key(_ body: KeyBody) throws
    func text(_ body: TextBody) throws
    func release()
}

public struct DeniedKeyboard: RemoteKeyboard {
    public init() {}

    public func key(_ body: KeyBody) throws {
        throw RemoteError.invalid("Keyboard control is not running in this process.")
    }

    public func text(_ body: TextBody) throws {
        throw RemoteError.invalid("Keyboard control is not running in this process.")
    }

    public func release() {}
}

/// Sends the Mac media keys. The Mac app supplies the implementation.
public protocol RemoteMedia: Sendable {
    func perform(_ body: MediaBody) throws
}

public struct DeniedMedia: RemoteMedia {
    public init() {}

    public func perform(_ body: MediaBody) throws {
        throw RemoteError.invalid("Media control is not running in this process.")
    }
}

/// Puts the Mac to sleep. The Mac app supplies the implementation.
public protocol RemotePower: Sendable {
    func sleep() throws
}

public struct DeniedPower: RemotePower {
    public init() {}

    public func sleep() throws {
        throw RemoteError.invalid("Sleep is not running in this process.")
    }
}
