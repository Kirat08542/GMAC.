import GLOTRemoteCore
import SwiftUI

enum LinkPresentation {
    static func title(_ state: LinkState) -> String {
        switch state {
        case .idle:
            "Not connected"
        case .listening:
            "Listening"
        case .connecting:
            "Connecting"
        case .pairing:
            "Compare codes"
        case .authenticating:
            "Authenticating"
        case .ready:
            "Connected"
        case .reconnecting(let attempt):
            "Reconnecting \(attempt)"
        case .failed:
            "Not connected"
        }
    }

    static func detail(_ state: LinkState, note: String) -> String {
        switch state {
        case .idle:
            note.isEmpty ? "Choose a Mac on this Wi-Fi." : note
        case .listening:
            note.isEmpty ? "Waiting for an iPhone on this network." : note
        case .connecting:
            "Establishing an encrypted session."
        case .pairing(_, let expires):
            "The same six digits must appear on both screens. Expires \(expires.formatted(date: .omitted, time: .shortened))."
        case .authenticating:
            "Checking the saved device identity."
        case .ready(let name):
            note.isEmpty ? "Session with \(name)." : note
        case .reconnecting(let attempt):
            "The network dropped. Trying again, attempt \(attempt)."
        case .failed(let message):
            message
        }
    }

    static func peerName(_ state: LinkState) -> String? {
        if case .ready(let name) = state {
            return name
        }
        return nil
    }

    static func tint(_ state: LinkState) -> Color {
        switch state {
        case .ready:
            RemoteTheme.good
        case .listening, .connecting, .pairing, .authenticating, .reconnecting:
            RemoteTheme.warn
        case .failed:
            RemoteTheme.bad
        case .idle:
            RemoteTheme.secondary
        }
    }
}
