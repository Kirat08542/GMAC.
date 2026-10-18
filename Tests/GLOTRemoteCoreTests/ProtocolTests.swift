import CryptoKit
import Foundation
import Network
import Security
import Testing
@testable import GLOTRemoteCore

@Test func frameRoundTripAndSplit() throws {
    let envelope = Envelope(type: WireType.test, payload: Data([9, 8, 7]), id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID())
    let frame = try FrameCodec.encode(envelope)
    let decoded = try FrameCodec.decode(frame.dropFirst(4))
    #expect(decoded == envelope)

    var buffer = FrameBuffer()
    let head = frame.prefix(5)
    #expect(try buffer.append(head, maxFrame: Limits.maxFrame).isEmpty)
    let frames = try buffer.append(frame.dropFirst(5), maxFrame: Limits.maxFrame)
    #expect(frames.count == 1)
    #expect(try FrameCodec.decode(frames[0]) == envelope)
}

@Test func frameRejectsDeclaredOversize() {
    var buffer = FrameBuffer()
    let chunk = Data([0x00, 0x01, 0x00, 0x01])
    #expect(throws: RemoteError.oversized) {
        _ = try buffer.append(chunk, maxFrame: Limits.maxFrame)
    }
}

@Test func frameRejectsGarbage() {
    #expect(throws: RemoteError.invalid("The message could not be read.")) {
        _ = try FrameCodec.decode(Data("not-json".utf8))
    }
}

@Test func versionIsPreservedAndPolicyRejectsIt() throws {
    let envelope = Envelope(type: WireType.test, version: 99)
    let decoded = try FrameCodec.decode(try FrameCodec.encode(envelope).dropFirst(4))
    #expect(decoded.v == 99)
    #expect(ControlPolicy.decide(type: WireType.test, authenticated: false, payload: Data()) == .unauthorized)
}

@Test func duplicateIdentifiersAreRejected() {
    var deduper = MessageDeduper()
    let id = UUID()
    let first = deduper.insert(id)
    let second = deduper.insert(id)
    let third = deduper.insert(UUID())
    #expect(first)
    #expect(!second)
    #expect(third)
}

@Test func rateLimiterCapsAWindow() {
    var limiter = RateLimiter()
    let start = ContinuousClock().now
    var accepted = 0
    for _ in 0..<3 where limiter.allow(now: start, limit: 3, window: .seconds(1)) {
        accepted += 1
    }
    let blocked = limiter.allow(now: start, limit: 3, window: .seconds(1))
    let later = limiter.allow(now: start.advanced(by: .seconds(2)), limit: 3, window: .seconds(1))
    #expect(accepted == 3)
    #expect(!blocked)
    #expect(later)
}

@Test func reconnectDelaysBackOff() {
    #expect(ReconnectPolicy.delay(afterFailedAttempt: 0) == .seconds(1))
    #expect(ReconnectPolicy.delay(afterFailedAttempt: 1) == .seconds(2))
    #expect(ReconnectPolicy.delay(afterFailedAttempt: 3) == .seconds(8))
    #expect(ReconnectPolicy.delay(afterFailedAttempt: 8) == .seconds(15))
}

@Test func pairingCodeIsStableAndBoundToTheMacKey() {
    let server = Data([0x04]) + Data(repeating: 1, count: 64)
    let other = Data([0x04]) + Data(repeating: 2, count: 64)
    let client = Data(repeating: 3, count: 64)
    let clientNonce = Data(repeating: 4, count: 32)
    let serverNonce = Data(repeating: 5, count: 32)
    let first = PairingCode.digest(serverPublicKey: server, clientPublicKey: client, clientNonce: clientNonce, serverNonce: serverNonce)
    let second = PairingCode.digest(serverPublicKey: server, clientPublicKey: client, clientNonce: clientNonce, serverNonce: serverNonce)
    let swapped = PairingCode.digest(serverPublicKey: other, clientPublicKey: client, clientNonce: clientNonce, serverNonce: serverNonce)
    #expect(first == second)
    #expect(first != swapped)
    let code = PairingCode.make(serverPublicKey: server, clientPublicKey: client, clientNonce: clientNonce, serverNonce: serverNonce)
    let digitsOnly = code.allSatisfy { $0.isNumber }
    #expect(code.count == 6)
    #expect(digitsOnly)
}

@Test func expiredPairingBeatsLateApproval() {
    var gate = PairingGate(deadline: Date().addingTimeInterval(-5))
    gate.clientAccepted = true
    gate.serverAccepted = true
    #expect(gate.result(now: Date()) == .expired)
}

@Test func pairingGateRequiresBothApprovals() {
    var gate = PairingGate(deadline: Date().addingTimeInterval(30))
    #expect(gate.result(now: Date()) == .pending)
    gate.clientAccepted = true
    #expect(gate.result(now: Date()) == .pending)
    gate.serverAccepted = false
    #expect(gate.result(now: Date()) == .denied)
    gate.serverAccepted = true
    #expect(gate.result(now: Date()) == .approved)
}

@Test func revokedAndMismatchedPhonesCannotPair() {
    let key = Data(repeating: 7, count: 64)
    let phone = PairedPhone(id: UUID(), name: "Phone", signingKey: key, pairedAt: Date(), revoked: true)
    #expect(Trust.decide(record: phone, presentedKey: key) == .reject("revoked"))
    var active = phone
    active.revoked = false
    #expect(Trust.decide(record: active, presentedKey: key) == .authenticate)
    #expect(Trust.decide(record: active, presentedKey: Data(repeating: 8, count: 64)) == .reject("mismatch"))
    #expect(Trust.decide(record: nil, presentedKey: key) == .pair)
}

@Test func signatureRejectsTampering() throws {
    let key = P256.Signing.PrivateKey()
    let message = DeviceSignature.message(
        challenge: Data(repeating: 1, count: 32),
        serverPublicKey: Data(repeating: 2, count: 65),
        clientNonce: Data(repeating: 3, count: 32),
        serverNonce: Data(repeating: 4, count: 32),
        clientID: UUID()
    )
    let signature = try DeviceSignature.sign(message, with: key)
    #expect(DeviceSignature.verify(signature: signature, message: message, publicKey: key.publicKey.rawRepresentation))
    var tampered = message
    tampered.append(0)
    #expect(!DeviceSignature.verify(signature: signature, message: tampered, publicKey: key.publicKey.rawRepresentation))
    let other = P256.Signing.PrivateKey()
    #expect(!DeviceSignature.verify(signature: signature, message: message, publicKey: other.publicKey.rawRepresentation))
}

@Test func keyboardModifiersAndClipboardLimits() throws {
    try PayloadValidation.key(KeyBody(key: "4", modifiers: ["command", "shift"], phase: "down"))
    try PayloadValidation.key(KeyBody(key: "c", modifiers: ["command"], phase: "up"))
    #expect(throws: RemoteError.invalid("A modifier key is repeated.")) {
        try PayloadValidation.key(KeyBody(key: "c", modifiers: ["command", "command"], phase: "down"))
    }
    #expect(throws: RemoteError.invalid("Character keys on this channel need a modifier. Text uses the text command.")) {
        try PayloadValidation.key(KeyBody(key: "c", modifiers: [], phase: "down"))
    }
    let pointer = try WireCoding.encodePayload(PointerBatch(samples: [PointerSample(dx: 4, dy: -3)]))
    #expect(ControlPolicy.decide(type: WireType.pointer, authenticated: false, payload: pointer) == .unauthorized)
    #expect(ControlPolicy.decide(type: WireType.pointer, authenticated: true, payload: pointer) == .handle)
    let tooBig = String(repeating: "a", count: Limits.maxClipboardBytes + 1)
    #expect(throws: RemoteError.invalid("Clipboard text is empty or over the 16 KB limit.")) {
        try PayloadValidation.clipboard(ClipboardBody(text: tooBig))
    }
    #expect(throws: RemoteError.invalid("The application identifier is not valid.")) {
        try PayloadValidation.launch(LaunchBody(bundleID: "rm -rf /"))
    }
    #expect(throws: RemoteError.invalid("This action needs confirmation.")) {
        try PayloadValidation.system(SystemBody(action: "sleep", confirmed: false))
    }
}

@Test func clipboardPolicyAndWakeAddress() throws {
    let clip = try WireCoding.encodePayload(ClipboardBody(text: "hello mac"))
    #expect(ControlPolicy.decide(type: WireType.clipPush, authenticated: false, payload: clip) == .unauthorized)
    #expect(ControlPolicy.decide(type: WireType.clipPush, authenticated: true, payload: clip) == .handle)
    #expect(ControlPolicy.decide(type: WireType.clipPull, authenticated: true, payload: Data()) == .handle)
    #expect(ControlPolicy.decide(type: WireType.clipData, authenticated: true, payload: clip) == .unsupported)

    var key = Data(repeating: 0, count: Limits.tlsPublicKeyLength)
    key[0] = 0x04
    let hello = ServerHello(
        version: Limits.protocolVersion,
        deviceID: UUID(),
        name: "Mac",
        publicKey: key,
        nonce: Data(repeating: 0, count: Limits.nonceLength),
        paired: true,
        macAddress: "aa:bb:cc:dd:ee:ff"
    )
    try PayloadValidation.serverHello(hello)
    var badMAC = hello
    badMAC.macAddress = "not-a-mac"
    #expect(throws: RemoteError.invalid("The Mac address is not valid.")) {
        try PayloadValidation.serverHello(badMAC)
    }
    var noMAC = hello
    noMAC.macAddress = nil
    try PayloadValidation.serverHello(noMAC)

    // Wake address survives the record round trip.
    var mac = PairedMac(
        id: UUID(), name: "Mac", tlsPublicKey: key, observedPeerKey: key,
        pairedAt: Date(), wakeMAC: "aa:bb:cc:dd:ee:ff"
    )
    let data = try WireCoding.encodePayload(mac)
    mac = try WireCoding.decodePayload(PairedMac.self, from: data)
    #expect(mac.wakeMAC == "aa:bb:cc:dd:ee:ff")
}

@Test func certificatePublicKeyMatchesThePrivateKey() throws {
    let material = try TLSMaterial.ephemeral()
    guard let certificateKey = SecCertificateCopyKey(material.certificate) else {
        Issue.record("Certificate has no key")
        return
    }
    var error: Unmanaged<CFError>?
    let external = SecKeyCopyExternalRepresentation(certificateKey, &error) as Data?
    #expect(external == material.canonicalPublicKey)
}

@Test func pairedPhoneFileRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let registry = try FilePhoneRegistry(directory: directory)
    let phone = PairedPhone(id: UUID(), name: "Kitchen", signingKey: Data(repeating: 4, count: 64), pairedAt: Date())
    try await registry.upsert(phone)
    try await registry.setRevoked(id: phone.id, revoked: true)
    let reloaded = try FilePhoneRegistry(directory: directory)
    let stored = await reloaded.phone(id: phone.id)
    #expect(stored?.revoked == true)
    #expect(stored?.signingKey == phone.signingKey)
    try await reloaded.forget(id: phone.id)
    #expect(await reloaded.phone(id: phone.id) == nil)
    try? FileManager.default.removeItem(at: directory)
}

@Suite(.serialized)
struct LiveTLSTests {
    @Test func pairThenAcknowledgeATestCommand() async throws {
        let config = testConfig(pairingTimeout: .seconds(5))
        let material = try TLSMaterial.ephemeral()
        let registry = InMemoryPhoneRegistry()
        let server = RemoteControlServer(
            identity: material,
            registry: registry,
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let client = RemoteControlClient(identity: SigningIdentity.ephemeral(), registry: InMemoryMacRegistry(), config: config)
        let endpoint = try loopback(port)
        let state = try await client.connect(endpoint: endpoint, expectedDeviceID: nil, pin: nil)
        guard case .pairing(let clientCode, _) = state else {
            Issue.record("Expected a pairing code, got \(state)")
            await server.stop()
            return
        }
        let serverState = await server.snapshot.state
        guard case .pairing(let serverCode, _) = serverState else {
            Issue.record("Mac did not show a pairing code")
            await server.stop()
            return
        }
        #expect(clientCode == serverCode)
        await client.resolvePairing(match: true)
        await server.resolvePairing(approve: true)
        try await wait(for: client, until: { if case .ready = $0 { return true } else { return false } })
        let ack = try await client.sendTest(nonce: Data("phase1".utf8))
        #expect(ack.ok)
        let saved = try #require(await client.pin)
        #expect(saved.observedPeerKey.count == 91)
        #expect(PeerKey.matches(canonical: saved.tlsPublicKey, observed: saved.observedPeerKey))
        #expect(Data(saved.observedPeerKey.suffix(65)) == saved.tlsPublicKey)
        try await wait(for: server, until: { $0.note.contains("acknowledged") })
        await client.disconnect()
        await server.stop()
    }

    @Test func denialDoesNotStoreThePhone() async throws {
        let config = testConfig(pairingTimeout: .seconds(5))
        let registry = InMemoryPhoneRegistry()
        let server = RemoteControlServer(
            identity: try TLSMaterial.ephemeral(),
            registry: registry,
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let identity = SigningIdentity.ephemeral()
        let client = RemoteControlClient(identity: identity, registry: InMemoryMacRegistry(), config: config)
        _ = try await client.connect(endpoint: try loopback(port), expectedDeviceID: nil, pin: nil)
        await client.resolvePairing(match: true)
        await server.resolvePairing(approve: false)
        try await wait(for: client, until: { if case .failed = $0 { return true } else { return false } })
        #expect(await registry.phone(id: identity.deviceID) == nil)
        await server.stop()
    }

    @Test func pairedPhoneAuthenticatesWithoutASecondCode() async throws {
        let config = testConfig(pairingTimeout: .seconds(5))
        let registry = InMemoryPhoneRegistry()
        let macRegistry = InMemoryMacRegistry()
        let server = RemoteControlServer(
            identity: try TLSMaterial.ephemeral(),
            registry: registry,
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let client = RemoteControlClient(identity: SigningIdentity.ephemeral(), registry: macRegistry, config: config)
        let endpoint = try loopback(port)
        _ = try await client.connect(endpoint: endpoint, expectedDeviceID: nil, pin: nil)
        await client.resolvePairing(match: true)
        await server.resolvePairing(approve: true)
        try await wait(for: client, until: { if case .ready = $0 { return true } else { return false } })
        let pin = try #require(await client.pin)
        await client.disconnect()
        try await wait(for: server, until: { if case .listening = $0.state { return true } else { return false } })
        let state = try await client.connect(endpoint: endpoint, expectedDeviceID: pin.id, pin: pin)
        guard case .ready = state else {
            Issue.record("Expected a saved Mac to authenticate, got \(state)")
            await server.stop()
            return
        }
        await server.stop()
    }

    @Test func revokedPhoneIsRejected() async throws {
        let config = testConfig(pairingTimeout: .seconds(5))
        let registry = InMemoryPhoneRegistry()
        let server = RemoteControlServer(
            identity: try TLSMaterial.ephemeral(),
            registry: registry,
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let client = RemoteControlClient(identity: SigningIdentity.ephemeral(), registry: InMemoryMacRegistry(), config: config)
        let endpoint = try loopback(port)
        _ = try await client.connect(endpoint: endpoint, expectedDeviceID: nil, pin: nil)
        await client.resolvePairing(match: true)
        await server.resolvePairing(approve: true)
        try await wait(for: client, until: { if case .ready = $0 { return true } else { return false } })
        let pin = try #require(await client.pin)
        let phoneID = try #require(await registry.all().first?.id)
        try await server.revoke(id: phoneID)
        await client.disconnect()
        try await wait(for: server, until: { if case .listening = $0.state { return true } else { return false } })
        await #expect(throws: RemoteError.self) {
            try await client.connect(endpoint: endpoint, expectedDeviceID: pin.id, pin: pin)
        }
        await server.stop()
    }

    @Test func mismatchedKeyCannotReplaceAPhone() async throws {
        let config = testConfig(pairingTimeout: .seconds(4))
        let identity = SigningIdentity.ephemeral()
        let registry = InMemoryPhoneRegistry(records: [
            PairedPhone(id: identity.deviceID, name: "Old", signingKey: Data(repeating: 9, count: 64), pairedAt: Date()),
        ])
        let server = RemoteControlServer(
            identity: try TLSMaterial.ephemeral(),
            registry: registry,
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let client = RemoteControlClient(identity: identity, registry: InMemoryMacRegistry(), config: config)
        await #expect(throws: RemoteError.self) {
            try await client.connect(endpoint: try loopback(port), expectedDeviceID: nil, pin: nil)
        }
        let record = await registry.phone(id: identity.deviceID)
        #expect(record?.signingKey == Data(repeating: 9, count: 64))
        await server.stop()
    }

    @Test func unansweredPairingExpires() async throws {
        let config = testConfig(pairingTimeout: .seconds(1))
        let server = RemoteControlServer(
            identity: try TLSMaterial.ephemeral(),
            registry: InMemoryPhoneRegistry(),
            deviceID: UUID(),
            deviceName: "Test Mac",
            config: config
        )
        let port = try await server.start(advertise: false)
        let client = RemoteControlClient(identity: SigningIdentity.ephemeral(), registry: InMemoryMacRegistry(), config: config)
        _ = try await client.connect(endpoint: try loopback(port), expectedDeviceID: nil, pin: nil)
        try await wait(for: client, until: { if case .failed = $0 { return true } else { return false } }, timeout: .seconds(4))
        await server.stop()
    }
}

@Test func keychainRoundTrip() throws {
    let account = "test.probe.\(UUID().uuidString)"
    defer { try? KeychainStore.delete(account: account) }
    let payload = Data("phase1".utf8)
    try KeychainStore.save(account: account, data: payload)
    let loaded = try KeychainStore.load(account: account)
    #expect(loaded == payload)

    let tag = Data("com.glot.remote.test.\(UUID().uuidString)".utf8)
    defer {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false],
    ]
    var error: Unmanaged<CFError>?
    let created = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    try KeychainStore.savePrivateKey(created, tag: tag)
    let stored = try #require(try KeychainStore.loadPrivateKey(tag: tag))
    let createdPublic = try #require(SecKeyCopyPublicKey(created))
    let storedPublic = try #require(SecKeyCopyPublicKey(stored))
    let createdBytes = try #require(SecKeyCopyExternalRepresentation(createdPublic, nil) as Data?)
    let storedBytes = try #require(SecKeyCopyExternalRepresentation(storedPublic, nil) as Data?)
    #expect(createdBytes == storedBytes)
}

private func testConfig(pairingTimeout: Duration) -> TransportConfig {
    TransportConfig(
        connectTimeout: .seconds(5),
        pairingTimeout: pairingTimeout,
        heartbeatInterval: .seconds(1),
        livenessTimeout: .seconds(4),
        autoReconnect: false
    )
}

private func loopback(_ port: UInt16) throws -> NWEndpoint {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        throw RemoteError.invalid("Bad test port.")
    }
    return .hostPort(host: .ipv4(.loopback), port: nwPort)
}

private func wait(
    for client: RemoteControlClient,
    until match: (LinkState) -> Bool,
    timeout: Duration = .seconds(5)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if match(await client.snapshot.state) { return }
        if case .failed(let message) = await client.snapshot.state, !match(await client.snapshot.state) {
            throw RemoteError.invalid(message)
        }
        try await Task.sleep(for: .milliseconds(30))
    }
    throw RemoteError.timeout
}

private func wait(
    for server: RemoteControlServer,
    until match: (SessionSnapshot) -> Bool,
    timeout: Duration = .seconds(5)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if match(await server.snapshot) { return }
        try await Task.sleep(for: .milliseconds(30))
    }
    throw RemoteError.timeout
}

