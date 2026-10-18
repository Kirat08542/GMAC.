import GLOTRemoteCore
import SwiftUI
import UIKit

struct TrackpadScreen: View {
    @Bindable var model: PhoneModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                TrackpadSurface(model: model, enabled: model.isReady)
                if let gate = gateCopy {
                    Text(gate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RemoteTheme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Trackpad")
            .accessibilityHint("One finger moves the pointer. Two fingers scroll.")
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 22)
            controls
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .remotePlate(radius: 36)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(RemoteTheme.canvas)
    }

    private var gateCopy: String? {
        guard !model.isReady else { return nil }
        if case .pairing = model.snapshot.state {
            return "Compare the pairing code on Link."
        }
        return "Open Link to connect."
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Toggle(isOn: Binding(
                    get: { model.dragMode },
                    set: { model.setDragMode($0) }
                )) {
                    Text("Drag")
                        .font(.body.weight(.medium))
                        .foregroundStyle(RemoteTheme.text)
                }
                .toggleStyle(.switch)
                .disabled(!model.isReady)
                Spacer(minLength: 12)
                Text("Speed \(model.sensitivity.formatted(.number.precision(.fractionLength(1))))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(RemoteTheme.secondary)
                    .accessibilityHidden(true)
            }
            Slider(value: Binding(
                get: { model.sensitivity },
                set: { model.setSensitivity($0) }
            ), in: 0.5...2.5)
            .accessibilityLabel("Pointer speed")
            Button {
                model.rightClick()
            } label: {
                Text("Right Click")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .remoteButton()
            .disabled(!model.isReady)
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
