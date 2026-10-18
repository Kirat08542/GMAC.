import GLOTRemoteCore
import SwiftUI

struct PhoneHomeView: View {
    @Bindable var model: PhoneModel
    @State private var nameDraft = ""
    @State private var pendingForget: PairedMac?
    @State private var pendingSleep = false
    @Namespace private var macSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if case .pairing(let code, _) = model.snapshot.state {
                    pairingBody(code)
                }
                section("Name on the Mac") { nameBody }
                section("Macs on this network") { discoveryBody }
                if model.isReady {
                    section("Session") {
                        testBody
                        sleepBody
                    }
                }
                section("Saved Macs") { savedBody }
                footer
            }
            .padding(20)
        }
        .background(RemoteTheme.canvas)
        .preferredColorScheme(.dark)
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
            Button("Sleep Mac") {
                pendingSleep = true
            }
            .remoteButton()
            .frame(minHeight: 44)
            .disabled(!model.isReady)
            .accessibilityLabel("Sleep the Mac")
            if model.snapshot.note.contains("could not sleep") {
                Text(model.snapshot.note)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
        }
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusDot(tint: LinkPresentation.tint(model.snapshot.state))
                    .padding(.bottom, 6)
                Text(LinkPresentation.title(model.snapshot.state))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(RemoteTheme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Text(detail)
                .font(.body)
                .foregroundStyle(RemoteTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Local Wi-Fi only. No account and no internet relay.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
            if model.isReady || isActive {
                Button("Disconnect") {
                    Task { await model.disconnect() }
                }
                .remoteButton()
                .frame(minHeight: 44)
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
                Button("Try again") {
                    Task { await model.prepare() }
                }
                .remoteButton()
                .frame(minHeight: 44)
            }
            if let actionError = model.actionError {
                Text(actionError)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.bad)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteTheme.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func pairingBody(_ code: String) -> some View {
        VStack(spacing: 14) {
            Text("Pairing code")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RemoteTheme.secondary)
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
                Button("Codes match") {
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
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RemoteTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                Text("Save name")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(RemoteTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
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
                Text("None yet. On the Mac, turn Listening on.")
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
            } else if !model.macs.isEmpty {
                ForEach(model.macs) { mac in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mac.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(RemoteTheme.text)
                            if !mac.fingerprint.isEmpty {
                                Text("Key \(mac.fingerprint)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(RemoteTheme.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(model.busy ? "Connecting" : "Connect") {
                            Task { await model.connect(mac) }
                        }
                        .remoteButton(.prominent)
                        .frame(minHeight: 44)
                        .disabled(model.busy || model.startupError != nil)
                    }
                    .padding(8)
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
            Button("Send test") {
                Task { await model.sendTest() }
            }
            .remoteButton(.prominent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(model.busy)
            if !model.testNote.isEmpty {
                Text(model.testNote)
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.text)
            }
        }
    }

    private var savedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.paired.isEmpty {
                Text("A Mac is saved here after you both accept the pairing code.")
                    .font(.subheadline)
                    .foregroundStyle(RemoteTheme.secondary)
            } else {
                ForEach(model.paired) { mac in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mac.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(RemoteTheme.text)
                            if let last = mac.lastConnected {
                                Text("Last connection \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(RemoteTheme.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Forget") { pendingForget = mac }
                            .remoteButton()
                            .frame(minHeight: 44)
                    }
                    .padding(8)
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
        Text("Protocol \(Limits.protocolVersion) · \(Limits.serviceType)")
            .font(.caption)
            .foregroundStyle(RemoteTheme.secondary)
    }
}
