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
            VStack(alignment: .leading, spacing: 12) {
                Text("These are the only apps the Mac will open. Add or remove them on the Mac.")
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(model.apps) { app in
                        Button {
                            model.sendRemote([.launch(LaunchBody(bundleID: app.bundleID))])
                        } label: {
                            VStack(spacing: 10) {
                                Text(String(app.name.prefix(1)).uppercased())
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(RemoteTheme.accent)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        RemoteTheme.selection,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
                                    }
                                Text(app.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RemoteTheme.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(minHeight: 36)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
                            }
                        }
                        .buttonStyle(RemotePressStyle())
                        .disabled(!model.isReady)
                        .opacity(model.isReady ? 1 : 0.45)
                        .accessibilityLabel("Open \(app.name)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
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
