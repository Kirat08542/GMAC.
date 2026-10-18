import SwiftUI

@main
struct GLOTRemoteApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            PhoneShell(model: model)
        }
    }
}

private enum RemoteMode: String, CaseIterable, Identifiable {
    case pad
    case keys
    case media
    case apps
    case link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pad: "Pad"
        case .keys: "Keys"
        case .media: "Media"
        case .apps: "Apps"
        case .link: "Link"
        }
    }

    var symbol: String {
        switch self {
        case .pad: "hand.draw"
        case .keys: "keyboard"
        case .media: "playpause.fill"
        case .apps: "square.grid.2x2"
        case .link: "desktopcomputer"
        }
    }
}

private struct PhoneShell: View {
    @Bindable var model: PhoneModel
    @State private var mode = RemoteMode.pad
    @Namespace private var modes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            if mode != .link {
                titleRow
            }
            Group {
                switch mode {
                case .pad:
                    TrackpadScreen(model: model)
                case .keys:
                    KeyboardScreen(model: model)
                case .media:
                    MediaScreen(model: model)
                case .apps:
                    AppsScreen(model: model)
                case .link:
                    PhoneHomeView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            modeBar
        }
        .background(RemoteTheme.canvas)
        .tint(RemoteTheme.accent)
        .task { await model.prepare() }
        .onChange(of: isPairing) { _, pairing in
            if pairing {
                mode = .link
            }
        }
    }

    private var titleRow: some View {
        let note = model.snapshot.note
        let bad = note.contains("not") || note.contains("Allow Accessibility") || note.contains("rejected")
        return Button {
            mode = .link
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(mode.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(RemoteTheme.text)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        StatusDot(tint: LinkPresentation.tint(model.snapshot.state))
                        Text(LinkPresentation.title(model.snapshot.state))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RemoteTheme.text)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(bad ? RemoteTheme.bad : RemoteTheme.secondary)
                        .lineLimit(verticalSizeClass == .compact ? 1 : nil)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityHint("Opens Link")
    }

    private var isPairing: Bool {
        if case .pairing = model.snapshot.state {
            return true
        }
        return false
    }

    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(RemoteMode.allCases) { item in
                let selected = mode == item
                Button {
                    mode = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.4)
                    }
                    .foregroundStyle(selected ? RemoteTheme.selectedInk : RemoteTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(RemoteTheme.selectedFill)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .matchedGeometryEffect(id: "mode", in: modes)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(selected ? "Selected" : "")
            }
        }
        .padding(6)
        .remoteBar()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : RemoteTheme.move, value: mode)
    }
}
