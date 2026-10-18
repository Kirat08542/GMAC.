import Foundation

/// The apps the Mac user has allowed the iPhone to open.
public struct ApprovedApps: Sendable, Equatable {
    public static let limit = 40
    public private(set) var apps: [AppRecord]

    public init(apps: [AppRecord] = []) {
        var kept: [AppRecord] = []
        var seen = Set<String>()
        for app in apps {
            let record = AppRecord(bundleID: app.bundleID, name: DeviceName.sanitize(app.name, fallback: "App"))
            guard seen.insert(record.bundleID).inserted else { continue }
            guard (try? PayloadValidation.launch(LaunchBody(bundleID: record.bundleID))) != nil else { continue }
            guard kept.count < Self.limit else { break }
            kept.append(record)
        }
        kept.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.apps = kept
    }

    public func allows(_ bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }

    public func adding(bundleID: String, name: String) throws -> ApprovedApps {
        let record = AppRecord(bundleID: bundleID, name: DeviceName.sanitize(name, fallback: "App"))
        try PayloadValidation.launch(LaunchBody(bundleID: record.bundleID))
        var next = apps.filter { $0.bundleID != record.bundleID }
        guard next.count < Self.limit else {
            throw RemoteError.invalid("The Mac already has 40 approved apps.")
        }
        next.append(record)
        return ApprovedApps(apps: next)
    }

    public func removing(_ bundleID: String) -> ApprovedApps {
        ApprovedApps(apps: apps.filter { $0.bundleID != bundleID })
    }

    public var catalog: AppCatalog {
        AppCatalog(apps: apps)
    }
}

/// Opens an approved app. The Mac app supplies the implementation.
public protocol RemoteLauncher: Sendable {
    func launch(bundleID: String) async throws
}

public struct DeniedLauncher: RemoteLauncher {
    public init() {}

    public func launch(bundleID: String) async throws {
        throw RemoteError.invalid("App launch is not running in this process.")
    }
}
