import Foundation

public struct TrackpadPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum TrackpadCommand: Equatable, Sendable {
    case move(PointerBatch)
    case button(MouseButtonBody)
    case scroll(ScrollBody)
    case key(KeyBody)
    case text(TextBody)
    case media(MediaBody)
    case launch(LaunchBody)
    case system(SystemBody)

    /// Merges consecutive moves and consecutive scrolls. A button stays between them.
    public static func coalesce(_ commands: [TrackpadCommand]) -> [TrackpadCommand] {
        var result: [TrackpadCommand] = []
        for command in commands {
            guard let last = result.last else {
                if let kept = nonzero(command) {
                    result.append(kept)
                }
                continue
            }
            switch (last, command) {
            case (.move(let prior), .move(let next)):
                let sample = PointerSample(
                    dx: clamp(deltaX(prior) + deltaX(next)),
                    dy: clamp(deltaY(prior) + deltaY(next))
                )
                if sample.dx == 0 && sample.dy == 0 {
                    result.removeLast()
                } else {
                    result[result.count - 1] = .move(PointerBatch(samples: [sample]))
                }
            case (.scroll(let prior), .scroll(let next)):
                let body = ScrollBody(
                    dx: clamp(Int64(prior.dx) + Int64(next.dx)),
                    dy: clamp(Int64(prior.dy) + Int64(next.dy))
                )
                if body.dx == 0 && body.dy == 0 {
                    result.removeLast()
                } else {
                    result[result.count - 1] = .scroll(body)
                }
            case (.text(let prior), .text(let next)):
                let combined = prior.text + next.text
                if combined.utf8.count <= Limits.maxTextBytes {
                    result[result.count - 1] = .text(TextBody(text: combined))
                } else if let kept = nonzero(command) {
                    result.append(kept)
                }
            default:
                if let kept = nonzero(command) {
                    result.append(kept)
                }
            }
        }
        return result
    }

    private static func nonzero(_ command: TrackpadCommand) -> TrackpadCommand? {
        switch command {
        case .move(let batch):
            let sample = PointerSample(dx: clamp(deltaX(batch)), dy: clamp(deltaY(batch)))
            guard sample.dx != 0 || sample.dy != 0 else { return nil }
            return .move(PointerBatch(samples: [sample]))
        case .scroll(let body):
            guard body.dx != 0 || body.dy != 0 else { return nil }
            return command
        case .button, .key, .media, .launch, .system:
            return command
        case .text(let body):
            guard !body.text.isEmpty else { return nil }
            return command
        }
    }

    private static func deltaX(_ batch: PointerBatch) -> Int64 {
        batch.samples.reduce(Int64(0)) { $0 + Int64($1.dx) }
    }

    private static func deltaY(_ batch: PointerBatch) -> Int64 {
        batch.samples.reduce(Int64(0)) { $0 + Int64($1.dy) }
    }

    private static func clamp(_ value: Int64) -> Int32 {
        let limit = Int64(Limits.maxPointerDelta)
        return Int32(min(limit, max(-limit, value)))
    }
}

/// Turns touch points into pointer, button, and scroll commands. It does not post events.
public struct TrackpadInterpreter: Sendable {
    public private(set) var sensitivity: Double
    public private(set) var dragMode: Bool

    private var fingers: [Int: Finger] = [:]
    private var leftHeld = false

    public init(sensitivity: Double = 1.2, dragMode: Bool = false) {
        self.sensitivity = min(3, max(0.4, sensitivity))
        self.dragMode = dragMode
    }

    public mutating func setSensitivity(_ value: Double) {
        sensitivity = min(3, max(0.4, value))
    }

    /// Releases the left button when drag mode turns off while it is held.
    public mutating func setDragMode(_ enabled: Bool, now: Date) -> [TrackpadCommand] {
        let wasEnabled = dragMode
        dragMode = enabled
        if wasEnabled && !enabled {
            return releaseLeft()
        }
        if !wasEnabled && enabled && fingers.count == 1 {
            return pressLeft()
        }
        return []
    }

    public mutating func begin(id: Int, at point: TrackpadPoint, now: Date) -> [TrackpadCommand] {
        begin(touches: [(id: id, at: point)], now: now)
    }

    /// Adds every touch from one event before deciding on a click, so two fingers landing together do not click.
    public mutating func begin(touches: [(id: Int, at: TrackpadPoint)], now: Date) -> [TrackpadCommand] {
        for touch in touches where fingers[touch.id] == nil {
            fingers[touch.id] = Finger(origin: touch.at, last: touch.at, moved: false, began: now)
        }
        if fingers.count >= 2 {
            let commands = releaseLeft()
            markMoved()
            return commands
        }
        guard dragMode else { return [] }
        return pressLeft()
    }

    public mutating func move(id: Int, to point: TrackpadPoint, now: Date) -> [TrackpadCommand] {
        guard var finger = fingers[id] else { return [] }
        let dx = point.x - finger.last.x
        let dy = point.y - finger.last.y
        finger.last = point
        fingers[id] = finger
        if fingers.count >= 2 {
            markMoved()
            return scroll(dx: dx / Double(fingers.count), dy: dy / Double(fingers.count))
        }
        let travel = hypot(point.x - finger.origin.x, point.y - finger.origin.y)
        if travel > Timing.slop {
            fingers[id]?.moved = true
        }
        guard fingers[id]?.moved == true || leftHeld else { return [] }
        return pointer(dx: dx, dy: dy)
    }

    public mutating func end(id: Int, at point: TrackpadPoint, now: Date) -> [TrackpadCommand] {
        guard let finger = fingers.removeValue(forKey: id) else { return [] }
        if !fingers.isEmpty {
            markMoved()
            return []
        }
        if leftHeld {
            return releaseLeft()
        }
        let travel = hypot(point.x - finger.origin.x, point.y - finger.origin.y)
        let duration = now.timeIntervalSince(finger.began)
        guard !dragMode, !finger.moved, travel <= Timing.slop, duration < Timing.tap else {
            return []
        }
        return [
            .button(MouseButtonBody(button: "left", phase: "down")),
            .button(MouseButtonBody(button: "left", phase: "up")),
        ]
    }

    /// Ends the touch without a tap. A held button is released.
    public mutating func cancel(id: Int, now: Date) -> [TrackpadCommand] {
        guard var finger = fingers[id] else { return [] }
        finger.moved = true
        fingers[id] = finger
        return end(id: id, at: finger.last, now: now)
    }

    /// Presses the left button after a still finger has rested long enough to drag.
    public mutating func tick(now: Date) -> [TrackpadCommand] {
        guard fingers.count == 1, let finger = fingers.values.first else { return [] }
        guard !finger.moved, !dragMode, !leftHeld else { return [] }
        guard now.timeIntervalSince(finger.began) >= Timing.hold else { return [] }
        return pressLeft()
    }

    public mutating func rightClick(now: Date) -> [TrackpadCommand] {
        var commands = releaseLeft()
        commands.append(.button(MouseButtonBody(button: "right", phase: "down")))
        commands.append(.button(MouseButtonBody(button: "right", phase: "up")))
        return commands
    }

    private mutating func pressLeft() -> [TrackpadCommand] {
        guard !leftHeld else { return [] }
        leftHeld = true
        return [.button(MouseButtonBody(button: "left", phase: "down"))]
    }

    private mutating func releaseLeft() -> [TrackpadCommand] {
        guard leftHeld else { return [] }
        leftHeld = false
        return [.button(MouseButtonBody(button: "left", phase: "up"))]
    }

    private mutating func markMoved() {
        for key in fingers.keys {
            fingers[key]?.moved = true
            if let last = fingers[key]?.last {
                fingers[key]?.origin = last
            }
        }
    }

    private func pointer(dx: Double, dy: Double) -> [TrackpadCommand] {
        guard let sample = scaled(dx: dx, dy: dy) else { return [] }
        return [.move(PointerBatch(samples: [sample]))]
    }

    private func scroll(dx: Double, dy: Double) -> [TrackpadCommand] {
        guard let sample = scaled(dx: dx, dy: dy) else { return [] }
        return [.scroll(ScrollBody(dx: sample.dx, dy: sample.dy))]
    }

    private func scaled(dx: Double, dy: Double) -> PointerSample? {
        let x = scale(dx)
        let y = scale(dy)
        guard x != 0 || y != 0 else { return nil }
        return PointerSample(dx: x, dy: y)
    }

    private func scale(_ value: Double) -> Int32 {
        let raw = (value * sensitivity).rounded()
        let limit = Double(Limits.maxPointerDelta)
        return Int32(min(limit, max(-limit, raw)))
    }

    private struct Finger {
        var origin: TrackpadPoint
        var last: TrackpadPoint
        var moved: Bool
        var began: Date
    }

    private enum Timing {
        static let slop = 12.0
        static let tap = 0.28
        static let hold = 0.35
    }
}
