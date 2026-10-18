import Foundation
import Network

public struct DiscoveredMac: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var fingerprint: String
    public var endpoint: NWEndpoint

    init?(result: NWBrowser.Result) {
        guard case .bonjour(let record) = result.metadata else { return nil }
        guard record["ver"] == "1", let idString = record["id"], let id = UUID(uuidString: idString) else {
            return nil
        }
        let name = DeviceName.sanitize(record["name"] ?? "Mac", fallback: "Mac")
        self.id = id
        self.name = name
        self.fingerprint = record["fp"] ?? ""
        self.endpoint = result.endpoint
    }
}

public final class MacBrowser: @unchecked Sendable {
    private let onChange: @Sendable ([DiscoveredMac]) -> Void
    private var browser: NWBrowser?

    private let onStatus: @Sendable (String) -> Void

    public init(
        onChange: @escaping @Sendable ([DiscoveredMac]) -> Void,
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.onChange = onChange
        self.onStatus = onStatus
    }

    public func start() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        // `.bonjour` leaves metadata empty. The Mac identity is in the TXT record,
        // so a plain browse would discover the service and then discard it.
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Limits.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.publish(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            let status = Self.status(for: state)
            RemoteLog.session.info("Browser \(status.isEmpty ? "ready" : status, privacy: .public)")
            self?.onStatus(status)
        }
        RemoteLog.session.info("Browsing \(Limits.serviceType, privacy: .public)")
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        var byID: [UUID: DiscoveredMac] = [:]
        var skipped = 0
        for result in results {
            guard let mac = DiscoveredMac(result: result) else {
                skipped += 1
                continue
            }
            byID[mac.id] = mac
        }
        let found = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        RemoteLog.session.info("Browse saw \(results.count, privacy: .public) services and kept \(found.count, privacy: .public)")
        if skipped > 0 {
            RemoteLog.session.error("Ignored \(skipped, privacy: .public) \(Limits.serviceType, privacy: .public) results without a version 1 TXT record")
        }
        onChange(found)
    }

    private static func status(for state: NWBrowser.State) -> String {
        switch state {
        case .setup, .ready:
            return ""
        case .waiting(let error):
            return "Looking for Macs is waiting. \(describe(error))"
        case .failed(let error):
            return "Looking for Macs failed. \(describe(error))"
        case .cancelled:
            return "Discovery stopped."
        @unknown default:
            return "Discovery entered an unknown state."
        }
    }

    private static func describe(_ error: NWError) -> String {
        let text = String(describing: error)
        if text.localizedCaseInsensitiveContains("PolicyDenied") || text.contains("-65570") {
            return "Allow Local Network for GLOT Remote in Settings."
        }
        return String(text.prefix(160))
    }
}
