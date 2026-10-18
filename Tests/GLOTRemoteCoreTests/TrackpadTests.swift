import Foundation
import Testing
@testable import GLOTRemoteCore

private let start = Date(timeIntervalSince1970: 1_000)

@Test func tapWhenTheFingerBarelyMoves() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    let began = pad.begin(id: 1, at: TrackpadPoint(x: 10, y: 10), now: start)
    let nudged = pad.move(id: 1, to: TrackpadPoint(x: 15, y: 12), now: start.addingTimeInterval(0.05))
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 15, y: 12), now: start.addingTimeInterval(0.12))
    #expect(began.isEmpty)
    #expect(nudged.isEmpty)
    #expect(ended == leftClick)
}

@Test func movementPastTheSlopDoesNotClick() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let moved = pad.move(id: 1, to: TrackpadPoint(x: 20, y: -8), now: start.addingTimeInterval(0.05))
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 20, y: -8), now: start.addingTimeInterval(0.1))
    #expect(moved == [.move(PointerBatch(samples: [PointerSample(dx: 20, dy: -8)]))])
    #expect(ended.isEmpty)
}

@Test func aSecondTapIsAnotherClick() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    let first = tap(&pad, at: 0)
    let second = tap(&pad, at: 0.4)
    #expect(first == leftClick)
    #expect(second == leftClick)
}

@Test func twoFingersScrollAndDoNotClick() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    let first = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let second = pad.begin(id: 2, at: TrackpadPoint(x: 40, y: 0), now: start)
    let scrolled = pad.move(id: 1, to: TrackpadPoint(x: 0, y: 30), now: start.addingTimeInterval(0.05))
    let liftOne = pad.end(id: 2, at: TrackpadPoint(x: 40, y: 0), now: start.addingTimeInterval(0.1))
    let liftTwo = pad.end(id: 1, at: TrackpadPoint(x: 0, y: 30), now: start.addingTimeInterval(0.12))
    #expect(first.isEmpty)
    #expect(second.isEmpty)
    #expect(scrolled == [.scroll(ScrollBody(dx: 0, dy: 15))])
    #expect(liftOne.isEmpty)
    #expect(liftTwo.isEmpty)
}

@Test func twoFingersLandingTogetherDoNotClickInDragMode() {
    var pad = TrackpadInterpreter(sensitivity: 1, dragMode: true)
    let began = pad.begin(
        touches: [(id: 1, at: TrackpadPoint(x: 0, y: 0)), (id: 2, at: TrackpadPoint(x: 30, y: 0))],
        now: start
    )
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start.addingTimeInterval(0.2))
    let last = pad.end(id: 2, at: TrackpadPoint(x: 30, y: 0), now: start.addingTimeInterval(0.2))
    #expect(began.isEmpty)
    #expect(ended.isEmpty)
    #expect(last.isEmpty)
}

@Test func dragModeHoldsTheLeftButton() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    #expect(pad.setDragMode(true, now: start).isEmpty)
    let began = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let moved = pad.move(id: 1, to: TrackpadPoint(x: 18, y: 4), now: start.addingTimeInterval(0.05))
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 18, y: 4), now: start.addingTimeInterval(0.2))
    #expect(began == [.button(leftDown)])
    #expect(moved == [.move(PointerBatch(samples: [PointerSample(dx: 18, dy: 4)]))])
    #expect(ended == [.button(leftUp)])
}

@Test func leavingDragModeReleasesTheButton() {
    var pad = TrackpadInterpreter(sensitivity: 1, dragMode: true)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let released = pad.setDragMode(false, now: start.addingTimeInterval(0.1))
    #expect(released == [.button(leftUp)])
    #expect(!pad.dragMode)
}

@Test func aStillFingerPressesAfterTheHoldDelay() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 4, y: 4), now: start)
    let early = pad.tick(now: start.addingTimeInterval(0.2))
    let held = pad.tick(now: start.addingTimeInterval(0.38))
    let moved = pad.move(id: 1, to: TrackpadPoint(x: 9, y: 6), now: start.addingTimeInterval(0.45))
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 9, y: 6), now: start.addingTimeInterval(0.5))
    #expect(early.isEmpty)
    #expect(held == [.button(leftDown)])
    #expect(moved == [.move(PointerBatch(samples: [PointerSample(dx: 5, dy: 2)]))])
    #expect(ended == [.button(leftUp)])
}

@Test func aSlowPressWithoutTheHoldTickDoesNotClick() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let ended = pad.end(id: 1, at: TrackpadPoint(x: 1, y: 1), now: start.addingTimeInterval(0.5))
    #expect(ended.isEmpty)
}

@Test func rightClickReleasesAHeldLeftButton() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    _ = pad.tick(now: start.addingTimeInterval(0.4))
    let clicked = pad.rightClick(now: start.addingTimeInterval(0.45))
    #expect(clicked == [.button(leftUp), .button(rightDown), .button(rightUp)])
}

@Test func sensitivityScalesMovementAndClamps() {
    var pad = TrackpadInterpreter(sensitivity: 2)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let moved = pad.move(id: 1, to: TrackpadPoint(x: 20, y: 0), now: start)
    pad.setSensitivity(9)
    #expect(pad.sensitivity == 3)
    pad.setSensitivity(0.1)
    #expect(pad.sensitivity == 0.4)
    #expect(moved == [.move(PointerBatch(samples: [PointerSample(dx: 40, dy: 0)]))])
}

@Test func cancellingATouchDoesNotClick() {
    var pad = TrackpadInterpreter(sensitivity: 1)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let cancelled = pad.cancel(id: 1, now: start.addingTimeInterval(0.05))
    #expect(cancelled.isEmpty)
}

@Test func cancellingADragReleasesTheButton() {
    var pad = TrackpadInterpreter(sensitivity: 1, dragMode: true)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 0, y: 0), now: start)
    let cancelled = pad.cancel(id: 1, now: start.addingTimeInterval(0.05))
    #expect(cancelled == [.button(leftUp)])
}

@Test func coalesceSumsMovesUntilAButton() {
    let merged = TrackpadCommand.coalesce([
        .move(PointerBatch(samples: [PointerSample(dx: 4, dy: 1)])),
        .move(PointerBatch(samples: [PointerSample(dx: 5, dy: -1)])),
        .button(leftDown),
        .move(PointerBatch(samples: [PointerSample(dx: 2, dy: 3)])),
        .scroll(ScrollBody(dx: 1, dy: 2)),
        .scroll(ScrollBody(dx: 3, dy: -2)),
    ])
    #expect(merged == [
        .move(PointerBatch(samples: [PointerSample(dx: 9, dy: 0)])),
        .button(leftDown),
        .move(PointerBatch(samples: [PointerSample(dx: 2, dy: 3)])),
        .scroll(ScrollBody(dx: 4, dy: 0)),
    ])
}

@Test func pointerCommandsAreAcceptedWhenAuthenticated() throws {
    let pointer = try WireCoding.encodePayload(PointerBatch(samples: [PointerSample(dx: 4, dy: -3)]))
    let mouse = try WireCoding.encodePayload(MouseButtonBody(button: "left", phase: "down"))
    let scroll = try WireCoding.encodePayload(ScrollBody(dx: 0, dy: 12))
    let key = try WireCoding.encodePayload(KeyBody(key: "c", modifiers: ["command"], phase: "down"))
    #expect(ControlPolicy.decide(type: WireType.pointer, authenticated: true, payload: pointer) == .handle)
    #expect(ControlPolicy.decide(type: WireType.mouse, authenticated: true, payload: mouse) == .handle)
    #expect(ControlPolicy.decide(type: WireType.scroll, authenticated: true, payload: scroll) == .handle)
    #expect(ControlPolicy.decide(type: WireType.key, authenticated: true, payload: key) == .handle)
    #expect(throws: RemoteError.invalid("Pointer control is not running in this process.")) {
        try DeniedPointer().move([PointerSample(dx: 1, dy: 0)])
    }
}

private let leftDown = MouseButtonBody(button: "left", phase: "down")
private let leftUp = MouseButtonBody(button: "left", phase: "up")
private let rightDown = MouseButtonBody(button: "right", phase: "down")
private let rightUp = MouseButtonBody(button: "right", phase: "up")
private let leftClick: [TrackpadCommand] = [.button(leftDown), .button(leftUp)]

private func tap(_ pad: inout TrackpadInterpreter, at offset: TimeInterval) -> [TrackpadCommand] {
    let moment = start.addingTimeInterval(offset)
    _ = pad.begin(id: 1, at: TrackpadPoint(x: 8, y: 8), now: moment)
    return pad.end(id: 1, at: TrackpadPoint(x: 8, y: 8), now: moment.addingTimeInterval(0.1))
}
