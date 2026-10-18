import GLOTRemoteCore
import SwiftUI

struct MacHomeView: View {
    @Bindable var model: MacModel
    @State private var pendingRevoke: PairedPhone?
    @State private var pendingForget: PairedPhone?
    @Namespace private var phoneSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var headerHeight: CGFloat = 164
    @State private var pairingHeight: CGFloat = 0
    @State private var footerIdeal: CGFloat = 276

    private var isPairing: Bool {
        if case .pairing = model.snapshot.state { return true }
        return false
    }

    var body: some View {
        GeometryReader { proxy in
            let remainder = max(0, proxy.size.height - headerHeight - pairingHeight)
            let split = columnSplit(remainder: remainder, measuredFooter: footerIdeal)
            VStack(spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                if case .pairing(let code, _) = model.snapshot.state {
                    pairingBody(code)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pairingHeight = $0 }
                }
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        appsBody
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
                    }
                    ScrollView {
                        phonesColumn
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
                    }
                }
                .padding(.horizontal, 24)
                .frame(height: split.columns)
                .allowsHitTesting(split.columns > 0)
                .clipped()
                ScrollView {
                    footerContent
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerIdeal = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: split.footer)
                .background(RemoteTheme.card)
            }
        }
        .onChange(of: isPairing) { _, pairing in
            if !pairing { pairingHeight = 0 }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(RemoteTheme.canvas)
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

    private func columnSplit(remainder: CGFloat, measuredFooter: CGFloat) -> (columns: CGFloat, footer: CGFloat) {
        let columnFloor: CGFloat = 64
        if remainder <= columnFloor {
            return (0, max(0, remainder))
        }
        let footerMax = remainder - columnFloor
        if measuredFooter <= footerMax {
            return (remainder - measuredFooter, measuredFooter)
        }
        return (columnFloor, footerMax)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Text(model.deviceName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(RemoteTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 12)
                Toggle(isOn: Binding(
                    get: { model.listening },
                    set: { enabled in Task { await model.setListening(enabled) } }
                )) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Listening")
                            .font(.headline)
                            .foregroundStyle(RemoteTheme.text)
                        Text("Advertises this Mac on the local network as \(Limits.serviceType).")
                            .font(.caption)
                            .foregroundStyle(RemoteTheme.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: 360, alignment: .trailing)
            }
            statusBody
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
                .lineLimit(2)
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
                Button {
                    Task { await model.disconnectRemote() }
                } label: {
                    RemoteActionLabel(title: "Disconnect iPhone", plain: true)
                }
                .remoteButton()
            }
        }
    }

    private func pairingBody(_ code: String) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 12) {
                Button {
                    Task { await model.decide(true) }
                } label: {
                    RemoteActionLabel(title: "Approve", fill: true, prominent: true)
                }
                .remoteButton(.prominent)
                Button {
                    Task { await model.decide(false) }
                } label: {
                    RemoteActionLabel(title: "They differ", fill: true, plain: true)
                }
                .remoteButton()
            }
            .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RemoteTheme.plate)
        .overlay(alignment: .top) { Rectangle().fill(RemoteTheme.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(RemoteTheme.divider).frame(height: 1) }
    }

    private var phonesColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConsoleSectionHeader(title: "Paired iPhones")
            phonesBody
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
                                Button { pendingRevoke = phone } label: {
                                    RemoteActionLabel(title: "Revoke", plain: true)
                                }
                                .remoteButton()
                            }
                            Button { pendingForget = phone } label: {
                                RemoteActionLabel(title: "Forget", plain: true)
                            }
                            .remoteButton()
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(RemoteTheme.divider).frame(height: 1)
                    }
                    .remoteSelection(
                        active: LinkPresentation.peerName(model.snapshot.state) == phone.name,
                        id: "phone",
                        in: phoneSelection
                    )
                }
                .animation(reduceMotion ? nil : RemoteTheme.move, value: LinkPresentation.peerName(model.snapshot.state))
            }
        }
    }

    private var appsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConsoleSectionHeader(title: "Approved apps")
            Text("The iPhone can open only the apps you add here.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.addApplication()
            } label: {
                RemoteActionLabel(title: "Add app", fill: true)
            }
            .remoteButton(addIsPrimary ? .prominent : .regular)
            ForEach(model.approvedApps) { app in
                HStack(spacing: 12) {
                    Image(systemName: "app.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RemoteTheme.text)
                        .frame(width: 36, height: 36)
                        .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
                        }
                    Text(app.name)
                        .font(.headline)
                        .foregroundStyle(RemoteTheme.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await model.removeApplication(app.bundleID) }
                    } label: {
                        RemoteActionLabel(title: "Remove", plain: true)
                    }
                    .remoteButton()
                }
                .frame(minHeight: 64)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(RemoteTheme.divider).frame(height: 1)
                }
            }
        }
    }

    private var addIsPrimary: Bool {
        !isPairing && model.accessibilityTrusted
    }

    private var securityBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.accessibilityTrusted ? "Accessibility is allowed." : "Accessibility is off. Allow it before the pointer can move.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(model.accessibilityTrusted ? RemoteTheme.good : RemoteTheme.warn)
            Text("Accessibility moves the pointer, clicks, scrolling, typing, and the media keys. The iPhone opens only apps you add. Sleep asks for confirmation on the iPhone.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.accessibilityTrusted {
                VStack(spacing: 8) {
                    Button {
                        model.requestAccessibility()
                    } label: {
                        RemoteActionLabel(title: "Request Access", fill: true, prominent: !isPairing)
                    }
                    .remoteButton(isPairing ? .regular : .prominent)
                    Button {
                        model.openAccessibilitySettings()
                    } label: {
                        RemoteActionLabel(title: "Open Accessibility Settings", fill: true, plain: true)
                    }
                    .remoteButton()
                }
            }
        }
    }

    private var footerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 32) {
                securityBody
                VStack(alignment: .leading, spacing: 4) {
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
                .frame(width: 280, alignment: .leading)
            }
            Text("GLOT Remote")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
            Text("Protocol \(Limits.protocolVersion) · One remote at a time · Local network only")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
            Text("Companion for this Mac account. It does not control the login screen.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(RemoteTheme.divider).frame(height: 1)
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
