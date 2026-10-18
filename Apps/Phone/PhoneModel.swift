import Foundation
import GLOTRemoteCore
import Observation
import UIKit

@MainActor
@Observable
final class PhoneModel {
    var macs: [DiscoveredMac] = []
    var snapshot = SessionSnapshot(state: .idle)
    var paired: [PairedMac] = []
    var displayName = "iPhone"
    var startupError: String?
    var actionError: String?
    var testNote = ""
    var discoveryNote = ""
    var clipboardNote = ""
    var wakeNote = ""
    var busy = false
    var sensitivity = 1.2
    var dragMode = false
    var apps: [AppRecord] = []

    @ObservationIgnored private var client: RemoteControlClient?
    @ObservationIgnored private var pad = TrackpadInterpreter()
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var pendingControls: [TrackpadCommand] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var browser: MacBrowser?
    @ObservationIgnored private var discoveryContinuation: AsyncStream<[DiscoveredMac]>.Continuation?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    var isReady: Bool {
        if case .ready = snapshot.state { return true }
        return false
    }

    func prepare() async {
        guard client == nil else { return }
        let folder: URL
        do {
            folder = try SupportDirectory.url(folder: "GLOT Remote")
        } catch {
            startupError = "The app could not open its local storage."
            return
        }
        displayName = storedName(in: folder)
        sensitivity = storedSensitivity(in: folder)
        pad.setSensitivity(sensitivity)
        self.folder = folder
        do {
            let identity = try PersistentIdentity.loadOrCreatePhone()
            let registry = try FileMacRegistry(directory: folder)
            let client = RemoteControlClient(identity: identity, registry: registry)
            await client.setDisplayName(displayName)
            self.client = client
            paired = await client.pairedMacs()
            let snapshots = await client.makeSnapshotStream()
            let appStream = await client.makeAppStream()
            tasks.append(Task { @MainActor in
                for await next in snapshots {
                    self.snapshot = next
                    if case .ready = next.state {
                        self.paired = await client.pairedMacs()
                    }
                }
            })
            tasks.append(Task { @MainActor in
                for await next in appStream {
                    self.apps = next
                }
            })
            let clipStream = await client.makeClipboardStream()
            tasks.append(Task { @MainActor in
                for await text in clipStream {
                    UIPasteboard.general.string = text
                    self.clipboardNote = "Mac clipboard copied to this iPhone."
                }
            })
            startDiscovery()
            startupError = nil
        } catch {
            startupError = (error as? RemoteError)?.safeDescription ?? "The iPhone identity could not be prepared."
        }
    }

    func updateName(_ name: String) async {
        let cleaned = DeviceName.sanitize(name, fallback: "iPhone")
        displayName = cleaned
        if let folder = try? SupportDirectory.url(folder: "GLOT Remote") {
            try? cleaned.write(to: folder.appendingPathComponent("display-name.txt"), atomically: true, encoding: .utf8)
        }
        await client?.setDisplayName(cleaned)
    }

    func connect(_ mac: DiscoveredMac) async {
        guard let client else { return }
        busy = true
        defer { busy = false }
        actionError = nil
        testNote = ""
        let known = paired.first { $0.id == mac.id }
        do {
            _ = try await client.connect(endpoint: mac.endpoint, expectedDeviceID: known?.id, pin: known)
            paired = await client.pairedMacs()
        } catch {
            actionError = (error as? RemoteError)?.safeDescription ?? "Could not connect."
        }
    }

    func decide(_ match: Bool) async {
        await client?.resolvePairing(match: match)
    }

    func disconnect() async {
        pad = TrackpadInterpreter(sensitivity: sensitivity, dragMode: dragMode)
        apps = []
        await client?.disconnect()
        testNote = ""
        clipboardNote = ""
        wakeNote = ""
        paired = await client?.pairedMacs() ?? paired
    }

    func sendTest() async {
        guard let client else { return }
        busy = true
        defer { busy = false }
        do {
            let ack = try await client.sendTest(nonce: Data("phase1".utf8))
            testNote = ack.ok ? "The Mac acknowledged the test command." : "The Mac rejected the test command."
            if ack.ok {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } catch {
            testNote = (error as? RemoteError)?.safeDescription ?? "The test command failed."
        }
    }

    /// Copies the iPhone clipboard text to the Mac. User-initiated, text only.
    func pushClipboard() {
        guard isReady else { return }
        guard var text = UIPasteboard.general.string, !text.isEmpty else {
            clipboardNote = "The iPhone clipboard is empty."
            return
        }
        var trimmed = false
        while text.utf8.count > Limits.maxClipboardBytes {
            text = String(text.dropLast())
            trimmed = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sendRemote([.clipPush(ClipboardBody(text: text))])
        clipboardNote = trimmed
            ? "Clipboard sent to the Mac (trimmed to 16 KB)."
            : "Clipboard sent to the Mac."
    }

    /// Asks the Mac for its clipboard text. The reply lands on the clipboard stream.
    func pullClipboard() {
        guard isReady else { return }
        clipboardNote = "Asking the Mac for its clipboard…"
        sendRemote([.clipPull])
    }

    /// Sends a Wake-on-LAN magic packet to a saved Mac.
    func wake(_ mac: PairedMac) {
        guard let address = mac.wakeMAC, !address.isEmpty else {
            wakeNote = "No wake address saved yet. Connect once to learn it."
            return
        }
        if WakeOnLan.send(mac: address) {
            wakeNote = "Wake packet sent to \(mac.name)."
        } else {
            wakeNote = "The wake packet could not be sent."
        }
    }

    func setSensitivity(_ value: Double) {
        let clamped = min(2.5, max(0.5, value))
        sensitivity = clamped
        pad.setSensitivity(clamped)
        guard let folder else { return }
        try? String(clamped).write(to: folder.appendingPathComponent("sensitivity.txt"), atomically: true, encoding: .utf8)
    }

    func setDragMode(_ enabled: Bool) {
        dragMode = enabled
        emit(pad.setDragMode(enabled, now: Date()))
    }

    func rightClick() {
        emit(pad.rightClick(now: Date()))
    }

    func sendRemote(_ commands: [TrackpadCommand]) {
        emit(commands)
    }

    func trackpadBegan(_ touches: [(id: Int, at: TrackpadPoint)]) {
        emit(pad.begin(touches: touches, now: Date()))
    }

    func trackpadMoved(id: Int, to point: TrackpadPoint) {
        emit(pad.move(id: id, to: point, now: Date()))
    }

    func trackpadEnded(id: Int, at point: TrackpadPoint) {
        emit(pad.end(id: id, at: point, now: Date()))
    }

    func trackpadCancelled(id: Int) {
        emit(pad.cancel(id: id, now: Date()))
    }

    func trackpadTick(_ now: Date) {
        emit(pad.tick(now: now))
    }

    func forget(_ id: UUID) async {
        do {
            try await client?.forget(id: id)
            paired = await client?.pairedMacs() ?? []
        } catch {
            actionError = (error as? RemoteError)?.safeDescription ?? "The saved Mac could not be removed."
        }
    }

    private func startDiscovery() {
        let (stream, continuation) = AsyncStream.makeStream(of: [DiscoveredMac].self)
        let (statusStream, statusContinuation) = AsyncStream.makeStream(of: String.self)
        let browser = MacBrowser { macs in
            continuation.yield(macs)
        } onStatus: { status in
            statusContinuation.yield(status)
        }
        self.browser = browser
        discoveryContinuation = continuation
        browser.start()
        tasks.append(Task { @MainActor in
            for await found in stream {
                self.macs = found
            }
        })
        tasks.append(Task { @MainActor in
            for await status in statusStream {
                self.discoveryNote = status
            }
        })
    }

    private func storedName(in folder: URL) -> String {
        let url = folder.appendingPathComponent("display-name.txt")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return DeviceName.sanitize(text, fallback: "iPhone")
        }
        return DeviceName.sanitize(UIDevice.current.name, fallback: "iPhone")
    }

    private func storedSensitivity(in folder: URL) -> Double {
        let url = folder.appendingPathComponent("sensitivity.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8), let value = Double(text) else {
            return 1.2
        }
        return min(2.5, max(0.5, value))
    }

    private func emit(_ commands: [TrackpadCommand]) {
        guard !commands.isEmpty else { return }
        let presses = commands.contains { command in
            guard case .button(let body) = command else { return false }
            return body.button == "left" && body.phase == "down"
        }
        let releases = commands.contains { command in
            guard case .button(let body) = command else { return false }
            return body.button == "left" && body.phase == "up"
        }
        let right = commands.contains { command in
            guard case .button(let body) = command else { return false }
            return body.button == "right" && body.phase == "down"
        }
        let keyDown = commands.contains { command in
            guard case .key(let body) = command else { return false }
            return body.phase == "down"
        }
        if right {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if presses && releases {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if presses {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else if keyDown || commands.contains(where: { command in
            if case .media = command { return true }
            if case .launch = command { return true }
            if case .system = command { return true }
            if case .clipPush = command { return true }
            if case .clipPull = command { return true }
            return false
        }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        pendingControls = TrackpadCommand.coalesce(pendingControls + commands)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                let batch = self.pendingControls
                self.pendingControls = []
                if !batch.isEmpty {
                    await self.client?.sendControls(batch)
                }
                if self.pendingControls.isEmpty {
                    self.flushScheduled = false
                    return
                }
            }
        }
    }
}
