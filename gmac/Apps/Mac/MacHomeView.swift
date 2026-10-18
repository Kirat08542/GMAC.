import GLOTRemoteCore
import SwiftUI

struct MacHomeView: View {
    @Bindable var model: MacModel
    @State private var pendingRevoke: PairedPhone?
    @State private var pendingForget: PairedPhone?
    @Namespace private var phoneSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusBody
                    if case .pairing(let code, _) = model.snapshot.state {
                        pairingBody(code)
                    }
                    listenerBody
                    securityBody
                    footer
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 340)
            .background(Color.black.opacity(0.28))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    appsBody
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Paired iPhones")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(RemoteTheme.text)
                        phonesBody
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(RemoteTheme.canvas)
        .preferredColorScheme(.dark)
        .tint(RemoteTheme.accent)
        .task { await model.prepare() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GLOT Remote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteTheme.accent)
            Text(model.deviceName)
                .font(.title.weight(.semibold))
                .foregroundStyle(RemoteTheme.text)
            Text("Companion for this Mac account. It does not control the login screen.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusDot(tint: LinkPresentation.tint(model.snapshot.state))
                Text(LinkPresentation.title(model.snapshot.state))
                    .font(.headline)
                    .foregroundStyle(RemoteTheme.text)
                if model.isReady {
                    Text("Remote connected")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RemoteTheme.good.opacity(0.18), in: Capsule())
                        .foregroundStyle(RemoteTheme.good)
                }
            }
            Text(LinkPresentation.detail(model.snapshot.state, note: model.snapshot.note))
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let startupError = model.startupError {
                Text(startupError)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
            if let actionError = model.actionError {
                Text(actionError)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
            if model.isReady {
                Button("Disconnect iPhone") {
                    Task { await model.disconnectRemote() }
                }
                .remoteButton()
                .frame(minHeight: 44)
            }
        }
    }

    private func pairingBody(_ code: String) -> some View {
        VStack(spacing: 12) {
            Text("Approve this iPhone")
                .font(.headline)
                .foregroundStyle(RemoteTheme.text)
            Text(code)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(RemoteTheme.text)
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Pairing code \(code.map { String($0) }.joined(separator: " "))")
            Text("Approve only when the iPhone shows this exact code.")
                .font(.footnote)
                .foregroundStyle(RemoteTheme.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Approve") {
                    Task { await model.decide(true) }
                }
                .remoteButton(.prominent)
                .frame(maxWidth: .infinity, minHeight: 44)
                Button("They differ") {
                    Task { await model.decide(false) }
                }
                .remoteButton()
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RemoteTheme.plate, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var listenerBody: some View {
        Group {
            Toggle(isOn: Binding(
                get: { model.listening },
                set: { enabled in Task { await model.setListening(enabled) } }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening")
                        .font(.headline)
                    Text("Advertises this Mac on the local network as \(Limits.serviceType).")
                        .font(.caption)
                        .foregroundStyle(RemoteTheme.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(16)
            .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var phonesBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.phones.isEmpty {
                Text("None yet. Pairing appears here after both sides accept the code.")
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
            } else {
                ForEach(model.phones) { phone in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(phone.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(RemoteTheme.text)
                            Spacer(minLength: 8)
                            Text(phone.revoked ? "Revoked" : "Allowed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(phone.revoked ? RemoteTheme.bad : RemoteTheme.good)
                        }
                        if let last = phone.lastConnected {
                            Text("Last connection \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(RemoteTheme.secondary)
                        }
                        HStack(spacing: 8) {
                            if !phone.revoked {
                                Button("Revoke") { pendingRevoke = phone }
                                    .remoteButton()
                                    .frame(minHeight: 44)
                            }
                            Button("Forget") { pendingForget = phone }
                                .remoteButton()
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .remoteSelection(
                        active: LinkPresentation.peerName(model.snapshot.state) == phone.name,
                        id: "phone",
                        in: phoneSelection
                    )
                    .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .animation(reduceMotion ? nil : RemoteTheme.move, value: LinkPresentation.peerName(model.snapshot.state))
            }
        }
    }

    private var appsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Approved apps")
                .font(.title2.weight(.semibold))
                .foregroundStyle(RemoteTheme.text)
            Text("The iPhone can open only the apps you add here.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.approvedApps.isEmpty {
                Text("None yet.")
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                Button {
                    model.addApplication()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                        Text("Add app")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 128)
                }
                .remoteButton(.prominent)
                ForEach(model.approvedApps) { app in
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "app.fill")
                            .font(.title3)
                            .foregroundStyle(RemoteTheme.text)
                            .frame(width: 44, height: 44)
                            .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(app.name)
                            .font(.headline)
                            .foregroundStyle(RemoteTheme.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Remove") {
                            Task { await model.removeApplication(app.bundleID) }
                        }
                        .remoteButton()
                        .frame(minHeight: 44)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                    .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private var securityBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.accessibilityTrusted ? "Accessibility is allowed." : "Accessibility is off. Allow it before the pointer can move.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(model.accessibilityTrusted ? RemoteTheme.good : RemoteTheme.warn)
            Text("Accessibility moves the pointer, clicks, scrolling, typing, and the media keys. The iPhone opens only apps you add. Sleep asks for confirmation on the iPhone. Lock, brightness, and the clipboard are not in this version.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.accessibilityTrusted {
                HStack(spacing: 8) {
                    Button("Request Access") {
                        model.requestAccessibility()
                    }
                    .remoteButton(.prominent)
                    .frame(minHeight: 44)
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .remoteButton()
                    .frame(minHeight: 44)
                }
            }
            Toggle(isOn: Binding(
                get: { model.loginStatus == "On" || model.loginStatus == "Needs approval in System Settings" },
                set: { model.setLoginItem($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start at login")
                        .font(.body.weight(.medium))
                    Text(model.loginStatus)
                        .font(.caption)
                        .foregroundStyle(RemoteTheme.secondary)
                }
            }
            .toggleStyle(.switch)
            if let loginError = model.loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        Text("Protocol \(Limits.protocolVersion) · One remote at a time · Local network only")
            .font(.caption)
            .foregroundStyle(RemoteTheme.secondary)
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
