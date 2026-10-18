import Foundation

/// Turns edits in the phone text field into key and text commands.
public enum KeyboardTyping {
    public static func commands(replacing old: String, with new: String) -> [TrackpadCommand] {
        guard old != new else { return [] }
        let prefix = old.commonPrefix(with: new)
        let removed = old.dropFirst(prefix.count).count
        let added = String(new.dropFirst(prefix.count))
        var commands: [TrackpadCommand] = []
        let deletes = min(removed, 80)
        for _ in 0..<deletes {
            commands.append(.key(KeyBody(key: "delete", modifiers: [], phase: "down")))
            commands.append(.key(KeyBody(key: "delete", modifiers: [], phase: "up")))
        }
        let clipped = clip(added)
        if !clipped.isEmpty {
            commands.append(.text(TextBody(text: clipped)))
        }
        return commands
    }

    /// One letter or digit, sent with the latched modifier keys.
    public static func shortcut(_ text: String, modifiers: Set<String>) -> [TrackpadCommand]? {
        guard !modifiers.isEmpty, text.count == 1, let scalar = text.unicodeScalars.first else { return nil }
        var names = modifiers
        let key: String
        if scalar >= "A" && scalar <= "Z" {
            names.insert("shift")
            key = text.lowercased()
        } else if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
            key = text
        } else {
            return nil
        }
        return chord(key, modifiers: ordered(names))
    }

    public static func chord(_ key: String, modifiers: [String]) -> [TrackpadCommand]? {
        let down = KeyBody(key: key, modifiers: modifiers, phase: "down")
        let up = KeyBody(key: key, modifiers: modifiers, phase: "up")
        do {
            try PayloadValidation.key(down)
            try PayloadValidation.key(up)
        } catch {
            return nil
        }
        return [.key(down), .key(up)]
    }

    private static func ordered(_ names: Set<String>) -> [String] {
        ["command", "option", "control", "shift"].filter { names.contains($0) }
    }

    private static func clip(_ text: String) -> String {
        var result = ""
        var count = 0
        for character in text {
            let extra = String(character).utf8.count
            if count + extra > Limits.maxTextBytes { break }
            result.append(character)
            count += extra
        }
        return result
    }
}
