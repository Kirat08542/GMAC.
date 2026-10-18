import Foundation

public protocol PhoneRegistry: Sendable {
    func all() async -> [PairedPhone]
    func phone(id: UUID) async -> PairedPhone?
    func upsert(_ phone: PairedPhone) async throws
    func setRevoked(id: UUID, revoked: Bool) async throws
    func forget(id: UUID) async throws
}

public protocol MacRegistry: Sendable {
    func all() async -> [PairedMac]
    func mac(id: UUID) async -> PairedMac?
    func upsert(_ mac: PairedMac) async throws
    func forget(id: UUID) async throws
}

public actor InMemoryPhoneRegistry: PhoneRegistry {
    private var records: [UUID: PairedPhone]

    public init(records: [PairedPhone] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public func all() -> [PairedPhone] {
        records.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func phone(id: UUID) -> PairedPhone? { records[id] }

    public func upsert(_ phone: PairedPhone) { records[phone.id] = phone }

    public func setRevoked(id: UUID, revoked: Bool) {
        records[id]?.revoked = revoked
    }

    public func forget(id: UUID) { records[id] = nil }
}

public actor InMemoryMacRegistry: MacRegistry {
    private var records: [UUID: PairedMac]

    public init(records: [PairedMac] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public func all() -> [PairedMac] {
        records.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func mac(id: UUID) -> PairedMac? { records[id] }

    public func upsert(_ mac: PairedMac) { records[mac.id] = mac }

    public func forget(id: UUID) { records[id] = nil }
}

public actor FilePhoneRegistry: PhoneRegistry {
    private let box: FileBox<PairedPhone>

    public init(directory: URL) throws {
        box = try FileBox(directory: directory, fileName: "paired-phones.json")
    }

    public func all() -> [PairedPhone] { box.all() }
    public func phone(id: UUID) -> PairedPhone? { box.get(id) }
    public func upsert(_ phone: PairedPhone) throws { try box.put(phone) }
    public func setRevoked(id: UUID, revoked: Bool) throws {
        guard var phone = box.get(id) else { return }
        phone.revoked = revoked
        try box.put(phone)
    }
    public func forget(id: UUID) throws { try box.remove(id) }
}

public actor FileMacRegistry: MacRegistry {
    private let box: FileBox<PairedMac>

    public init(directory: URL) throws {
        box = try FileBox(directory: directory, fileName: "paired-macs.json")
    }

    public func all() -> [PairedMac] { box.all() }
    public func mac(id: UUID) -> PairedMac? { box.get(id) }
    public func upsert(_ mac: PairedMac) throws { try box.put(mac) }
    public func forget(id: UUID) throws { try box.remove(id) }
}

private final class FileBox<Record: Codable & Identifiable> where Record.ID == UUID {
    private var records: [UUID: Record] = [:]
    private let url: URL

    init(directory: URL, fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let decoded = try WireCoding.decoder().decode([Record].self, from: data)
        records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    func all() -> [Record] { Array(records.values) }
    func get(_ id: UUID) -> Record? { records[id] }

    func put(_ record: Record) throws {
        records[record.id] = record
        try persist()
    }

    func remove(_ id: UUID) throws {
        records[id] = nil
        try persist()
    }

    private func persist() throws {
        let data = try WireCoding.encoder().encode(Array(records.values))
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
