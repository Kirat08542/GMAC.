import GLOTRemoteCore
import SwiftUI
import UIKit

// Pad — Night Console redesign. All gesture and scroll logic is unchanged;
// only the chrome is new: dot-grid surface, docked scroll rail, floating deck.
struct TrackpadScreen: View {
    @Bindable var model: PhoneModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 0) {
                    pad
                    rail
                    deck
                        .frame(width: 208)
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        pad
                        rail
                    }
                    deck
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(RemoteTheme.canvas)
        .clipped()
    }

    private var pad: some View {
        ZStack {
            DotGrid()
            TrackpadSurface(model: model, enabled: model.isReady)
            GateNote(text: gateCopy)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad")
        .accessibilityHint("One finger moves the pointer. Two fingers scroll.")
    }

    private var rail: some View {
        ScrollWheel(enabled: model.isReady, sensitivity: model.sensitivity) { dy in
            model.sendRemote([.scroll(ScrollBody(dx: 0, dy: dy))])
        }
    }

    private var deck: some View {
        Group {
            if verticalSizeClass == .compact {
                VStack(spacing: 10) { deckContent }
            } else {
                HStack(spacing: 16) { deckContent }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RemoteTheme.plate, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var deckContent: some View {
        LatchKey(
            title: "Drag",
            symbol: "hand.draw",
            latched: model.dragMode,
            enabled: model.isReady
        ) {
            model.setDragMode(!model.dragMode)
        }
        .accessibilityHint("Locks the pointer down for dragging")

        VStack(spacing: 6) {
            Text("SPEED")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(RemoteTheme.tertiary)
            HStack(spacing: 10) {
                StepperKey(symbol: "minus", label: "Decrease pointer speed", enabled: model.isReady) {
                    model.setSensitivity(max(0.5, model.sensitivity - 0.1))
                }
                Text(model.sensitivity.formatted(.number.precision(.fractionLength(1))))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(RemoteTheme.secondary)
                    .frame(minWidth: 36)
                    .accessibilityHidden(true)
                StepperKey(symbol: "plus", label: "Increase pointer speed", enabled: model.isReady) {
                    model.setSensitivity(min(2.5, model.sensitivity + 0.1))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pointer speed")

        Button {
            model.rightClick()
        } label: {
            Text("Right-click")
                .font(.body.weight(.semibold))
                .foregroundStyle(RemoteTheme.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
        }
        .remoteKey()
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.45)
        .accessibilityLabel("Right click")
    }

    private var gateCopy: String? {
        guard !model.isReady else { return nil }
        if case .pairing = model.snapshot.state {
            return "Compare the pairing code on Link."
        }
        return "Open Link to connect."
    }
}

private struct ScrollWheel: View {
    var enabled: Bool
    var sensitivity: Double
    var onScroll: (Int32) -> Void

    private let groove: CGFloat = 16
    @State private var roll: CGFloat = 0
    @State private var velocity: Double = 0
    @State private var lastSample: Date?
    @State private var coast: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            roller
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
                .allowsHitTesting(false)
            WheelDrag(
                onBegin: {
                    coast?.cancel()
                    velocity = 0
                    lastSample = nil
                },
                onDelta: { delta in
                    note(delta)
                    send(delta)
                },
                onEnd: { release() }
            )
        }
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(RemoteTheme.well)
        .overlay(alignment: .leading) {
            Rectangle().fill(RemoteTheme.hairline).frame(width: 1)
        }
        .clipped()
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel("Scroll")
        .accessibilityHint("Drag up or down. A flick keeps rolling.")
        .accessibilityAdjustableAction { direction in
            let points: CGFloat = direction == .increment ? -48 : 48
            roll += points
            send(points)
        }
        .onChange(of: enabled) { _, ready in
            if !ready { stopCoast() }
        }
        .onDisappear { stopCoast() }
    }

    private var roller: some View {
        GeometryReader { geo in
            let shift = positiveRemainder(roll, groove)
            let count = Int(ceil(geo.size.height / groove)) + 3
            ZStack(alignment: .top) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(RemoteTheme.secondary)
                        .frame(width: 18, height: 3)
                        .frame(maxWidth: .infinity)
                        .offset(y: CGFloat(index) * groove + shift - groove)
                }
            }
        }
        .clipped()
    }

    private func note(_ delta: CGFloat) {
        let now = Date()
        if let lastSample {
            let dt = now.timeIntervalSince(lastSample)
            if dt > 0.001, dt < 0.08 {
                let sample = Double(delta) / dt
                velocity = velocity * 0.35 + sample * 0.65
            }
        }
        lastSample = now
        roll += delta
    }

    private func release() {
        if let lastSample, Date().timeIntervalSince(lastSample) > 0.08 {
            velocity = 0
        }
        lastSample = nil
        guard !reduceMotion, abs(velocity) > 120 else {
            velocity = 0
            return
        }
        coast?.cancel()
        coast = Task { @MainActor in
            var previous = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let now = Date()
                let dt = min(0.05, now.timeIntervalSince(previous))
                previous = now
                velocity *= exp(-2.4 * dt)
                let step = velocity * dt
                if abs(step) < 0.45 {
                    velocity = 0
                    return
                }
                roll += CGFloat(step)
                send(CGFloat(step))
            }
        }
    }

    private func stopCoast() {
        coast?.cancel()
        coast = nil
        velocity = 0
    }

    private func positiveRemainder(_ value: CGFloat, _ divisor: CGFloat) -> CGFloat {
        let raw = value.truncatingRemainder(dividingBy: divisor)
        return raw < 0 ? raw + divisor : raw
    }

    private func send(_ points: CGFloat) {
        guard enabled else { return }
        let raw = (Double(points) * sensitivity).rounded()
        let limit = Double(Limits.maxPointerDelta)
        let clamped = min(limit, max(-limit, raw))
        let dy = Int32(clamped)
        guard dy != 0 else { return }
        onScroll(dy)
    }
}

private struct WheelDrag: UIViewRepresentable {
    var onBegin: () -> Void
    var onDelta: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> WheelDragView {
        let view = WheelDragView()
        view.onBegin = onBegin
        view.onDelta = onDelta
        view.onEnd = onEnd
        return view
    }

    func updateUIView(_ view: WheelDragView, context: Context) {
        view.onBegin = onBegin
        view.onDelta = onDelta
        view.onEnd = onEnd
    }
}

final class WheelDragView: UIView {
    var onBegin: (() -> Void)?
    var onDelta: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var lastY: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastY = touches.first?.location(in: self).y
        let onBegin = onBegin
        MainActor.assumeIsolated {
            onBegin?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let previous = lastY ?? y
        lastY = y
        let delta = y - previous
        guard delta != 0 else { return }
        let onDelta = onDelta
        MainActor.assumeIsolated {
            onDelta?(delta)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    private func finish() {
        lastY = nil
        let onEnd = onEnd
        MainActor.assumeIsolated {
            onEnd?()
        }
    }
}

struct TrackpadSurface: UIViewRepresentable {
    var model: PhoneModel
    var enabled: Bool

    func makeUIView(context: Context) -> TrackpadTouchView {
        let view = TrackpadTouchView()
        view.isMultipleTouchEnabled = true
        bind(view)
        return view
    }

    func updateUIView(_ view: TrackpadTouchView, context: Context) {
        bind(view)
        view.isUserInteractionEnabled = enabled
        view.alpha = enabled ? 1 : 0.45
        if !enabled {
            view.cancelActiveTouches()
        }
    }

    private func bind(_ view: TrackpadTouchView) {
        view.hook.onBegin = { [weak model] touches in
            model?.trackpadBegan(touches)
        }
        view.hook.onMove = { [weak model] id, point in
            model?.trackpadMoved(id: id, to: point)
        }
        view.hook.onEnd = { [weak model] id, point in
            model?.trackpadEnded(id: id, at: point)
        }
        view.hook.onCancel = { [weak model] id in
            model?.trackpadCancelled(id: id)
        }
        view.hook.onTick = { [weak model] date in
            model?.trackpadTick(date)
        }
    }
}

final class TrackpadTouchView: UIView {
    let hook = TrackpadHook()

    private var active: [ObjectIdentifier: Int] = [:]
    private var nextID = 1
    private var ticker: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Trackpad"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopTicker()
        }
    }

    func cancelActiveTouches() {
        let ids = Array(active.values)
        active.removeAll()
        stopTicker()
        guard !ids.isEmpty else { return }
        let hook = hook
        MainActor.assumeIsolated {
            for id in ids {
                hook.onCancel?(id)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let began = touches.map { (id: identify($0), at: location(of: $0)) }
        let hook = hook
        MainActor.assumeIsolated {
            hook.onBegin?(began)
        }
        startTicker()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let hook = hook
        for touch in touches {
            guard let id = active[ObjectIdentifier(touch)] else { continue }
            let point = location(of: touch)
            MainActor.assumeIsolated {
                hook.onMove?(id, point)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let hook = hook
        for touch in touches {
            guard let id = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            let point = location(of: touch)
            MainActor.assumeIsolated {
                hook.onEnd?(id, point)
            }
        }
        if active.isEmpty {
            stopTicker()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let hook = hook
        for touch in touches {
            guard let id = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            let point = location(of: touch)
            MainActor.assumeIsolated {
                hook.onCancel?(id)
            }
        }
        if active.isEmpty {
            stopTicker()
        }
    }

    private func identify(_ touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if let id = active[key] {
            return id
        }
        let id = nextID
        nextID += 1
        active[key] = id
        return id
    }

    private func location(of touch: UITouch) -> TrackpadPoint {
        let point = touch.location(in: self)
        return TrackpadPoint(x: Double(point.x), y: Double(point.y))
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let hook = hook
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                hook.onTick?(Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

final class TrackpadHook: @unchecked Sendable {
    var onBegin: (@MainActor ([(id: Int, at: TrackpadPoint)]) -> Void)?
    var onMove: (@MainActor (Int, TrackpadPoint) -> Void)?
    var onEnd: (@MainActor (Int, TrackpadPoint) -> Void)?
    var onCancel: (@MainActor (Int) -> Void)?
    var onTick: (@MainActor (Date) -> Void)?
}
