import GLOTRemoteCore
import SwiftUI

enum RemoteTheme {
    static let canvas = Color(white: 0.11)
    static let card = Color.white.opacity(0.08)
    static let plate = Color.white.opacity(0.10)
    static let well = Color(white: 0.05)
    static let hairline = Color.white.opacity(0.14)
    static let keyFill = Color.white.opacity(0.17)
    static let accent = Color(red: 0, green: 145.0 / 255, blue: 1)
    static let selection = Color(red: 0, green: 145.0 / 255, blue: 1).opacity(0.25)
    static let good = Color(red: 0.45, green: 0.78, blue: 0.55)
    static let warn = Color(red: 0.93, green: 0.72, blue: 0.38)
    static let bad = Color(red: 0.91, green: 0.43, blue: 0.40)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.64)

    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let move = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

enum RemoteButtonKind {
    case regular
    case prominent
}

extension View {
    @ViewBuilder
    func remoteButton(_ kind: RemoteButtonKind = .regular) -> some View {
        if #available(iOS 26, macOS 26, *) {
            switch kind {
            case .regular:
                self.buttonStyle(.glass)
            case .prominent:
                self.buttonStyle(.glassProminent)
            }
        } else {
            switch kind {
            case .regular:
                self.buttonStyle(.bordered)
            case .prominent:
                self.buttonStyle(.borderedProminent)
            }
        }
    }

    func remoteKey(latched: Bool = false, prominent: Bool = false, pressed: Bool = false, capsule: Bool = false) -> some View {
        modifier(RemoteKeySurface(latched: latched, prominent: prominent, pressed: pressed, capsule: capsule))
    }

    func remoteField() -> some View {
        padding(12)
            .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func remoteDock() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    @ViewBuilder
    func remoteBar() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    func remotePlate(radius: CGFloat = 36) -> some View {
        background(RemoteTheme.plate, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .padding(1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.28)
                        )
                    )
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func remoteSelection(active: Bool, id: String, in namespace: Namespace.ID) -> some View {
        background {
            if active {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RemoteTheme.selection)
                    .matchedGeometryEffect(id: id, in: namespace)
            }
        }
    }
}

struct RemotePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: configuration.isPressed)
    }
}

private struct RemoteKeySurface: ViewModifier {
    var latched: Bool
    var prominent: Bool
    var pressed: Bool
    var capsule: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        keyed(content)
            .scaleEffect(!reduceMotion && pressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: pressed)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: latched)
    }

    @ViewBuilder
    private func keyed(_ content: Content) -> some View {
        let labeled = content.foregroundStyle(latched && !prominent ? Color.black : RemoteTheme.text)
        if capsule {
            labeled.background(fill, in: Capsule())
        } else {
            labeled.background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var fill: Color {
        if prominent {
            return RemoteTheme.accent
        }
        if latched {
            return Color.white
        }
        if pressed {
            return Color.white.opacity(0.28)
        }
        return RemoteTheme.keyFill
    }
}

struct RemoteStatusPill: View {
    var state: LinkState
    var note = ""
    var gate: String?
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                StatusDot(tint: LinkPresentation.tint(state))
                Text(LinkPresentation.title(state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RemoteTheme.text)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RemoteTheme.secondary)
                }
            }
            if let gate {
                Text(gate)
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.secondary)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(note.contains("not") || note.contains("Allow Accessibility") || note.contains("rejected") ? RemoteTheme.bad : RemoteTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, note.isEmpty && gate == nil ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .modifier(StatusMaterial(compact: note.isEmpty && gate == nil))
    }
}

private struct StatusMaterial: ViewModifier {
    var compact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if compact {
            content.remoteBar()
        } else {
            content.remoteDock()
        }
    }
}

struct StatusDot: View {
    var tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

struct RemoteCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
