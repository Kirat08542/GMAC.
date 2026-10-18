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

    var body: some View {
        VStack(spacing: 0) {
            if mode != .link {
                RemoteStatusPill(state: model.snapshot.state, note: model.snapshot.note, showsDisclosure: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .onTapGesture { mode = .link }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens Link")
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
            modeBar
        }
        .background(RemoteTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(RemoteTheme.accent)
        .task { await model.prepare() }
        .onChange(of: isPairing) { _, pairing in
            if pairing {
                mode = .link
            }
        }
    }

    private var isPairing: Bool {
        if case .pairing = model.snapshot.state {
            return true
        }
        return false
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(RemoteMode.allCases) { item in
                let selected = mode == item
                Button {
                    mode = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                        if selected {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(selected ? Color.black : RemoteTheme.secondary)
                    .padding(.horizontal, selected ? 12 : 0)
                    .frame(maxWidth: selected ? .infinity : 44, minHeight: 44)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.white)
                                .matchedGeometryEffect(id: "mode", in: modes)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .remoteBar()
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : RemoteTheme.move, value: mode)
    }
}
