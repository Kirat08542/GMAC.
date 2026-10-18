import Foundation

/// Posts pointer, button, and scroll actions. The Mac app supplies the implementation.
/// The iOS library uses `DeniedPointer` and never imports CoreGraphics.
public protocol RemotePointer: Sendable {
    func move(_ samples: [PointerSample]) throws
    func button(_ body: MouseButtonBody) throws
    func scroll(_ body: ScrollBody) throws
    func release()
}

public struct DeniedPointer: RemotePointer {
    public init() {}

    public func move(_ samples: [PointerSample]) throws {
        throw RemoteError.invalid("Pointer control is not running in this process.")
    }

    public func button(_ body: MouseButtonBody) throws {
        throw RemoteError.invalid("Pointer control is not running in this process.")
    }

    public func scroll(_ body: ScrollBody) throws {
        throw RemoteError.invalid("Pointer control is not running in this process.")
    }

    public func release() {}
}
