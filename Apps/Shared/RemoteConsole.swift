import SwiftUI

// Shared console chrome for the Night Console redesign.
// Small, honest building blocks used by the iPhone tabs and the Mac console.

/// Eyebrow section header: tracked-out caption in tertiary ink.
struct ConsoleSectionHeader: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(RemoteTheme.tertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The "not connected" gate note shared by Pad, Keys, Media and Apps.
/// Takes rendered text so Shared stays independent of PhoneModel.
struct GateNote: View {
    var text: String?

    var body: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RemoteTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Faint dot grid used behind gesture surfaces. Decorative only.
struct DotGrid: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            for c in 0..<cols {
                for r in 0..<rows {
                    let rect = CGRect(
                        x: CGFloat(c) * spacing - 1,
                        y: CGFloat(r) * spacing - 1,
                        width: 2,
                        height: 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(RemoteTheme.dot))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A latch key: on/off state rendered with the accent fill when latched.
struct LatchKey: View {
    var title: String
    var symbol: String? = nil
    var latched: Bool
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(minWidth: 64, minHeight: 44)
            .padding(.horizontal, 8)
        }
        .remoteKey(latched: latched)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(latched ? "On" : "Off")
    }
}

/// Round stepper key used for scalar settings like pointer speed.
struct StepperKey: View {
    var symbol: String
    var label: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(RemoteTheme.text)
                .frame(width: 44, height: 44)
                .background(RemoteTheme.keyFill, in: Circle())
                .overlay {
                    Circle().strokeBorder(RemoteTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(RemotePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }
}
