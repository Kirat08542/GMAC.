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
    @State private var mode: RemoteMode = .pad

    var body: some View {
        TabView(selection: $mode) {
            ForEach(RemoteMode.allCases) { item in
                tabContent(for: item)
                    .tabItem {
                        Label(item.title, systemImage: item.symbol)
                    }
                    .tag(item)
            }
        }
        .task { await model.prepare() }
        .onChange(of: isPairing) { _, pairing in
            if pairing {
                mode = .link
            }
        }
    }

    @ViewBuilder
    private func tabContent(for item: RemoteMode) -> some View {
        NavigationStack {
            Group {
                switch item {
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
            .navigationTitle(item.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mode = .link
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(LinkPresentation.tint(model.snapshot.state))
                            Text(LinkPresentation.title(model.snapshot.state))
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Connection status. Opens Link.")
                }
            }
        }
    }

    private var isPairing: Bool {
        if case .pairing = model.snapshot.state { return true }
        return false
    }
}
