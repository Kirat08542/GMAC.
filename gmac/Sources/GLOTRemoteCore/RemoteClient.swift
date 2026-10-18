import Foundation
import Network

public actor RemoteControlClient {
    public private(set) var snapshot = SessionSnapshot(state: .idle)
    public private(set) var apps: [AppRecord] = []
    public private(set) var pin: PairedMac?

    private let identity: SigningIdentity
    private let registry: any MacRegistry
    private let config: TransportConfig
    private var endpoint: NWEndpoint?
    private var expectedDeviceID: UUID?
    private var connection: FrameConnection?
    private var queue: SessionQueue?
    private var runTask: Task<Void, Never>?
    private var userWantsConnection = false
    private var attempt = 0
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]
    private var appContinuations: [UUID: AsyncStream<[AppRecord]>.Continuation] = [:]
    private var ackWaiters: [UUID: CheckedContinuation<AckBody, Error>] = [:]
    private var queuedDecision: Bool?
    private var lastInbound = ContinuousClock().now

    public init(identity: SigningIdentity, registry: any MacRegistry, config: TransportConfig = TransportConfig()) {
        self.identity = identity
        self.registry = registry
        self.config = config
    }

    @discardableResult
    public func connect(endpoint: NWEndpoint, expectedDeviceID: UUID?, pin: PairedMac?) async throws -> LinkState {
        self.endpoint = endpoint
        self.expectedDeviceID = expectedDeviceID
        self.pin = pin
        userWantsConnection = true
        attempt = 0
        runTask?.cancel()
        queue?.finish("Replaced.")
        await connection?.cancel()
        runTask = Task { await self.sessionLoop() }
        let state = try await waitFor(timeout: config.connectTimeout + .seconds(2)) { state in
            switch state {
            case .pairing, .ready, .failed:
                return true
            default:
                return false
            }
        }
        if case .failed(let message) = state {
            throw RemoteError.invalid(message)
        }
        return state
    }

    public func resolvePairing(match: Bool) {
        queue?.push(.decision(match))
    }

    public func disconnect() async {
        userWantsConnection = false
        if let connection, let envelope = try? WireCoding.envelope(type: WireType.bye, body: ByeBody(reason: "disconnect")) {
            try? await connection.send(envelope)
        }
        queue?.finish("Disconnected.")
        await connection?.cancel()
        runTask?.cancel()
        failAcks(RemoteError.cancelled)
        setSnapshot(SessionSnapshot(state: .idle, note: "Disconnected."))
    }

    public func sendTest(nonce: Data) async throws -> AckBody {
        guard case .ready = snapshot.state, let connection else { throw RemoteError.notReady }
        guard (1...64).contains(nonce.count) else { throw RemoteError.invalid("The test command is not valid.") }
        let id = UUID()
        let envelope = try WireCoding.envelope(type: WireType.test, body: TestBody(nonce: nonce), id: id)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AckBody, Error>) in
            ackWaiters[id] = continuation
            Task {
                do {
                    try await connection.send(envelope)
                } catch {
                    self.completeAck(id, result: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                self.completeAck(id, result: .failure(RemoteError.timeout))
            }
        }
    }

    /// Sends pointer, button, and scroll commands without waiting for an acknowledgement.
    public func sendControls(_ commands: [TrackpadCommand]) async {
        guard case .ready = snapshot.state, let connection else { return }
        for command in commands {
            do {
                let envelope: Envelope
                switch command {
                case .move(let batch):
                    envelope = try WireCoding.envelope(type: WireType.pointer, body: batch)
                case .button(let body):
                    envelope = try WireCoding.envelope(type: WireType.mouse, body: body)
                case .scroll(let body):
                    envelope = try WireCoding.envelope(type: WireType.scroll, body: body)
                case .key(let body):
                    envelope = try WireCoding.envelope(type: WireType.key, body: body)
                case .text(let body):
                    envelope = try WireCoding.envelope(type: WireType.text, body: body)
                case .media(let body):
                    envelope = try WireCoding.envelope(type: WireType.media, body: body)
                case .launch(let body):
                    envelope = try WireCoding.envelope(type: WireType.launch, body: body)
                case .system(let body):
                    envelope = try WireCoding.envelope(type: WireType.system, body: body)
                }
                try await connection.send(envelope)
            } catch {
                return
            }
        }
    }

    public func forget(id: UUID) async throws {
        try await registry.forget(id: id)
        if pin?.id == id {
            pin = nil
        }
    }

    public func pairedMacs() async -> [PairedMac] {
        await registry.all()
    }

    public func makeAppStream() -> AsyncStream<[AppRecord]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [AppRecord].self, bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        appContinuations[id] = continuation
        continuation.yield(apps)
        continuation.onTermination = { @Sendable _ in
            Task { await self.removeAppContinuation(id) }
        }
        return stream
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

    private func sessionLoop() async {
        while userWantsConnection && !Task.isCancelled {
            let end = await runOnce()
            switch end {
            case .stop(let message):
                guard userWantsConnection else { return }
                setSnapshot(SessionSnapshot(state: .failed(message), note: message))
                return
            case .reconnect:
                guard userWantsConnection, config.autoReconnect, pin != nil else { return }
                attempt += 1
                if attempt > config.reconnectAttempts {
                    setSnapshot(SessionSnapshot(state: .failed("Could not reconnect."), note: "Could not reconnect."))
                    return
                }
                setSnapshot(SessionSnapshot(state: .reconnecting(attempt: attempt)))
                try? await Task.sleep(for: ReconnectPolicy.delay(afterFailedAttempt: attempt - 1))
            }
        }
    }

    private func runOnce() async -> RunEnd {
        guard let endpoint else { return .stop("There is no Mac to connect to.") }
        let box = PeerKeyBox()
        let tlsPin: TLSPin
        if let pin {
            tlsPin = .pinned(canonical: pin.tlsPublicKey, observed: pin.observedPeerKey)
        } else {
            tlsPin = .acceptForPairing
        }
        let raw = NWConnection(to: endpoint, using: TLSConfiguration.clientParameters(pin: tlsPin, observedKey: box))
        let connection = FrameConnection(connection: raw, maxFrame: config.maxFrameSize)
        let queue = SessionQueue()
        self.connection = connection
        self.queue = queue
        setSnapshot(SessionSnapshot(state: .connecting))
        defer {
            queue.finish("The session ended.")
            Task { await connection.cancel() }
        }
        do {
            try await connection.ready(timeout: config.connectTimeout)
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
            defer { reader.cancel() }
            guard TLSConfiguration.isTLS13(raw) else { throw RemoteError.tlsUntrusted }
            guard let observed = box.load(), !observed.isEmpty else { throw RemoteError.tlsUntrusted }
            if let pin {
                let matches = observed == pin.observedPeerKey || PeerKey.matches(canonical: pin.tlsPublicKey, observed: observed)
                guard matches else { throw RemoteError.tlsUntrusted }
            }
            let clientNonce = try RandomBytes.generate(count: Limits.nonceLength)
            let hello = ClientHello(
                versions: [Limits.protocolVersion],
                deviceID: identity.deviceID,
                name: DeviceName.sanitize("iPhone", fallback: "iPhone"),
                publicKey: identity.publicKey,
                nonce: clientNonce,
                wantsPairing: pin == nil
            )
            // The display name is supplied by the app through a later setter. The handshake below uses the stored name.
            try await connection.send(try WireCoding.envelope(type: WireType.hello, body: replacedName(hello)))
            let serverHello = try await expect(queue, type: WireType.helloAck, timeout: config.connectTimeout, as: ServerHello.self)
            try PayloadValidation.serverHello(serverHello)
            if let expectedDeviceID, serverHello.deviceID != expectedDeviceID {
                throw RemoteError.tlsUntrusted
            }
            guard PeerKey.matches(canonical: serverHello.publicKey, observed: observed) else {
                throw RemoteError.tlsUntrusted
            }
            if serverHello.paired {
                guard pin != nil else { throw RemoteError.tlsUntrusted }
                setSnapshot(SessionSnapshot(state: .authenticating))
                try await authenticate(queue, connection: connection, serverHello: serverHello, clientNonce: clientNonce)
            } else {
                try await pair(
                    queue,
                    connection: connection,
                    serverHello: serverHello,
                    clientNonce: clientNonce,
                    observed: observed
                )
            }
            try await remember(serverHello, observed: observed)
            setSnapshot(SessionSnapshot(state: .ready(peerName: serverHello.name)))
            RemoteLog.session.info("Connected to Mac")
            try await pump(queue, connection: connection)
            return .reconnect
        } catch {
            if !userWantsConnection {
                return .stop("Disconnected.")
            }
            let message = SessionText.describe(error)
            RemoteLog.session.error("Client session failed: \(message, privacy: .public)")
            setSnapshot(SessionSnapshot(state: .failed(message), note: message))
            return retryable(error) ? .reconnect : .stop(message)
        }
    }

    private func replacedName(_ hello: ClientHello) -> ClientHello {
        ClientHello(
            versions: hello.versions,
            deviceID: hello.deviceID,
            name: displayName,
            publicKey: hello.publicKey,
            nonce: hello.nonce,
            wantsPairing: hello.wantsPairing
        )
    }

    public func setDisplayName(_ name: String) {
        displayName = DeviceName.sanitize(name, fallback: "iPhone")
    }

    private var displayName = "iPhone"

    private func authenticate(
        _ queue: SessionQueue,
        connection: FrameConnection,
        serverHello: ServerHello,
        clientNonce: Data
    ) async throws {
        let challenge = try await expect(queue, type: WireType.authChallenge, timeout: config.connectTimeout, as: AuthChallenge.self)
        guard challenge.challenge.count == Limits.nonceLength else { throw RemoteError.unauthorized }
        let message = DeviceSignature.message(
            challenge: challenge.challenge,
            serverPublicKey: serverHello.publicKey,
            clientNonce: clientNonce,
            serverNonce: serverHello.nonce,
            clientID: identity.deviceID
        )
        let signature = try DeviceSignature.sign(message, with: identity.privateKey)
        try await connection.send(try WireCoding.envelope(type: WireType.authResponse, body: AuthResponse(signature: signature)))
        let result = try await expect(queue, type: WireType.authResult, timeout: config.connectTimeout, as: AuthResult.self)
        guard result.ok else { throw RemoteError.unauthorized }
    }

    private func pair(
        _ queue: SessionQueue,
        connection: FrameConnection,
        serverHello: ServerHello,
        clientNonce: Data,
        observed: Data
    ) async throws {
        let code = PairingCode.make(
            serverPublicKey: serverHello.publicKey,
            clientPublicKey: identity.publicKey,
            clientNonce: clientNonce,
            serverNonce: serverHello.nonce
        )
        let expires = Date().addingTimeInterval(DurationClock.seconds(config.pairingTimeout))
        setSnapshot(SessionSnapshot(state: .pairing(code: code, expires: expires)))
        let timeoutID = UUID()
        let pairingTimeout = config.pairingTimeout
        let timer = Task {
            try? await Task.sleep(for: pairingTimeout)
            queue.push(.timeout(timeoutID))
        }
        defer { timer.cancel() }
        var confirmed = false
        if let queuedDecision {
            self.queuedDecision = nil
            try await connection.send(try WireCoding.envelope(type: WireType.pairConfirm, body: PairConfirm(accept: queuedDecision)))
            confirmed = true
            if !queuedDecision { throw RemoteError.pairingFailed }
        }
        while true {
            switch await queue.next() {
            case .decision(let match):
                try await connection.send(try WireCoding.envelope(type: WireType.pairConfirm, body: PairConfirm(accept: match)))
                confirmed = true
                if !match { throw RemoteError.pairingFailed }
            case .message(let envelope):
                if envelope.type == WireType.pairResult {
                    let result = try WireCoding.decodePayload(PairResult.self, from: envelope.payload)
                    guard result.paired else {
                        if result.reason == "expired" { throw RemoteError.pairingExpired }
                        throw RemoteError.pairingFailed
                    }
                    guard confirmed else { throw RemoteError.pairingFailed }
                    return
                }
                if envelope.type == WireType.error {
                    throw error(from: envelope)
                }
            case .timeout(let id):
                guard id == timeoutID else { continue }
                throw RemoteError.pairingExpired
            case .closed(let reason):
                throw RemoteError.invalid(reason)
            }
        }
    }

    private func pump(_ queue: SessionQueue, connection: FrameConnection) async throws {
        let interval = config.heartbeatInterval
        let heart = Task {
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                sequence += 1
                if let envelope = try? WireCoding.envelope(type: WireType.heartbeat, body: HeartbeatBody(seq: sequence)) {
                    try? await connection.send(envelope)
                }
            }
        }
        let livenessID = UUID()
        let watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.checkLiveness(queue: queue, timeoutID: livenessID)
            }
        }
        defer {
            heart.cancel()
            watch.cancel()
        }
        lastInbound = ContinuousClock().now
        while true {
            switch await queue.next() {
            case .message(let envelope):
                lastInbound = ContinuousClock().now
                try await handleReady(envelope)
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

    private func checkLiveness(queue: SessionQueue, timeoutID: UUID) {
        guard case .ready = snapshot.state else { return }
        if lastInbound.duration(to: ContinuousClock().now) > config.livenessTimeout {
            queue.push(.timeout(timeoutID))
        }
    }

    private func handleReady(_ envelope: Envelope) async throws {
        guard envelope.v == Limits.protocolVersion else { throw RemoteError.versionMismatch }
        switch envelope.type {
        case WireType.ack:
            let ack = try WireCoding.decodePayload(AckBody.self, from: envelope.payload)
            completeAck(ack.ref, result: .success(ack))
            if ack.ok {
                setSnapshot(SessionSnapshot(state: snapshot.state, note: "The Mac acknowledged the test command."))
            }
        case WireType.heartbeat:
            return
        case WireType.bye:
            throw RemoteError.closed
        case WireType.error:
            let failure = error(from: envelope)
            if Self.isFatal(failure) {
                throw failure
            }
            let message = SessionText.describe(failure)
            if snapshot.note != message {
                setSnapshot(SessionSnapshot(state: snapshot.state, note: message))
            }
        case WireType.apps:
            guard let catalog = try? WireCoding.decodePayload(AppCatalog.self, from: envelope.payload),
                  (try? PayloadValidation.catalog(catalog)) != nil else { return }
            setApps(catalog.apps)
        default:
            break
        }
    }

    private static func isFatal(_ error: Error) -> Bool {
        guard let remote = error as? RemoteError else { return true }
        switch remote {
        case .revoked, .pairingExpired, .pairingFailed, .versionMismatch, .unauthorized, .tlsUntrusted:
            return true
        default:
            return false
        }
    }

    private func expect<T: Decodable>(
        _ queue: SessionQueue,
        type: String,
        timeout: Duration,
        as valueType: T.Type
    ) async throws -> T {
        let timeoutID = UUID()
        let timer = Task {
            try? await Task.sleep(for: timeout)
            queue.push(.timeout(timeoutID))
        }
        defer { timer.cancel() }
        while true {
            switch await queue.next() {
            case .message(let envelope):
                if envelope.type == WireType.error { throw error(from: envelope) }
                guard envelope.type == type else { continue }
                guard envelope.v == Limits.protocolVersion else { throw RemoteError.versionMismatch }
                return try WireCoding.decodePayload(valueType, from: envelope.payload)
            case .timeout(let id):
                guard id == timeoutID else { continue }
                throw RemoteError.timeout
            case .closed(let reason):
                throw RemoteError.invalid(reason)
            case .decision(let match):
                queuedDecision = match
            }
        }
    }

    private func remember(_ hello: ServerHello, observed: Data) async throws {
        var record = await registry.mac(id: hello.deviceID) ?? PairedMac(
            id: hello.deviceID,
            name: hello.name,
            tlsPublicKey: hello.publicKey,
            observedPeerKey: observed,
            pairedAt: Date()
        )
        record.name = hello.name
        record.tlsPublicKey = hello.publicKey
        record.observedPeerKey = observed
        record.lastConnected = Date()
        try await registry.upsert(record)
        pin = record
    }

    private func error(from envelope: Envelope) -> Error {
        let body = try? WireCoding.decodePayload(ErrorBody.self, from: envelope.payload)
        switch body?.code {
        case ErrorCode.revoked:
            return RemoteError.revoked
        case ErrorCode.expired:
            return RemoteError.pairingExpired
        case ErrorCode.denied:
            return RemoteError.pairingFailed
        case ErrorCode.version:
            return RemoteError.versionMismatch
        case ErrorCode.unauthorized, ErrorCode.mismatch:
            return RemoteError.unauthorized
        default:
            return RemoteError.invalid(PayloadValidation.errorMessage(body?.message ?? "The Mac rejected the session."))
        }
    }

    private func retryable(_ error: Error) -> Bool {
        guard config.autoReconnect, pin != nil else { return false }
        if case RemoteError.timeout = error { return true }
        if case RemoteError.closed = error { return true }
        if let remote = error as? RemoteError, remote.safeDescription == RemoteError.closed.safeDescription {
            return true
        }
        let text = SessionText.describe(error)
        return text == RemoteError.closed.safeDescription || text == RemoteError.timeout.safeDescription
    }

    private func waitFor(timeout: Duration, where match: (LinkState) -> Bool) async throws -> LinkState {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if match(snapshot.state) { return snapshot.state }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw RemoteError.timeout
    }

    private func completeAck(_ id: UUID, result: Result<AckBody, Error>) {
        guard let waiter = ackWaiters.removeValue(forKey: id) else { return }
        waiter.resume(with: result)
    }

    private func failAcks(_ error: Error) {
        let waiters = ackWaiters
        ackWaiters.removeAll()
        for waiter in waiters.values {
            waiter.resume(throwing: error)
        }
    }

    private func setSnapshot(_ snapshot: SessionSnapshot) {
        let wasReady = if case .ready = self.snapshot.state { true } else { false }
        let isReady = if case .ready = snapshot.state { true } else { false }
        self.snapshot = snapshot
        if wasReady && !isReady {
            setApps([])
        }
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func setApps(_ apps: [AppRecord]) {
        self.apps = apps
        for continuation in appContinuations.values {
            continuation.yield(apps)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func removeAppContinuation(_ id: UUID) {
        appContinuations[id] = nil
    }

    private enum RunEnd {
        case reconnect
        case stop(String)
    }
}
