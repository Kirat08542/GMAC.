import GLOTRemoteCore
import SwiftUI

struct AppsScreen: View {
    @Bindable var model: PhoneModel

    var body: some View {
        Group {
            if model.apps.isEmpty {
                empty
            } else {
                grid
            }
        }
        .background(RemoteTheme.canvas)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(RemoteTheme.secondary)
            if let gate = gateCopy {
                Text(gate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RemoteTheme.text)
            }
            Text(model.isReady
                 ? "None yet. On the Mac, add the apps this iPhone may open."
                 : "These are the only apps the Mac will open. Add or remove them on the Mac.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("These are the only apps the Mac will open. Add or remove them on the Mac.")
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 22) {
                    ForEach(model.apps) { app in
                        Button {
                            model.sendRemote([.launch(LaunchBody(bundleID: app.bundleID))])
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(RemoteTheme.text)
                                    .frame(width: 84, height: 84)
                                    .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                Text(app.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RemoteTheme.text)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 148)
                        }
                        .buttonStyle(RemotePressStyle())
                        .disabled(!model.isReady)
                        .opacity(model.isReady ? 1 : 0.45)
                        .accessibilityLabel("Open \(app.name)")
                    }
                }
            }
            .padding(20)
        }
        .background(RemoteTheme.canvas)
    }

    private var gateCopy: String? {
        guard !model.isReady else { return nil }
        if case .pairing = model.snapshot.state {
            return "Compare the pairing code on Link."
        }
        return "Open Link to connect."
    }
}
