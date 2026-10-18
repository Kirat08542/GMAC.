import GLOTRemoteCore
import SwiftUI

struct AppsScreen: View {
    @Bindable var model: PhoneModel

    var body: some View {
        Group {
            if model.apps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "square.grid.2x2")
                } description: {
                    Text(gateCopy ?? "These are the only apps the Mac will open. Add or remove them on the Mac.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.apps) { app in
                            Button {
                                model.sendRemote([.launch(LaunchBody(bundleID: app.bundleID))])
                            } label: {
                                Label {
                                    Text(app.name)
                                } icon: {
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!model.isReady)
                            .accessibilityLabel("Open \(app.name)")
                        }
                    } footer: {
                        Text("These are the only apps the Mac will open. Add or remove them on the Mac.")
                    }
                }
            }
        }
    }

    private var gateCopy: String? {
        guard !model.isReady else { return nil }
        if case .pairing = model.snapshot.state {
            return "Compare the pairing code on Link."
        }
        return "Open Link to connect."
    }
}
