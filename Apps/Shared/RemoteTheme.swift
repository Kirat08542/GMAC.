import GLOTRemoteCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Night Console — dark-first redesign of the GLOT Remote design system.
// Decisions and their sources live in CHANGELOG.md ("Source of every decision").
// The component API is unchanged from the previous theme so existing screens
// compile against it; only the visual treatment is new.
enum RemoteTheme {
    // Surfaces — dark-first ramps
    static let canvas = adaptive((0.945, 0.945, 0.960, 1), (0.030, 0.030, 0.045, 1))
    static let card = adaptive((1, 1, 1, 1), (1, 1, 1, 0.055))
    static let plate = adaptive((1, 1, 1, 1), (1, 1, 1, 0.080))
    static let well = adaptive((0.870, 0.870, 0.890, 1), (0, 0, 0, 0.38))
    static let hairline = adaptive((0, 0, 0, 0.08), (1, 1, 1, 0.12))
    static let keyFill = adaptive((1, 1, 1, 1), (1, 1, 1, 0.105))
    static let field = adaptive((0.920, 0.920, 0.935, 1), (1, 1, 1, 0.105))

    // One calm accent; status colours are reserved for status
    static let accent = adaptive((0.050, 0.420, 0.980, 1), (0.220, 0.530, 1.000, 1))
    static let accentDeep = adaptive((0.030, 0.300, 0.800, 1), (0.120, 0.380, 0.920, 1))
    static let selection = adaptive((0.050, 0.420, 0.980, 0.14), (0.220, 0.530, 1.000, 0.26))
    static let glow = adaptive((0.050, 0.420, 0.980, 0.10), (0.220, 0.530, 1.000, 0.16))

    // Status only
    static let good = adaptive((0.150, 0.550, 0.320, 1), (0.350, 0.800, 0.500, 1))
    static let warn = adaptive((0.700, 0.460, 0.050, 1), (0.950, 0.700, 0.300, 1))
    static let bad = adaptive((0.780, 0.220, 0.200, 1), (0.950, 0.450, 0.400, 1))

    // Ink
    static let text = adaptive((0.050, 0.050, 0.060, 1), (0.965, 0.965, 0.975, 1))
    static let secondary = adaptive((0.050, 0.050, 0.060, 0.58), (0.965, 0.965, 0.975, 0.62))
    static let tertiary = adaptive((0.050, 0.050, 0.060, 0.38), (0.965, 0.965, 0.975, 0.40))
    static let onAccent = Color.white

    // Key states
    static let latchedFill = adaptive((0.050, 0.420, 0.980, 1), (0.220, 0.530, 1.000, 1))
    static let latchedInk = Color.white
    static let pressedFill = adaptive((0, 0, 0, 0.08), (1, 1, 1, 0.22))
    static let highlight = adaptive((1, 1, 1, 0.9), (1, 1, 1, 0.16))
    static let selectedFill = adaptive((0.050, 0.420, 0.980, 1), (0.220, 0.530, 1.000, 1))
    static let selectedInk = Color.white

    // Structure
    static let rail = adaptive((0.900, 0.900, 0.915, 1), (0, 0, 0, 0.30))
    static let divider = adaptive((0, 0, 0, 0.07), (1, 1, 1, 0.09))
    static let dot = adaptive((0, 0, 0, 0.05), (1, 1, 1, 0.055))
    static let cardEdge = adaptive((0, 0, 0, 0.06), (1, 1, 1, 0.06))
    static let lift = adaptive((0.05, 0.05, 0.08, 0.08), (0, 0, 0, 0.45))

    // Motion — one shared pair of springs (MicroKit)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let move = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

enum RemoteButtonKind {
    case regular
    case prominent
}

extension View {
    /// Buttons are solid fills. Glass is reserved for floating chrome
    /// (the mode bar via `remoteBar()`), per the Liquid Glass rules.
    func remoteButton(_ kind: RemoteButtonKind = .regular) -> some View {
        switch kind {
        case .regular:
            self.buttonStyle(RemoteSubtleButtonStyle())
        case .prominent:
            self.buttonStyle(RemoteAccentButtonStyle())
        }
    }

    func remoteKey(latched: Bool = false, prominent: Bool = false, pressed: Bool = false, capsule: Bool = false) -> some View {
        modifier(RemoteKeySurface(latched: latched, prominent: prominent, pressed: pressed, capsule: capsule))
    }

    func remoteField() -> some View {
        padding(12)
            .background(RemoteTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
            }
    }

    /// Floating chrome only — the mode bar. Glass on iOS 26+, material fallback.
    @ViewBuilder
    func remoteBar() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Floating chrome only — sheets and floating docks.
    @ViewBuilder
    func remoteDock() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                    .stroke(RemoteTheme.highlight, lineWidth: 1)
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
            .shadow(color: RemoteTheme.lift, radius: 18, y: 8)
    }

    func remoteCard(radius: CGFloat = 22) -> some View {
        background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
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

/// Press state shared by tappable rows and icon buttons (MicroKit: ~0.97 scale).
struct RemotePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: configuration.isPressed)
    }
}

/// Quiet button: solid key fill, hairline edge, 44pt-friendly.
struct RemoteSubtleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: configuration.isPressed)
    }
}

/// Primary button: solid accent. The only place accent fills a control.
struct RemoteAccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: [RemoteTheme.accent, RemoteTheme.accentDeep],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
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
            .scaleEffect(!reduceMotion && pressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: pressed)
            .animation(reduceMotion ? nil : RemoteTheme.press, value: latched)
    }

    @ViewBuilder
    private func keyed(_ content: Content) -> some View {
        let labeled = content.foregroundStyle(ink)
        if capsule {
            labeled.background(fill, in: Capsule())
        } else {
            labeled.background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var ink: Color {
        if prominent {
            return RemoteTheme.onAccent
        }
        if latched {
            return RemoteTheme.latchedInk
        }
        return RemoteTheme.text
    }

    private var fill: Color {
        if prominent {
            return RemoteTheme.accent
        }
        if latched {
            return RemoteTheme.latchedFill
        }
        if pressed {
            return RemoteTheme.pressedFill
        }
        return RemoteTheme.keyFill
    }
}

private func adaptive(_ light: (CGFloat, CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
    #if os(iOS)
    Color(uiColor: UIColor { traits in
        let channel = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: channel.0, green: channel.1, blue: channel.2, alpha: channel.3)
    })
    #elseif os(macOS)
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let channel = darkMode ? dark : light
        return NSColor(srgbRed: channel.0, green: channel.1, blue: channel.2, alpha: channel.3)
    }))
    #else
    Color(red: dark.0, green: dark.1, blue: dark.2, opacity: dark.3)
    #endif
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
        .remoteCard()
    }
}

struct RemoteActionLabel: View {
    var title: String
    var fill = false
    var plain = false
    /// Set when the label sits on the accent button style.
    var prominent = false

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, fill ? 0 : 14)
    }

    private var foreground: AnyShapeStyle {
        if prominent {
            return AnyShapeStyle(RemoteTheme.onAccent)
        }
        if plain {
            return AnyShapeStyle(RemoteTheme.text)
        }
        return AnyShapeStyle(.primary)
    }
}
