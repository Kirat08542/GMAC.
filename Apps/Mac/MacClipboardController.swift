import AppKit
import GLOTRemoteCore

/// Moves text through the Mac general pasteboard. Sandboxed apps may use the
/// general pasteboard. Text only, 16 KB limit, user-initiated from the iPhone.
final class MacClipboardController: RemoteClipboard, @unchecked Sendable {
    func push(_ body: ClipboardBody) throws {
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(body.text, forType: .string) else {
            throw RemoteError.invalid("The Mac clipboard rejected the text.")
        }
    }

    func pull() throws -> ClipboardBody {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteError.invalid("The Mac clipboard is empty.")
        }
        let body = ClipboardBody(text: text)
        try PayloadValidation.clipboard(body)
        return body
    }
}
