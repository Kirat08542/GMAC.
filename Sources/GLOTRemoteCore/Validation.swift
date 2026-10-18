import Foundation

public enum PayloadValidation {
    public static func clientHello(_ hello: ClientHello) throws {
        guard hello.versions.contains(Limits.protocolVersion) else {
            throw RemoteError.versionMismatch
        }
        guard hello.publicKey.count == Limits.signingKeyLength else {
            throw RemoteError.invalid("The iPhone identity key is the wrong size.")
        }
        guard hello.nonce.count == Limits.nonceLength else {
            throw RemoteError.invalid("The handshake nonce is the wrong size.")
        }
        guard hello.name.count <= Limits.maxNameLength, !hello.name.isEmpty else {
            throw RemoteError.invalid("The device name is not valid.")
        }
        guard hello.name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            throw RemoteError.invalid("The device name is not valid.")
        }
    }

    public static func serverHello(_ hello: ServerHello) throws {
        guard hello.version == Limits.protocolVersion else {
            throw RemoteError.versionMismatch
        }
        guard hello.publicKey.count == Limits.tlsPublicKeyLength, hello.publicKey.first == 0x04 else {
            throw RemoteError.invalid("The Mac identity key is the wrong size.")
        }
        guard hello.nonce.count == Limits.nonceLength else {
            throw RemoteError.invalid("The handshake nonce is the wrong size.")
        }
        guard hello.name.count <= Limits.maxNameLength, !hello.name.isEmpty else {
            throw RemoteError.invalid("The device name is not valid.")
        }
        if let mac = hello.macAddress {
            let pattern = #"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$"#
            guard mac.range(of: pattern, options: .regularExpression) != nil else {
                throw RemoteError.invalid("The Mac address is not valid.")
            }
        }
    }

    public static func pointer(_ batch: PointerBatch) throws {
        guard (1...Limits.maxPointerSamples).contains(batch.samples.count) else {
            throw RemoteError.invalid("The pointer batch is the wrong size.")
        }
        for sample in batch.samples {
            guard inDelta(sample.dx), inDelta(sample.dy) else {
                throw RemoteError.invalid("A pointer movement is out of range.")
            }
        }
    }

    public static func mouse(_ body: MouseButtonBody) throws {
        guard body.button == "left" || body.button == "right" else {
            throw RemoteError.invalid("The mouse button is not supported.")
        }
        guard body.phase == "down" || body.phase == "up" else {
            throw RemoteError.invalid("The mouse action is not supported.")
        }
    }

    public static func scroll(_ body: ScrollBody) throws {
        guard inDelta(body.dx), inDelta(body.dy) else {
            throw RemoteError.invalid("The scroll distance is out of range.")
        }
        guard body.dx != 0 || body.dy != 0 else {
            throw RemoteError.invalid("The scroll event is empty.")
        }
    }

    public static func key(_ body: KeyBody) throws {
        guard body.phase == "down" || body.phase == "up" else {
            throw RemoteError.invalid("The key action is not supported.")
        }
        let allowedModifiers: Set<String> = ["command", "option", "control", "shift"]
        guard body.modifiers.count <= 4 else {
            throw RemoteError.invalid("Too many modifier keys.")
        }
        guard Set(body.modifiers).count == body.modifiers.count else {
            throw RemoteError.invalid("A modifier key is repeated.")
        }
        guard body.modifiers.allSatisfy({ allowedModifiers.contains($0) }) else {
            throw RemoteError.invalid("A modifier key is not supported.")
        }
        let bare = Set(["return", "escape", "tab", "delete", "arrowLeft", "arrowRight", "arrowUp", "arrowDown", "space"])
        if bare.contains(body.key) {
            return
        }
        guard body.key.count == 1, let scalar = body.key.unicodeScalars.first else {
            throw RemoteError.invalid("The key is not supported.")
        }
        let isLetter = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
        let isDigit = scalar >= "0" && scalar <= "9"
        guard isLetter || isDigit else {
            throw RemoteError.invalid("The key is not supported.")
        }
        guard !body.modifiers.isEmpty else {
            throw RemoteError.invalid("Character keys on this channel need a modifier. Text uses the text command.")
        }
    }

    public static func text(_ body: TextBody) throws {
        let count = body.text.utf8.count
        guard count > 0, count <= Limits.maxTextBytes else {
            throw RemoteError.invalid("The text is empty or too long.")
        }
        guard !body.text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw RemoteError.invalid("The text is not valid.")
        }
    }

    public static func media(_ body: MediaBody) throws {
        let allowed: Set<String> = ["playPause", "next", "previous", "volumeUp", "volumeDown", "mute"]
        guard allowed.contains(body.action) else {
            throw RemoteError.invalid("The media action is not supported.")
        }
    }

    public static func launch(_ body: LaunchBody) throws {
        guard body.bundleID.count >= 3, body.bundleID.count <= 155 else {
            throw RemoteError.invalid("The application identifier is not valid.")
        }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9\.\-]{1,154}$"#
        guard body.bundleID.range(of: pattern, options: .regularExpression) != nil else {
            throw RemoteError.invalid("The application identifier is not valid.")
        }
        guard !body.bundleID.contains("..") else {
            throw RemoteError.invalid("The application identifier is not valid.")
        }
    }

    public static func catalog(_ catalog: AppCatalog) throws {
        guard catalog.apps.count <= 40 else {
            throw RemoteError.invalid("The app list is too long.")
        }
        var seen = Set<String>()
        for app in catalog.apps {
            try launch(LaunchBody(bundleID: app.bundleID))
            guard seen.insert(app.bundleID).inserted else {
                throw RemoteError.invalid("The app list repeats an app.")
            }
            guard !app.name.isEmpty, app.name.count <= Limits.maxNameLength else {
                throw RemoteError.invalid("An app name is not valid.")
            }
            guard app.name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
                throw RemoteError.invalid("An app name is not valid.")
            }
        }
    }

    public static func system(_ body: SystemBody) throws {
        guard body.action == "lock" || body.action == "sleep" else {
            throw RemoteError.invalid("The system action is not supported.")
        }
        guard body.confirmed else {
            throw RemoteError.invalid("This action needs confirmation.")
        }
    }

    public static func clipboard(_ body: ClipboardBody) throws {
        let count = body.text.utf8.count
        guard count > 0, count <= Limits.maxClipboardBytes else {
            throw RemoteError.invalid("Clipboard text is empty or over the 16 KB limit.")
        }
        guard !body.text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw RemoteError.invalid("Clipboard text is not valid.")
        }
    }

    public static func errorMessage(_ message: String) -> String {
        let cleaned = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(cleaned.prefix(180))
    }

    private static func inDelta(_ value: Int32) -> Bool {
        value >= -Int32(Limits.maxPointerDelta) && value <= Int32(Limits.maxPointerDelta)
    }
}

public enum PolicyDecision: Sendable, Equatable {
    case session
    case handle
    case unsupported
    case unauthorized
    case invalid(String)
}

public enum ControlPolicy {
    /// Pointer, mouse, scroll, key, text, media, launch, confirmed sleep, and clipboard
    /// are handled after they validate. The Mac still opens only apps the user added.
    /// Lock stays refused.
    public static func decide(type: String, authenticated: Bool, payload: Data) -> PolicyDecision {
        if WireType.session.contains(type) {
            return .session
        }
        if !authenticated {
            return .unauthorized
        }
        switch type {
        case WireType.heartbeat, WireType.test, WireType.ack, WireType.error, WireType.bye:
            return .handle
        case WireType.pointer:
            return validate(PointerBatch.self, payload: payload, accept: .handle)
        case WireType.mouse:
            return validate(MouseButtonBody.self, payload: payload, accept: .handle)
        case WireType.scroll:
            return validate(ScrollBody.self, payload: payload, accept: .handle)
        case WireType.key:
            return validate(KeyBody.self, payload: payload, accept: .handle)
        case WireType.text:
            return validate(TextBody.self, payload: payload, accept: .handle)
        case WireType.media:
            return validate(MediaBody.self, payload: payload, accept: .handle)
        case WireType.launch:
            return validate(LaunchBody.self, payload: payload, accept: .handle)
        case WireType.apps:
            return .unsupported
        case WireType.system:
            let decision = validate(SystemBody.self, payload: payload, accept: .handle)
            if case .handle = decision,
               let body = try? WireCoding.decodePayload(SystemBody.self, from: payload),
               body.action != "sleep" {
                return .unsupported
            }
            return decision
        case WireType.clipPush:
            return validate(ClipboardBody.self, payload: payload, accept: .handle)
        case WireType.clipPull:
            return .handle
        case WireType.clipData:
            return .unsupported
        default:
            return .unsupported
        }
    }

    private static func validate<T: Decodable>(_ type: T.Type, payload: Data, accept: PolicyDecision) -> PolicyDecision {
        do {
            let value = try WireCoding.decodePayload(type, from: payload)
            try check(value)
            return accept
        } catch let error as RemoteError {
            return .invalid(error.safeDescription)
        } catch {
            return .invalid("The message payload is not valid.")
        }
    }

    private static func check<T>(_ value: T) throws {
        switch value {
        case let body as PointerBatch: try PayloadValidation.pointer(body)
        case let body as MouseButtonBody: try PayloadValidation.mouse(body)
        case let body as ScrollBody: try PayloadValidation.scroll(body)
        case let body as KeyBody: try PayloadValidation.key(body)
        case let body as TextBody: try PayloadValidation.text(body)
        case let body as MediaBody: try PayloadValidation.media(body)
        case let body as LaunchBody: try PayloadValidation.launch(body)
        case let body as SystemBody: try PayloadValidation.system(body)
        case let body as ClipboardBody: try PayloadValidation.clipboard(body)
        default:
            break
        }
    }
}
