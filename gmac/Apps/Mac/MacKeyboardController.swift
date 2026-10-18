import AppKit
import Carbon
import GLOTRemoteCore

/// Posts keystrokes only while this process is trusted for Accessibility.
/// Secure input, such as a password field, blocks the events and nothing is typed.
final class MacKeyboardController: RemoteKeyboard, @unchecked Sendable {
    static let permissionMessage = "Allow Accessibility for GLOT Remote Mac in System Settings. The keys were not sent."
    static let secureMessage = "The Mac is in a secure field, such as a password box. The keys were not sent."

    private let lock = NSLock()
    private let source: CGEventSource?
    private var held: [String: CGKeyCode] = [:]

    init() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        self.source = source
    }

    func key(_ body: KeyBody) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTrust()
        try refuseSecureInput()
        let (code, flags) = try resolved(body)
        let down = body.phase == "down"
        if down {
            guard held[body.key] == nil else { return }
            try post(code: code, flags: flags, down: true)
            held[body.key] = code
        } else {
            held.removeValue(forKey: body.key)
            try post(code: code, flags: flags, down: false)
        }
    }

    func text(_ body: TextBody) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTrust()
        try refuseSecureInput()
        var units: [UniChar] = []
        func flush() throws {
            guard !units.isEmpty else { return }
            try postUnicode(units)
            units.removeAll(keepingCapacity: true)
        }
        for scalar in body.text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                try flush()
                try post(code: Self.codes["return"] ?? 0x24, flags: [], down: true)
                try post(code: Self.codes["return"] ?? 0x24, flags: [], down: false)
                continue
            }
            if scalar == "\t" {
                try flush()
                try post(code: Self.codes["tab"] ?? 0x30, flags: [], down: true)
                try post(code: Self.codes["tab"] ?? 0x30, flags: [], down: false)
                continue
            }
            let piece = Array(String(scalar).utf16)
            if units.count + piece.count > 20 {
                try flush()
            }
            units.append(contentsOf: piece)
        }
        try flush()
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        let codes = Array(held.values)
        held.removeAll()
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return }
        for code in codes {
            try? post(code: code, flags: [], down: false)
        }
    }

    private func requireTrust() throws {
        guard AXIsProcessTrusted() else {
            throw RemoteError.invalid(Self.permissionMessage)
        }
    }

    private func refuseSecureInput() throws {
        guard !IsSecureEventInputEnabled() else {
            throw RemoteError.invalid(Self.secureMessage)
        }
    }

    private func resolved(_ body: KeyBody) throws -> (CGKeyCode, CGEventFlags) {
        var flags = eventFlags(body.modifiers)
        var name = body.key
        if name.count == 1, let scalar = name.unicodeScalars.first, scalar >= "A" && scalar <= "Z" {
            flags.insert(.maskShift)
            name = name.lowercased()
        }
        guard let code = Self.codes[name] else {
            throw RemoteError.invalid("The key is not supported.")
        }
        return (code, flags)
    }

    private func eventFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains("command") { flags.insert(.maskCommand) }
        if modifiers.contains("option") { flags.insert(.maskAlternate) }
        if modifiers.contains("control") { flags.insert(.maskControl) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        return flags
    }

    private func post(code: CGKeyCode, flags: CGEventFlags, down: Bool) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            throw RemoteError.invalid("macOS did not create a key event.")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postUnicode(_ units: [UniChar]) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw RemoteError.invalid("macOS did not create a key event.")
        }
        units.withUnsafeBufferPointer { buffer in
            guard let address = buffer.baseAddress else { return }
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: address)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: address)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static let codes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
        "arrowLeft": 0x7B, "arrowRight": 0x7C, "arrowDown": 0x7D, "arrowUp": 0x7E,
    ]
}
