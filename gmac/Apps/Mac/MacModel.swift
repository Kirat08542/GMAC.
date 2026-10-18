import AppKit
import Foundation
import GLOTRemoteCore
import Observation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
@Observable
final class MacModel {
    var snapshot = SessionSnapshot(state: .idle)
    var phones: [PairedPhone] = []
    var deviceName = "Mac"
    var listening = false
    var startupError: String?
    var actionError: String?
    var loginStatus = "Off"
    var loginError: String?
    var accessibilityTrusted = false
    var approvedApps: [AppRecord] = []

    @ObservationIgnored private var server: RemoteControlServer?
    @ObservationIgnored private var catalog: MacAppCatalog?
    @ObservationIgnored private var openPanel: NSOpenPanel?
    @ObservationIgnored private let pointer = MacPointerController()
    @ObservationIgnored private let keyboard = MacKeyboardController()
    @ObservationIgnored private let media = MacMediaController()
    @ObservationIgnored private let power = MacPowerController()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var accessTask: Task<Void, Never>?
    @ObservationIgnored private var accessPoll: Task<Void, Never>?

    var isReady: Bool {
        if case .ready = snapshot.state { return true }
        return false
    }

    func prepare() async {
        deviceName = DeviceName.sanitize(Host.current().localizedName ?? "Mac", fallback: "Mac")
        if catalog == nil, let directory = try? SupportDirectory.url(folder: "GLOT Remote Mac") {
            let catalog = MacAppCatalog(directory: directory)
            self.catalog = catalog
            approvedApps = catalog.current().apps
        }
        refreshLoginStatus()
        refreshAccessibility()
        watchAccessibility()
        guard !listening else { return }
        if storedListening() {
            await setListening(true)
        }
    }

    func addApplication() {
        guard catalog != nil else {
            actionError = "The app list could not be opened."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        panel.message = "Choose an app the iPhone may open."
        openPanel = panel
        NSApp.activate()
        let present = {
            let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeMain }
            if let window {
                panel.beginSheetModal(for: window) { [weak self] response in
                    MainActor.assumeIsolated {
                        self?.finishPicking(panel, response: response)
                    }
                }
            } else {
                self.finishPicking(panel, response: panel.runModal())
            }
        }
        DispatchQueue.main.async(execute: present)
    }

    func removeApplication(_ bundleID: String) async {
        catalog?.remove(bundleID: bundleID)
        approvedApps = catalog?.current().apps ?? []
        await pushApps()
    }

    func setListening(_ enabled: Bool) async {
        if enabled {
            await start()
            writeListening(listening)
        } else {
            await stop()
            writeListening(false)
        }
    }

    func decide(_ approve: Bool) async {
        await server?.resolvePairing(approve: approve)
    }

    func disconnectRemote() async {
        await server?.disconnectRemote()
    }

    func revoke(_ id: UUID) async {
        do {
            try await server?.revoke(id: id)
            phones = await server?.pairedPhones() ?? phones
        } catch {
            actionError = (error as? RemoteError)?.safeDescription ?? "The iPhone could not be revoked."
        }
    }

    func forget(_ id: UUID) async {
        do {
            try await server?.forget(id: id)
            phones = await server?.pairedPhones() ?? phones
        } catch {
            actionError = (error as? RemoteError)?.safeDescription ?? "The iPhone could not be forgotten."
        }
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Start at login did not change. A development signature often cannot register a login item. \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func refreshAccessibility() {
        accessibilityTrusted = pointer.isTrusted()
    }

    func requestAccessibility() {
        pointer.promptForTrust()
        refreshAccessibility()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func start() async {
        if server != nil {
            listening = true
            return
        }
        startupError = nil
        actionError = nil
        do {
            let (id, material) = try PersistentIdentity.loadOrCreateMacIdentity()
            let directory = try SupportDirectory.url(folder: "GLOT Remote Mac")
            let registry = try FilePhoneRegistry(directory: directory)
            let server = RemoteControlServer(
                identity: material,
                registry: registry,
                deviceID: id,
                deviceName: deviceName,
                pointer: pointer,
                keyboard: keyboard,
                media: media,
                launcher: catalog ?? DeniedLauncher(),
                power: power
            )
            do {
                _ = try await server.start(advertise: true)
            } catch {
                await server.stop()
                throw error
            }
            self.server = server
            listening = true
            phones = await server.pairedPhones()
            let snapshots = await server.makeSnapshotStream()
            tasks.append(Task { @MainActor in
                var wasReady = false
                for await next in snapshots {
                    let isReady = if case .ready = next.state { true } else { false }
                    self.snapshot = next
                    self.phones = await server.pairedPhones()
                    if isReady && !wasReady {
                        await self.pushApps()
                    }
                    wasReady = isReady
                }
            })
        } catch {
            listening = false
            startupError = (error as? RemoteError)?.safeDescription ?? "The listener could not start."
        }
    }

    private func stop() async {
        pointer.release()
        keyboard.release()
        await server?.stop()
        server = nil
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        listening = false
        snapshot = SessionSnapshot(state: .idle, note: "Stopped.")
    }

    private func finishPicking(_ panel: NSOpenPanel, response: NSApplication.ModalResponse) {
        let url = response == .OK ? panel.url : nil
        openPanel = nil
        guard let url else { return }
        Task { await admit(url) }
    }

    private func admit(_ url: URL) async {
        guard let catalog else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let described = describeApp(at: url) else {
            actionError = "The Mac could not read that app."
            return
        }
        do {
            try catalog.add(bundleID: described.id, name: described.name)
            approvedApps = catalog.current().apps
            actionError = nil
            await pushApps()
        } catch {
            actionError = (error as? RemoteError)?.safeDescription ?? "That app could not be added."
        }
    }

    private func describeApp(at url: URL) -> (id: String, name: String)? {
        let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
        let bundle = Bundle(url: url)
        let bundleID = (info?["CFBundleIdentifier"] as? String) ?? bundle?.bundleIdentifier
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let localized = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let raw = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = [localized, raw, fileName].compactMap { $0 }.first { !$0.isEmpty } ?? "App"
        return (bundleID, name)
    }

    private func pushApps() async {
        guard let catalog else { return }
        await server?.sendApps(catalog.current().catalog)
    }

    private func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginStatus = "On"
        case .requiresApproval:
            loginStatus = "Needs approval in System Settings"
        case .notRegistered:
            loginStatus = "Off"
        case .notFound:
            loginStatus = "Unavailable until the app is installed and signed"
        @unknown default:
            loginStatus = "Unknown"
        }
    }

    private func watchAccessibility() {
        guard accessTask == nil, accessPoll == nil else { return }
        accessTask = Task { @MainActor in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self.refreshAccessibility()
            }
        }
        accessPoll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let trusted = self.pointer.isTrusted()
                if trusted != self.accessibilityTrusted {
                    self.accessibilityTrusted = trusted
                }
            }
        }
    }

    private func flagURL() -> URL? {
        try? SupportDirectory.url(folder: "GLOT Remote Mac").appendingPathComponent("listening.txt")
    }

    private func storedListening() -> Bool {
        guard let url = flagURL(), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return text == "1"
    }

    private func writeListening(_ enabled: Bool) {
        guard let url = flagURL() else { return }
        try? (enabled ? "1" : "0").write(to: url, atomically: true, encoding: .utf8)
    }
}
