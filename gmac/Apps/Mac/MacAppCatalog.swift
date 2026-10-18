import AppKit
import Foundation
import GLOTRemoteCore

/// Stores the apps the Mac user approved and opens one of them.
final class MacAppCatalog: RemoteLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var approved: ApprovedApps
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("allowed-apps.json")
        if let data = try? Data(contentsOf: fileURL),
           let catalog = try? JSONDecoder().decode(AppCatalog.self, from: data) {
            approved = ApprovedApps(apps: catalog.apps)
        } else {
            approved = ApprovedApps()
        }
    }

    func current() -> ApprovedApps {
        lock.lock()
        defer { lock.unlock() }
        return approved
    }

    func add(bundleID: String, name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        approved = try approved.adding(bundleID: bundleID, name: name)
        saveLocked()
    }

    func remove(bundleID: String) {
        lock.lock()
        defer { lock.unlock() }
        approved = approved.removing(bundleID)
        saveLocked()
    }

    func launch(bundleID: String) async throws {
        let allowed: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return approved.allows(bundleID)
        }()
        guard allowed else {
            throw RemoteError.invalid("That app is not approved on the Mac.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                      Bundle(url: url)?.bundleIdentifier == bundleID else {
                    continuation.resume(throwing: RemoteError.invalid("The Mac could not find that app."))
                    return
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    if error == nil {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: RemoteError.invalid("The Mac could not open that app."))
                    }
                }
            }
        }
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(approved.catalog) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
