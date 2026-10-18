import GLOTRemoteCore
import SwiftUI

struct PhoneHomeView: View {
    @Bindable var model: PhoneModel
    @State private var nameDraft = ""
    @State private var pendingForget: PairedMac?
    @State private var pendingSleep = false

    var body: some View {
        Form {
            statusSection
            if case .pairing(let code, _) = model.snapshot.state {
                pairingSection(code)
            }
            if model.isReady {
                sessionSection
            }
            discoverySection
            nameSection
            savedSection
            Section {
                Text("Protocol \(Limits.protocolVersion) · \(Limits.serviceType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private var statusSection: some View {
        Section("Status") {
            let detail = LinkPresentation.detail(model.snapshot.state, note: model.snapshot.note)
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.title2)
                    .foregroundStyle(LinkPresentation.tint(model.snapshot.state))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LinkPresentation.title(model.snapshot.state))
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            Text("Local Wi-Fi only. No account and no internet relay.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.isReady || isActive {
                Button("Disconnect", role: .destructive) {
                    Task { await model.disconnect() }
                }
            }
            if !model.snapshot.note.isEmpty, !detail.contains(model.snapshot.note) {
                Text(model.snapshot.note)
                    .font(.subheadline)
                    .foregroundStyle(isBadNote(model.snapshot.note) ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let startupError = model.startupError {
                Text(startupError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Try again") {
                    Task { await model.prepare() }
                }
            }
            if let actionError = model.actionError {
                Text(actionError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func pairingSection(_ code: String) -> some View {
        Section("Pairing") {
            VStack(spacing: 12) {
                Text(code)
                    .font(.system(size: 56, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Pairing code \(code.map { String($0) }.joined(separator: " "))")
                Text("The same six digits must appear on the Mac. The code is not typed or sent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Codes match") {
                        Task { await model.decide(true) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("They differ") {
                        Task { await model.decide(false) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            Button("Send test") {
                Task { await model.sendTest() }
            }
            .disabled(model.busy)
            if !model.testNote.isEmpty {
                Text(model.testNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Send clipboard to Mac") {
                model.pushClipboard()
            }
            .disabled(!model.isReady)
            Button("Fetch Mac clipboard") {
                model.pullClipboard()
            }
            .disabled(!model.isReady)
            if !model.clipboardNote.isEmpty {
                Text(model.clipboardNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Sleep Mac") {
                pendingSleep = true
            }
            .disabled(!model.isReady)
            if model.snapshot.note.contains("could not sleep") {
                Text(model.snapshot.note)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Sends one authenticated message. The Mac answers with an acknowledgement. Clipboard moves text only, one tap per transfer — nothing syncs on its own.")
        }
    }

    private var discoverySection: some View {
        Section("Macs on this network") {
            if !model.discoveryNote.isEmpty {
                Text(model.discoveryNote)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.macs.isEmpty && model.discoveryNote.isEmpty {
                ContentUnavailableView(
                    "No Macs found",
                    systemImage: "wifi",
                    description: Text("On the Mac, turn Listening on.")
                )
            } else {
                ForEach(model.macs) { mac in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name)
                                .font(.headline)
                            if !mac.fingerprint.isEmpty {
                                Text("Key \(mac.fingerprint)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(model.busy ? "Connecting" : "Connect") {
                            Task { await model.connect(mac) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.busy || model.startupError != nil)
                    }
                }
            }
        }
    }

    private var nameSection: some View {
        Section("Name on the Mac") {
            TextField("iPhone", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await model.updateName(nameDraft) } }
            Button("Save name") {
                Task { await model.updateName(nameDraft) }
            }
        }
    }

    private var savedSection: some View {
        Section("Saved Macs") {
            if !model.wakeNote.isEmpty {
                Text(model.wakeNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.paired.isEmpty {
                Text("A Mac is saved here after you both accept the pairing code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.paired) { mac in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name)
                                .font(.headline)
                            if let last = mac.lastConnected {
                                Text("Last connection \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if mac.wakeMAC != nil {
                            Button("Wake") {
                                model.wake(mac)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Wake \(mac.name)")
                        }
                        Button("Forget", role: .destructive) {
                            pendingForget = mac
                        }
                        .buttonStyle(.bordered)
                    }
                }
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

    private func isBadNote(_ note: String) -> Bool {
        note.contains("not") || note.contains("Allow Accessibility") || note.contains("rejected")
    }
}
