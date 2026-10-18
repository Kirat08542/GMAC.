import Foundation
import Network

public actor RemoteControlServer {
    public private(set) var snapshot = SessionSnapshot(state: .idle)

    private let identity: TLSMaterial
    private let registry: any PhoneRegistry
    private let deviceID: UUID
    private var deviceName: String
    private let pointer: any RemotePointer
    private let keyboard: any RemoteKeyboard
    private let media: any RemoteMedia
    private let launcher: any RemoteLauncher
    private let power: any RemotePower
    private let config: TransportConfig
    private var listener: NWListener?
    private var slot: Slot?
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]

    public init(
        identity: TLSMaterial,
        registry: any PhoneRegistry,
        deviceID: UUID,
        deviceName: String,
        pointer: any RemotePointer = DeniedPointer(),
        keyboard: any RemoteKeyboard = DeniedKeyboard(),
        media: any RemoteMedia = DeniedMedia(),
        launcher: any RemoteLauncher = DeniedLauncher(),
        power: any RemotePower = DeniedPower(),
        config: TransportConfig = TransportConfig()
    ) {
        self.identity = identity
        self.registry = registry
        self.deviceID = deviceID
        self.deviceName = DeviceName.sanitize(deviceName, fallback: "Mac")
        self.pointer = pointer
        self.keyboard = keyboard
        self.media = media
        self.launcher = launcher
        self.power = power
        self.config = config
    }

    public func start(advertise: Bool) async throws -> UInt16 {
        if listener != nil {
            throw RemoteError.invalid("The Mac listener is already running.")
        }
        let parameters = TLSConfiguration.serverParameters(identity: identity)
        parameters.allowLocalEndpointReuse = true
        if !advertise {
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        }
        let listener = try NWListener(using: parameters)
        if advertise {
            let txt = NWTXTRecord([
                "id": deviceID.uuidString,
                "ver": "1",
                "name": deviceName,
                "fp": Fingerprint.short(identity.canonicalPublicKey),
            ])
            var service = NWListener.Service(name: bonjourName(deviceName), type: Limits.serviceType, domain: nil, txtRecord: txt)
            service.noAutoRename = false
            listener.service = service
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.accept(connection) }
        }
        self.listener = listener
        let port = try await waitUntilListening(listener, advertise: advertise)
        watch(listener)
        setSnapshot(SessionSnapshot(state: .listening))
        RemoteLog.session.info("Listener ready on port \(port, privacy: .public) advertise \(advertise, privacy: .public)")
        return port
    }

    public func stop() async {
        pointer.release()
        keyboard.release()
        slot?.queue.finish("The Mac stopped listening.")
        slot?.reader?.cancel()
        await slot?.connection.cancel()
        slot = nil
        listener?.cancel()
        listener = nil
        setSnapshot(SessionSnapshot(state: .idle, note: "Stopped."))
    }

    public func resolvePairing(approve: Bool) {
        slot?.queue.push(.decision(approve))
    }

    public func disconnectRemote() async {
        guard let slot else { return }
        let bye = ByeBody(reason: "disconnect")
        if let envelope = try? WireCoding.envelope(type: WireType.bye, body: bye) {
            try? await slot.connection.send(envelope)
        }
        slot.queue.finish("Disconnected.")
        slot.reader?.cancel()
        await slot.connection.cancel()
    }

    public func sendApps(_ catalog: AppCatalog) async {
        guard case .ready = snapshot.state, let slot else { return }
        guard (try? PayloadValidation.catalog(catalog)) != nil else { return }
        guard let envelope = try? WireCoding.envelope(type: WireType.apps, body: catalog) else { return }
        try? await slot.connection.send(envelope)
    }

    public func revoke(id: UUID) async throws {
        try await registry.setRevoked(id: id, revoked: true)
        if slot?.deviceID == id {
            await disconnectRemote()
            setSnapshot(SessionSnapshot(state: .listening, note: "Revoked the paired iPhone."))
        }
    }

    public func forget(id: UUID) async throws {
        try await registry.forget(id: id)
        if slot?.deviceID == id {
            await disconnectRemote()
        }
    }

    public func pairedPhones() async -> [PairedPhone] {
        await registry.all()
    }

    public func makeSnapshotStream() -> AsyncStream<SessionSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionSnapshot.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { @Sendable _ in
            Task { await self.removeContinuation(id) }
        }
        return stream
    }

    private func accept(_ connection: NWConnection) async {
        if slot != nil {
            connection.cancel()
            RemoteLog.session.info("Rejected a connection because a session is active")
            return
        }
        let frame = FrameConnection(connection: connection, maxFrame: config.maxFrameSize)
        let queue = SessionQueue()
        let accepted = Slot(connection: frame, raw: connection, queue: queue)
        slot = accepted
        await serve(accepted)
        if slot === accepted {
            slot = nil
            if listener != nil, snapshot.state != .listening {
                setSnapshot(SessionSnapshot(state: .listening))
            }
        }
    }

    private func serve(_ slot: Slot) async {
        let connection = slot.connection
        let queue = slot.queue
        defer {
            pointer.release()
            keyboard.release()
            queue.finish("The session ended.")
            Task { await connection.cancel() }
        }
        do {
            try await connection.ready(timeout: config.connectTimeout)
            guard TLSConfiguration.isTLS13(slot.raw) else { throw RemoteError.tlsUntrusted }
            let reader = Task {
                do {
                    while !Task.isCancelled {
                        let envelope = try await connection.nextEnvelope()
                        queue.push(.message(envelope))
                    }
                } catch {
                    queue.push(.closed(SessionText.describe(error)))
                }
            }
            slot.reader = reader
            defer { reader.cancel() }
            try await handshake(slot)
            setSnapshot(SessionSnapshot(state: .ready(peerName: slot.deviceName ?? "iPhone")))
            RemoteLog.session.info("Remote session authenticated")
            try await pump(slot)
        } catch {
            let message = SessionText.describe(error)
            RemoteLog.session.error("Session ended before or during use")
            if listener != nil {
                setSnapshot(SessionSnapshot(state: .listening, note: message))
            } else {
                setSnapshot(SessionSnapshot(state: .failed(message), note: message))
            }
        }
    }

    private func handshake(_ slot: Slot) async throws {
        let first = try await nextMessage(slot, timeout: config.connectTimeout)
        guard first.type == WireType.hello else { throw RemoteError.unauthorized }
        guard slot.deduper.insert(first.id) else { throw RemoteError.invalid("A repeated message was rejected.") }
        let hello = try WireCoding.decodePayload(ClientHello.self, from: first.payload)
        try PayloadValidation.clientHello(hello)
        let record = await registry.phone(id: hello.deviceID)
        let decision = Trust.decide(record: record, presentedKey: hello.publicKey)
        switch decision {
        case .reject(let code):
            let message = code == ErrorCode.revoked
                ? "This iPhone is revoked. Forget it on the Mac before pairing again."
                : "The iPhone key does not match the paired record."
            try await sendError(slot, ref: first.id, code: code, message: message)
            throw code == ErrorCode.revoked ? RemoteError.revoked : RemoteError.unauthorized
        case .authenticate where !hello.wantsPairing:
            slot.deviceID = hello.deviceID
            slot.deviceName = hello.name
            slot.clientKey = hello.publicKey
            slot.clientNonce = hello.nonce
            try await sendServerHello(slot, paired: true)
            try await authenticate(slot, hello: hello)
        case .authenticate, .pair:
            slot.deviceID = hello.deviceID
            slot.deviceName = hello.name
            slot.clientKey = hello.publicKey
            slot.clientNonce = hello.nonce
            try await sendServerHello(slot, paired: false)
            try await pair(slot, hello: hello)
        }
        guard let id = slot.deviceID, let key = slot.clientKey, let name = slot.deviceName else {
            throw RemoteError.unauthorized
        }
        var phone = await registry.phone(id: id) ?? PairedPhone(
            id: id,
            name: name,
            signingKey: key,
            pairedAt: Date()
        )
        phone.name = name
        phone.signingKey = key
        phone.revoked = false
        phone.lastConnected = Date()
        try await registry.upsert(phone)
        slot.authenticated = true
    }

    private func sendServerHello(_ slot: Slot, paired: Bool) async throws {
        let nonce = try RandomBytes.generate(count: Limits.nonceLength)
        slot.serverNonce = nonce
        let hello = ServerHello(
            version: Limits.protocolVersion,
            deviceID: deviceID,
            name: deviceName,
            publicKey: identity.canonicalPublicKey,
            nonce: nonce,
            paired: paired
        )
        try await slot.connection.send(try WireCoding.envelope(type: WireType.helloAck, body: hello))
    }

    private func authenticate(_ slot: Slot, hello: ClientHello) async throws {
        setSnapshot(SessionSnapshot(state: .authenticating))
        let challenge = try RandomBytes.generate(count: Limits.nonceLength)
        try await slot.connection.send(try WireCoding.envelope(type: WireType.authChallenge, body: AuthChallenge(challenge: challenge)))
        let envelope = try await nextMessage(slot, timeout: config.connectTimeout)
        guard envelope.type == WireType.authResponse else { throw RemoteError.unauthorized }
        guard slot.deduper.insert(envelope.id) else { throw RemoteError.invalid("A repeated message was rejected.") }
        let response = try WireCoding.decodePayload(AuthResponse.self, from: envelope.payload)
        guard (40...128).contains(response.signature.count) else { throw RemoteError.unauthorized }
        guard let serverNonce = slot.serverNonce else { throw RemoteError.unauthorized }
        let message = DeviceSignature.message(
            challenge: challenge,
            serverPublicKey: identity.canonicalPublicKey,
            clientNonce: hello.nonce,
            serverNonce: serverNonce,
            clientID: hello.deviceID
        )
        guard DeviceSignature.verify(signature: response.signature, message: message, publicKey: hello.publicKey) else {
            try await sendError(slot, ref: envelope.id, code: ErrorCode.unauthorized, message: "The iPhone signature was rejected.")
            throw RemoteError.unauthorized
        }
        try await slot.connection.send(try WireCoding.envelope(type: WireType.authResult, body: AuthResult(ok: true)))
    }

    private func pair(_ slot: Slot, hello: ClientHello) async throws {
        guard let serverNonce = slot.serverNonce else { throw RemoteError.unauthorized }
        let code = PairingCode.make(
            serverPublicKey: identity.canonicalPublicKey,
            clientPublicKey: hello.publicKey,
            clientNonce: hello.nonce,
            serverNonce: serverNonce
        )
        let deadline = Date().addingTimeInterval(DurationClock.seconds(config.pairingTimeout))
        slot.gate = PairingGate(deadline: deadline)
        setSnapshot(SessionSnapshot(state: .pairing(code: code, expires: deadline)))
        let timeoutID = UUID()
        let queue = slot.queue
        let pairingTimeout = config.pairingTimeout
        let timer = Task {
            try? await Task.sleep(for: pairingTimeout)
            queue.push(.timeout(timeoutID))
        }
        defer { timer.cancel() }
        var clientAccepted: Bool?
        var serverAccepted: Bool?
        while true {
            if let outcome = conclude(clientAccepted: clientAccepted, serverAccepted: serverAccepted, deadline: deadline) {
                switch outcome {
                case .approved:
                    try await slot.connection.send(try WireCoding.envelope(type: WireType.pairResult, body: PairResult(paired: true, reason: "approved")))
                    return
                case .denied:
                    try await slot.connection.send(try WireCoding.envelope(type: WireType.pairResult, body: PairResult(paired: false, reason: "denied")))
                    throw RemoteError.pairingFailed
                case .expired:
                    try await slot.connection.send(try WireCoding.envelope(type: WireType.pairResult, body: PairResult(paired: false, reason: "expired")))
                    throw RemoteError.pairingExpired
                case .pending:
                    break
                }
            }
            switch await slot.queue.next() {
            case .decision(let approved):
                serverAccepted = approved
            case .timeout(let id):
                guard id == timeoutID else { continue }
                serverAccepted = serverAccepted ?? false
                clientAccepted = clientAccepted ?? false
                slot.gate?.deadline = Date().addingTimeInterval(-1)
            case .closed(let reason):
                throw RemoteError.invalid(reason)
            case .message(let envelope):
                guard slot.deduper.insert(envelope.id) else { continue }
                guard try allow(slot) else { throw RemoteError.invalid("The iPhone sent messages too quickly.") }
                if envelope.type == WireType.pairConfirm {
                    let confirm = try WireCoding.decodePayload(PairConfirm.self, from: envelope.payload)
                    clientAccepted = confirm.accept
                } else if envelope.type == WireType.error {
                    throw RemoteError.pairingFailed
                } else {
                    try await sendError(slot, ref: envelope.id, code: ErrorCode.unauthorized, message: "The session is not authenticated.")
                    throw RemoteError.unauthorized
                }
            }
        }
    }

    private func conclude(clientAccepted: Bool?, serverAccepted: Bool?, deadline: Date) -> PairingOutcome? {
        var gate = PairingGate(deadline: deadline)
        gate.clientAccepted = clientAccepted
        gate.serverAccepted = serverAccepted
        let outcome = gate.result(now: Date())
        return outcome == .pending ? nil : outcome
    }

    private func pump(_ slot: Slot) async throws {
        let connection = slot.connection
        let heartbeatInterval = config.heartbeatInterval
        let heart = Task {
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)
                sequence += 1
                if let envelope = try? WireCoding.envelope(type: WireType.heartbeat, body: HeartbeatBody(seq: sequence)) {
                    try? await connection.send(envelope)
                }
            }
        }
        let livenessID = UUID()
        let token = slot.token
        let watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.checkLiveness(token: token, timeoutID: livenessID)
            }
        }
        defer {
            heart.cancel()
            watch.cancel()
        }
        slot.lastInbound = ContinuousClock().now
        while true {
            switch await slot.queue.next() {
            case .message(let envelope):
                slot.lastInbound = ContinuousClock().now
                try await handleReady(slot, envelope)
            case .closed(let reason):
                throw RemoteError.invalid(reason)
            case .timeout(let id):
                guard id == livenessID else { continue }
                throw RemoteError.timeout
            case .decision:
                break
            }
        }
    }

    private func checkLiveness(token: UUID, timeoutID: UUID) {
        guard let slot, slot.token == token else { return }
        let idle = slot.lastInbound.duration(to: ContinuousClock().now)
        if idle > config.livenessTimeout {
            slot.queue.push(.timeout(timeoutID))
        }
    }

    private func handleReady(_ slot: Slot, _ envelope: Envelope) async throws {
        guard envelope.v == Limits.protocolVersion else { throw RemoteError.versionMismatch }
        guard slot.deduper.insert(envelope.id) else { return }
        guard try allow(slot) else {
            try await sendError(slot, ref: envelope.id, code: ErrorCode.invalid, message: "The iPhone sent messages too quickly.")
            return
        }
        switch envelope.type {
        case WireType.heartbeat:
            return
        case WireType.test:
            let body = try WireCoding.decodePayload(TestBody.self, from: envelope.payload)
            guard (1...64).contains(body.nonce.count) else {
                try await sendError(slot, ref: envelope.id, code: ErrorCode.invalid, message: "The test command is not valid.")
                return
            }
            try await slot.connection.send(try WireCoding.envelope(type: WireType.ack, body: AckBody(ref: envelope.id, ok: true)))
            setSnapshot(SessionSnapshot(state: .ready(peerName: slot.deviceName ?? "iPhone"), note: "Test command acknowledged."))
        case WireType.bye:
            throw RemoteError.closed
        case WireType.error:
            throw RemoteError.closed
        default:
            switch ControlPolicy.decide(type: envelope.type, authenticated: true, payload: envelope.payload) {
            case .handle:
                try await performControl(slot, envelope)
            case .unsupported, .session:
                try await sendError(slot, ref: envelope.id, code: ErrorCode.unsupported, message: "This command is not available in this version.")
                slot.invalidCount += 1
            case .unauthorized:
                try await sendError(slot, ref: envelope.id, code: ErrorCode.unauthorized, message: "The session is not authenticated.")
                throw RemoteError.unauthorized
            case .invalid(let message):
                try await sendError(slot, ref: envelope.id, code: ErrorCode.invalid, message: message)
                slot.invalidCount += 1
            }
            if slot.invalidCount > Limits.maxInvalidMessages {
                throw RemoteError.invalid("Too many rejected messages.")
            }
        }
    }

    private func performControl(_ slot: Slot, _ envelope: Envelope) async throws {
        do {
            switch envelope.type {
            case WireType.pointer:
                let batch = try WireCoding.decodePayload(PointerBatch.self, from: envelope.payload)
                try pointer.move(batch.samples)
            case WireType.mouse:
                let body = try WireCoding.decodePayload(MouseButtonBody.self, from: envelope.payload)
                try pointer.button(body)
            case WireType.scroll:
                let body = try WireCoding.decodePayload(ScrollBody.self, from: envelope.payload)
                try pointer.scroll(body)
            case WireType.key:
                let body = try WireCoding.decodePayload(KeyBody.self, from: envelope.payload)
                try keyboard.key(body)
            case WireType.text:
                let body = try WireCoding.decodePayload(TextBody.self, from: envelope.payload)
                try keyboard.text(body)
            case WireType.media:
                let body = try WireCoding.decodePayload(MediaBody.self, from: envelope.payload)
                try media.perform(body)
            case WireType.launch:
                let body = try WireCoding.decodePayload(LaunchBody.self, from: envelope.payload)
                try await launcher.launch(bundleID: body.bundleID)
            case WireType.system:
                let body = try WireCoding.decodePayload(SystemBody.self, from: envelope.payload)
                guard body.action == "sleep" else {
                    throw RemoteError.invalid("The system action is not supported.")
                }
                guard body.confirmed else {
                    throw RemoteError.invalid("This action needs confirmation.")
                }
                try power.sleep()
            default:
                try await sendError(slot, ref: envelope.id, code: ErrorCode.unsupported, message: "This command is not available in this version.")
                slot.invalidCount += 1
                return
            }
        } catch {
            try await sendError(slot, ref: envelope.id, code: ErrorCode.invalid, message: SessionText.describe(error))
        }
    }

    private func nextMessage(_ slot: Slot, timeout: Duration) async throws -> Envelope {
        let timeoutID = UUID()
        let queue = slot.queue
        let timer = Task {
            try? await Task.sleep(for: timeout)
            queue.push(.timeout(timeoutID))
        }
        defer { timer.cancel() }
        while true {
            switch await slot.queue.next() {
            case .message(let envelope):
                guard try allow(slot) else { throw RemoteError.invalid("The iPhone sent messages too quickly.") }
                guard envelope.v == Limits.protocolVersion else { throw RemoteError.versionMismatch }
                return envelope
            case .timeout(let id):
                guard id == timeoutID else { continue }
                throw RemoteError.timeout
            case .closed(let reason):
                throw RemoteError.invalid(reason)
            case .decision:
                continue
            }
        }
    }

    private func allow(_ slot: Slot) throws -> Bool {
        slot.limiter.allow(now: ContinuousClock().now, limit: Limits.maxMessagesPerSecond, window: .seconds(1))
    }

    private func sendError(_ slot: Slot, ref: UUID?, code: String, message: String) async throws {
        let body = ErrorBody(ref: ref, code: code, message: PayloadValidation.errorMessage(message))
        try await slot.connection.send(try WireCoding.envelope(type: WireType.error, body: body))
    }

    private func waitUntilListening(_ listener: NWListener, advertise: Bool) async throws -> UInt16 {
        try await withThrowingTaskGroup(of: UInt16.self) { group in
            group.addTask { try await self.waitForPort(listener, advertise: advertise) }
            group.addTask {
                try await Task.sleep(for: self.config.connectTimeout)
                if advertise {
                    throw RemoteError.invalid("The Mac did not advertise \(Limits.serviceType).")
                }
                throw RemoteError.timeout
            }
            defer { group.cancelAll() }
            guard let port = try await group.next() else { throw RemoteError.closed }
            if port == 0 { throw RemoteError.invalid("The listener did not bind a port.") }
            return port
        }
    }

    private func waitForPort(_ listener: NWListener, advertise: Bool) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let gate = OnceGate<UInt16>()
            let progress = ListenProgress(needsAdvertisement: advertise)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    RemoteLog.session.info("Listener bound port \(port, privacy: .public)")
                    if let ready = progress.markReady(port) {
                        gate.finish(continuation, result: .success(ready))
                    }
                case .waiting(let error):
                    RemoteLog.session.error("Listener waiting: \(String(describing: error), privacy: .public)")
                case .failed(let error):
                    RemoteLog.session.error("Listener failed: \(String(describing: error), privacy: .public)")
                    gate.finish(continuation, result: .failure(RemoteError.invalid(String(describing: error))))
                case .cancelled:
                    gate.finish(continuation, result: .failure(RemoteError.cancelled))
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.serviceRegistrationUpdateHandler = { change in
                switch change {
                case .add(let endpoint):
                    RemoteLog.session.info("Published \(Limits.serviceType, privacy: .public) as \(String(describing: endpoint), privacy: .public)")
                    if let ready = progress.markAdvertised() {
                        gate.finish(continuation, result: .success(ready))
                    }
                case .remove(let endpoint):
                    RemoteLog.session.error("Bonjour registration removed: \(String(describing: endpoint), privacy: .public)")
                @unknown default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private func watch(_ listener: NWListener) {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                let message = "The listener failed. \(String(describing: error))"
                RemoteLog.session.error("\(message, privacy: .public)")
                Task { await self.noteListener(message) }
            case .waiting(let error):
                let message = "The listener is waiting. \(String(describing: error))"
                RemoteLog.session.error("\(message, privacy: .public)")
                Task { await self.noteListener(message) }
            case .cancelled:
                RemoteLog.session.info("Listener cancelled")
            case .ready, .setup:
                break
            @unknown default:
                break
            }
        }
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            if case .remove(let endpoint) = change {
                RemoteLog.session.error("Bonjour registration removed: \(String(describing: endpoint), privacy: .public)")
                Task { await self.noteListener("This Mac stopped advertising \(Limits.serviceType).") }
            }
        }
    }

    private func noteListener(_ message: String) {
        guard listener != nil else { return }
        if case .listening = snapshot.state {
            setSnapshot(SessionSnapshot(state: .listening, note: message))
        }
    }

    private func setSnapshot(_ snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func bonjourName(_ raw: String) -> String {
        let sanitized = DeviceName.sanitize(raw, fallback: "GLOT Remote Mac")
        var result = ""
        var count = 0
        for character in sanitized {
            let added = character.utf8.count
            if count + added > 63 { break }
            result.append(character)
            count += added
        }
        return result.isEmpty ? "GLOT Remote Mac" : result
    }
}

private final class ListenProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var port: UInt16 = 0
    private var advertised: Bool
    private var finished = false

    init(needsAdvertisement: Bool) {
        advertised = !needsAdvertisement
    }

    func markReady(_ port: UInt16) -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        self.port = port
        return finishIfReady()
    }

    func markAdvertised() -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        advertised = true
        return finishIfReady()
    }

    private func finishIfReady() -> UInt16? {
        guard !finished, port != 0, advertised else { return nil }
        finished = true
        return port
    }
}

private final class Slot {
    let connection: FrameConnection
    let raw: NWConnection
    let queue: SessionQueue
    var reader: Task<Void, Never>?
    var deviceID: UUID?
    var deviceName: String?
    var clientKey: Data?
    var clientNonce: Data?
    var serverNonce: Data?
    var gate: PairingGate?
    var authenticated = false
    var deduper = MessageDeduper()
    var limiter = RateLimiter()
    var invalidCount = 0
    var lastInbound = ContinuousClock().now
    let token = UUID()

    init(connection: FrameConnection, raw: NWConnection, queue: SessionQueue) {
        self.connection = connection
        self.raw = raw
        self.queue = queue
    }
}

enum SessionText {
    static func describe(_ error: Error) -> String {
        if let remote = error as? RemoteError {
            return remote.safeDescription
        }
        let text = String(describing: error)
        return String(text.prefix(160))
    }
}
