import AppKit
import Carbon
import GLOTRemoteCore

/// Posts the same system media keys as the Mac keyboard.
/// Play, pause, and skip go to whichever app is playing. Volume is the system volume.
final class MacMediaController: RemoteMedia, @unchecked Sendable {
    static let permissionMessage = "Allow Accessibility for GLOT Remote Mac in System Settings. The media key was not sent."
    static let secureMessage = "The Mac is in a secure field, such as a password box. The media key was not sent."

    private let lock = NSLock()

    func perform(_ body: MediaBody) throws {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else {
            throw RemoteError.invalid(Self.permissionMessage)
        }
        guard !IsSecureEventInputEnabled() else {
            throw RemoteError.invalid(Self.secureMessage)
        }
        guard let code = Self.keys[body.action] else {
            throw RemoteError.invalid("The media action is not supported.")
        }
        try post(code)
    }

    private func post(_ code: Int32) throws {
        try post(code, pressed: true)
        try post(code, pressed: false)
    }

    private func post(_ code: Int32, pressed: Bool) throws {
        let marker: Int = pressed ? 0xA : 0xB
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(marker) << 8),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (Int(code) << 16) | (marker << 8),
            data2: -1
        ), let posted = event.cgEvent else {
            throw RemoteError.invalid("macOS did not create a media key.")
        }
        posted.post(tap: .cghidEventTap)
    }

    // Values from IOKit ev_keymap.h. 16 is the play/pause key.
    private static let keys: [String: Int32] = [
        "playPause": 16,
        "next": 17,
        "previous": 18,
        "volumeUp": 0,
        "volumeDown": 1,
        "mute": 7,
    ]
}
