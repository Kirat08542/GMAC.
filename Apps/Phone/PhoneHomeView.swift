import GLOTRemoteCore
import SwiftUI

// Link — Night Console redesign. Connection hub as a console dashboard:
// status card with connected glow, pairing plate, and carded sections.
// All pairing, discovery and session logic is unchanged.
struct PhoneHomeView: View {
    @Bindable var model: PhoneModel
    @State private var nameDraft = ""
    @State private var pendingForget: PairedMac?
    @State private var pendingSleep = false
    @Namespace private var macSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if case .pairing(let code, _) = model.snapshot.state {
                    pairingBody(code)
                }
                if model.isReady {
                    section("Session") {
                        testBody
                        Divider().background(RemoteTheme.divider)
                        clipboardBody
                        Divider().background(RemoteTheme.divider)
                        sleepBody
                    }
                }
                section("Macs on this network") { discoveryBody }
                section("Name on the Mac") { nameBody }
                section("Saved Macs") { savedBody }
                footer
            }
            .padding(16)
        }
        .background(RemoteTheme.canvas)
        .tint(RemoteTheme.accent)
        .task {
            await model.prepare()
            if nameDraft.isEmpty {
                nameDraft = model.displayName
            }
        }
        .confirmationDialog(
            "Forget this Mac?",
            isPresented: Binding(
                get: { pendingForget != nil },
                set: { if !$0 { pendingForget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) {
                if let pendingForget {
                    Task { await model.forget(pendingForget.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The iPhone deletes its saved key for this Mac. Pairing is required again.")
        }
        .confirmationDialog(
            "Sleep this Mac?",
            isPresented: $pendingSleep,
            titleVisibility: .visible
        ) {
            Button("Sleep", role: .destructive) {
                model.sendRemote([.system(SystemBody(action: "sleep", confirmed: true))])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Mac display turns off and the computer sleeps.")
        }
    }

    private var sleepBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirm here before the Mac sleeps.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
            Button {
                pendingSleep = true
            } label: {
                RemoteActionLabel(title: "Sleep Mac", fill: true, plain: true)
            }
            .remoteButton()
            .disabled(!model.isReady)
            .accessibilityLabel("Sleep the Mac")
            if model.snapshot.note.contains("could not sleep") {
                Text(model.snapshot.note)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
        }
    }

    private var isPairing: Bool {
        if case .pairing = model.snapshot.state { return true }
        return false
    }

    private var connectIsProminent: Bool {
        !isPairing && !model.isReady
    }

    private var isActive: Bool {
        switch model.snapshot.state {
        case .connecting, .pairing, .authenticating, .ready, .reconnecting:
            true
        default:
            false
        }
    }

    private var hero: some View {
        let detail = LinkPresentation.detail(model.snapshot.state, note: model.snapshot.note)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                StatusDot(tint: LinkPresentation.tint(model.snapshot.state))
                Text(LinkPresentation.title(model.snapshot.state))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(RemoteTheme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if model.isReady {
                    Text("SECURE")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(RemoteTheme.good)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RemoteTheme.good.opacity(0.14), in: Capsule())
                        .accessibilityLabel("Secure connection")
                }
            }
            Text(detail)
                .font(.body)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Local Wi-Fi only. No account and no internet relay.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.tertiary)
            if model.isReady || isActive {
                Button {
                    Task { await model.disconnect() }
                } label: {
                    RemoteActionLabel(title: "Disconnect", fill: true, plain: true)
                }
                .remoteButton()
                .accessibilityLabel("Disconnect from the Mac")
            }
            if !model.snapshot.note.isEmpty, !detail.contains(model.snapshot.note) {
                Text(model.snapshot.note)
                    .font(.subheadline)
                    .foregroundStyle(model.snapshot.note.contains("not") || model.snapshot.note.contains("Allow Accessibility") || model.snapshot.note.contains("rejected") ? RemoteTheme.bad : RemoteTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let startupError = model.startupError {
                Text(startupError)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
                Button {
                    Task { await model.prepare() }
                } label: {
                    RemoteActionLabel(title: "Try again", fill: true, plain: true)
                }
                .remoteButton()
            }
            if let actionError = model.actionError {
                Text(actionError)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(RemoteTheme.hairline, lineWidth: 1)
        }
        .overlay {
            if model.isReady {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(RemoteTheme.accent.opacity(0.4), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ConsoleSectionHeader(title: title)
                .padding(.horizontal, 4)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(RemoteTheme.cardEdge, lineWidth: 1)
        }
    }

    private func pairingBody(_ code: String) -> some View {
        VStack(spacing: 14) {
            ConsoleSectionHeader(title: "Pairing code")
            Text(code)
                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                .foregroundStyle(RemoteTheme.text)
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Pairing code \(code.map { String($0) }.joined(separator: " "))")
            Text("Read both screens. The code is not typed or sent.")
                .font(.footnote)
                .foregroundStyle(RemoteTheme.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    Task { await model.decide(true) }
                } label: {
                    RemoteActionLabel(title: "Codes match", fill: true, prominent: true)
                }
                .remoteButton(.prominent)
                Button {
                    Task { await model.decide(false) }
                } label: {
                    RemoteActionLabel(title: "They differ", fill: true, plain: true)
                }
                .remoteButton()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RemoteTheme.plate, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(RemoteTheme.accent.opacity(0.35), lineWidth: 1.5)
        }
    }

    private var nameBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("iPhone", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(RemoteTheme.text)
                .remoteField()
                .accessibilityLabel("Name shown on the Mac")
                .onSubmit { Task { await model.updateName(nameDraft) } }
            Button {
                Task { await model.updateName(nameDraft) }
            } label: {
                RemoteActionLabel(title: "Save name", fill: true, plain: true)
            }
            .remoteButton()
        }
    }

    private var discoveryBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.discoveryNote.isEmpty {
                Text(model.discoveryNote)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.macs.isEmpty && model.discoveryNote.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wifi")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(RemoteTheme.tertiary)
                    Text("None yet. On the Mac, turn Listening on.")
                        .font(.subheadline)
                        .foregroundStyle(RemoteTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if !model.macs.isEmpty {
                ForEach(model.macs) { mac in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(RemoteTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(RemoteTheme.selection, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mac.name)
                                .font(.headline)
                                .foregroundStyle(RemoteTheme.text)
                            if !mac.fingerprint.isEmpty {
                                Text("Key \(mac.fingerprint)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(RemoteTheme.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Task { await model.connect(mac) }
                        } label: {
                            RemoteActionLabel(
                                title: model.busy ? "Connecting" : "Connect",
                                prominent: connectIsProminent
                            )
                        }
                        .remoteButton(connectIsProminent ? .prominent : .regular)
                        .disabled(model.busy || model.startupError != nil)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(RemoteTheme.divider).frame(height: 1)
                    }
                    .remoteSelection(
                        active: LinkPresentation.peerName(model.snapshot.state) == mac.name,
                        id: "discovered",
                        in: macSelection
                    )
                }
                .animation(reduceMotion ? nil : RemoteTheme.move, value: LinkPresentation.peerName(model.snapshot.state))
            }
        }
    }

    private var testBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sends one authenticated message. The Mac answers with an acknowledgement.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
            Button {
                Task { await model.sendTest() }
            } label: {
                RemoteActionLabel(title: "Send test", fill: true, prominent: !isPairing)
            }
            .remoteButton(isPairing ? .regular : .prominent)
            .disabled(model.busy)
            if !model.testNote.isEmpty {
                Text(model.testNote)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.text)
            }
        }
    }

    private var clipboardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move text between clipboards. Each transfer needs a tap — nothing syncs on its own.")
                .font(.subheadline)
                .foregroundStyle(RemoteTheme.secondary)
            HStack(spacing: 12) {
                Button {
                    model.pushClipboard()
                } label: {
                    RemoteActionLabel(title: "Send to Mac", fill: true, plain: true)
                }
                .remoteButton()
                .disabled(!model.isReady)
                Button {
                    model.pullClipboard()
                } label: {
                    RemoteActionLabel(title: "Fetch from Mac", fill: true, plain: true)
                }
                .remoteButton()
                .disabled(!model.isReady)
            }
            if !model.clipboardNote.isEmpty {
                Text(model.clipboardNote)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard sharing")
    }

    private var savedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.wakeNote.isEmpty {
                Text(model.wakeNote)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.paired.isEmpty {
                Text("A Mac is saved here after you both accept the pairing code.")
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
            } else {
                ForEach(model.paired) { mac in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(RemoteTheme.secondary)
                            .frame(width: 44, height: 44)
                            .background(RemoteTheme.keyFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mac.name)
                                .font(.headline)
                                .foregroundStyle(RemoteTheme.text)
                            if let last = mac.lastConnected {
                                Text("Last connection \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(RemoteTheme.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if mac.wakeMAC != nil {
                            Button {
                                model.wake(mac)
                            } label: {
                                RemoteActionLabel(title: "Wake", plain: true)
                            }
                            .remoteButton()
                            .accessibilityLabel("Wake \(mac.name)")
                        }
                        Button { pendingForget = mac } label: {
                            RemoteActionLabel(title: "Forget", plain: true)
                        }
                        .remoteButton()
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(RemoteTheme.divider).frame(height: 1)
                    }
                    .remoteSelection(
                        active: LinkPresentation.peerName(model.snapshot.state) == mac.name,
                        id: "saved",
                        in: macSelection
                    )
                }
                .animation(reduceMotion ? nil : RemoteTheme.move, value: LinkPresentation.peerName(model.snapshot.state))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GLOT Remote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteTheme.secondary)
            Text("Protocol \(Limits.protocolVersion) · \(Limits.serviceType)")
                .font(.caption)
                .foregroundStyle(RemoteTheme.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
