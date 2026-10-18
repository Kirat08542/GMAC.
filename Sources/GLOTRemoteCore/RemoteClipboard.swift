import Foundation

/// Moves text through the system pasteboards. The Mac app supplies the implementation.
/// Every transfer is user-initiated from the iPhone; nothing syncs on its own.
public protocol RemoteClipboard: Sendable {
    /// Copies text into the Mac pasteboard.
    func push(_ body: ClipboardBody) throws
    /// Reads text from the Mac pasteboard.
    func pull() throws -> ClipboardBody
}

public struct DeniedClipboard: RemoteClipboard {
    public init() {}

    public func push(_ body: ClipboardBody) throws {
        throw RemoteError.invalid("Clipboard sharing is not running in this process.")
    }

    public func pull() throws -> ClipboardBody {
        throw RemoteError.invalid("Clipboard sharing is not running in this process.")
    }
}
