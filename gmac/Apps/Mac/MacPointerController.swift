import AppKit
import GLOTRemoteCore

/// Posts pointer events only while this process is trusted for Accessibility.
final class MacPointerController: RemotePointer, @unchecked Sendable {
    static let permissionMessage = "Allow Accessibility for GLOT Remote Mac in System Settings. The pointer was not moved."

    private let lock = NSLock()
    private let source: CGEventSource?
    private var leftDown = false
    private var rightDown = false
    private var leftClickState: Int64 = 0
    private var lastLeftUp = Date.distantPast

    init() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        self.source = source
    }

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func move(_ samples: [PointerSample]) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTrust()
        for sample in samples {
            guard sample.dx != 0 || sample.dy != 0 else { continue }
            let type: CGEventType
            let button: CGMouseButton
            if leftDown {
                type = .leftMouseDragged
                button = .left
            } else if rightDown {
                type = .rightMouseDragged
                button = .right
            } else {
                type = .mouseMoved
                button = .left
            }
            try post(type: type, button: button, dx: sample.dx, dy: sample.dy, clickState: leftDown ? leftClickState : 0)
        }
    }

    func button(_ body: MouseButtonBody) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTrust()
        let down = body.phase == "down"
        switch body.button {
        case "left":
            guard leftDown != down else { return }
            let clickState = down ? nextLeftClickState() : leftClickState
            try post(
                type: down ? .leftMouseDown : .leftMouseUp,
                button: .left,
                dx: 0,
                dy: 0,
                clickState: clickState
            )
            leftDown = down
            if !down {
                lastLeftUp = Date()
            }
        case "right":
            guard rightDown != down else { return }
            try post(
                type: down ? .rightMouseDown : .rightMouseUp,
                button: .right,
                dx: 0,
                dy: 0,
                clickState: 1
            )
            rightDown = down
        default:
            throw RemoteError.invalid("The mouse button is not supported.")
        }
    }

    func scroll(_ body: ScrollBody) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTrust()
        guard body.dx != 0 || body.dy != 0 else { return }
        // Finger motion uses a top-left origin. A downward finger is a negative wheel so content follows the finger.
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: -body.dy,
            wheel2: body.dx,
            wheel3: 0
        ) else {
            throw RemoteError.invalid("macOS did not create a pointer event.")
        }
        event.post(tap: .cghidEventTap)
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        let trusted = AXIsProcessTrusted()
        if leftDown {
            leftDown = false
            if trusted {
                try? post(type: .leftMouseUp, button: .left, dx: 0, dy: 0, clickState: leftClickState)
            }
        }
        if rightDown {
            rightDown = false
            if trusted {
                try? post(type: .rightMouseUp, button: .right, dx: 0, dy: 0, clickState: 1)
            }
        }
    }

    private func requireTrust() throws {
        guard AXIsProcessTrusted() else {
            throw RemoteError.invalid(Self.permissionMessage)
        }
    }

    private func nextLeftClickState() -> Int64 {
        if Date().timeIntervalSince(lastLeftUp) <= NSEvent.doubleClickInterval, leftClickState >= 1 {
            leftClickState += 1
        } else {
            leftClickState = 1
        }
        return leftClickState
    }

    private func post(type: CGEventType, button: CGMouseButton, dx: Int32, dy: Int32, clickState: Int64) throws {
        guard let current = CGEvent(source: nil)?.location else {
            throw RemoteError.invalid("macOS did not create a pointer event.")
        }
        let next = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: next,
            mouseButton: button
        ) else {
            throw RemoteError.invalid("macOS did not create a pointer event.")
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.post(tap: .cghidEventTap)
    }
}
