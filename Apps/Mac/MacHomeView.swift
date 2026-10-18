import GLOTRemoteCore
import SwiftUI

private enum MacSection: String, CaseIterable, Identifiable {
    case overview
    case apps
    case phones
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .apps: "Approved Apps"
        case .phones: "Paired iPhones"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "info.circle"
        case .apps: "app.badge"
        case .phones: "iphone"
        case .settings: "gear"
        }
    }
}

struct MacHomeView: View {
    @Bindable var model: MacModel
    @State private var selection: MacSection? = .overview
    @State private var pendingRevoke: PairedPhone?
    @State private var pendingForget: PairedPhone?

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(badge(for: section))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 232)
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .overview {
                    case .overview:
                        overviewDetail
                    case .apps:
                        appsDetail
                    case .phones:
                        phonesDetail
                    case .settings:
                        settingsDetail
                    }
                }
                .navigationTitle((selection ?? .overview).title)
                .safeAreaInset(edge: .top) {
                    if case .pairing(let code, _) = model.snapshot.state {
                        pairingBanner(code)
                    }
                }
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .task { await model.prepare() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Listening", isOn: Binding(
                    get: { model.listening },
                    set: { enabled in Task { await model.setListening(enabled) } }
                ))
                .toggleStyle(.switch)
                .help("Advertises this Mac on the local network as \(Limits.serviceType).")
            }
        }
        .confirmationDialog(
            "Revoke this iPhone?",
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let pendingRevoke {
                    Task { await model.revoke(pendingRevoke.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The iPhone is disconnected and cannot pair again until you forget it.")
        }
        .confirmationDialog(
            "Forget this iPhone?",
            isPresented: Binding(get: { pendingForget != nil }, set: { if !$0 { pendingForget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) {
                if let pendingForget {
                    Task { await model.forget(pendingForget.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved key is deleted. That iPhone can request pairing again.")
        }
    }

    private func badge(for section: MacSection) -> Int? {
        switch section {
        case .apps:
            model.approvedApps.isEmpty ? nil : model.approvedApps.count
        case .phones:
            model.phones.isEmpty ? nil : model.phones.count
        case .overview, .settings:
            nil
        }
    }

    private var overviewDetail: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.title2)
                        .foregroundStyle(LinkPresentation.tint(model.snapshot.state))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LinkPresentation.title(model.snapshot.state))
                            .font(.headline)
                        Text(LinkPresentation.detail(model.snapshot.state, note: model.snapshot.note))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                if model.isReady {
                    Label("Remote connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Disconnect iPhone", role: .destructive) {
                        Task { await model.disconnectRemote() }
                    }
                }
                if let startupError = model.startupError {
                    Text(startupError)
                        .foregroundStyle(.red)
                }
                if let actionError = model.actionError {
                    Text(actionError)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(model.deviceName)
            } footer: {
                Text("Local network only. One remote at a time.")
            }
        }
    }

    private func pairingBanner(_ code: String) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(code)
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Pairing code \(code.map { String($0) }.joined(separator: " "))")
                Text("Approve only when the iPhone shows this exact code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("They differ") {
                Task { await model.decide(false) }
            }
            .buttonStyle(.bordered)
            Button("Approve") {
                Task { await model.decide(true) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var appsDetail: some View {
        List {
            Section {
                ForEach(model.approvedApps) { app in
                    HStack {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(systemName: "app.fill")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            Task { await model.removeApplication(app.bundleID) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("The iPhone can open only the apps you add here.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Add app") {
                    model.addApplication()
                }
                .buttonStyle(addIsPrimary ? .borderedProminent : .bordered)
                Spacer()
            }
            .padding()
            .background(.bar)
        }
    }

    private var addIsPrimary: Bool {
        if case .pairing = model.snapshot.state { return false }
        return model.accessibilityTrusted
    }

    private var phonesDetail: some View {
        List {
            if model.phones.isEmpty {
                ContentUnavailableView(
                    "No paired iPhones",
                    systemImage: "iphone",
                    description: Text("Pairing appears here after both sides accept the code.")
                )
            } else {
                ForEach(model.phones) { phone in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(phone.name)
                                .font(.headline)
                            Spacer()
                            Text(phone.revoked ? "Revoked" : "Allowed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(phone.revoked ? .red : .green)
                        }
                        if let last = phone.lastConnected {
                            Text("Last connection \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            if !phone.revoked {
                                Button("Revoke") { pendingRevoke = phone }
                                    .buttonStyle(.bordered)
                            }
                            Button("Forget", role: .destructive) { pendingForget = phone }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var settingsDetail: some View {
        Form {
            Section("Accessibility") {
                Label(
                    model.accessibilityTrusted ? "Accessibility is allowed." : "Accessibility is off. Allow it before the pointer can move.",
                    systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                if !model.accessibilityTrusted {
                    Button("Request Access") {
                        model.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                }
            } footer: {
                Text("Accessibility moves the pointer, clicks, scrolling, typing, and the media keys. The iPhone opens only apps you add. Sleep asks for confirmation on the iPhone.")
            }
            Section("General") {
                Toggle("Start at login", isOn: Binding(
                    get: { model.loginStatus == "On" || model.loginStatus == "Needs approval in System Settings" },
                    set: { model.setLoginItem($0) }
                ))
                if model.loginStatus != "On" {
                    Text(model.loginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loginError = model.loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Text("GLOT Remote")
                Text("Protocol \(Limits.protocolVersion) · \(Limits.serviceType)")
                Text("Companion for this Mac account. It does not control the login screen.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct MacMenuView: View {
    var model: MacModel

    var body: some View {
        Text(model.isReady ? "iPhone connected" : LinkPresentation.title(model.snapshot.state))
        Text(model.deviceName)
        Divider()
        Button(model.listening ? "Stop listening" : "Start listening") {
            Task { await model.setListening(!model.listening) }
        }
        if model.isReady {
            Button("Disconnect iPhone") {
                Task { await model.disconnectRemote() }
            }
        }
    }
}
