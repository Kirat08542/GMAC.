import GLOTRemoteCore
import SwiftUI

struct KeyboardScreen: View {
    @Bindable var model: PhoneModel
    @State private var draft = ""
    @State private var latched: Set<String> = []
    @State private var skipNextEdit = false

    var body: some View {
        VStack(spacing: 12) {
            field
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if let gate = gateCopy {
                Text(gate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RemoteTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            Text("Highlight a shortcut key, then type a letter. Password fields on the Mac reject these keys.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                modifierRow
                keyGrid
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 40, style: .continuous)
                    .fill(RemoteTheme.well)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 40, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            .mask(
                                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
                            )
                    }
            }
            .padding(.horizontal, 8)
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

    private var field: some View {
        TextField("Type into the Mac", text: $draft)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.return)
            .font(.body)
            .foregroundStyle(RemoteTheme.text)
            .remoteField()
            .disabled(!model.isReady)
            .onSubmit {
                sendChord("return")
            }
            .onChange(of: draft) { old, new in
                if skipNextEdit {
                    skipNextEdit = false
                    return
                }
                if !latched.isEmpty, new.hasPrefix(old), new.count == old.count + 1 {
                    let added = String(new.dropFirst(old.count))
                    if let commands = KeyboardTyping.shortcut(added, modifiers: latched) {
                        latched = []
                        skipNextEdit = true
                        draft = old
                        model.sendRemote(commands)
                        return
                    }
                }
                model.sendRemote(KeyboardTyping.commands(replacing: old, with: new))
            }
    }

    private var modifierRow: some View {
        HStack(spacing: 8) {
            modifier("command", title: "⌘")
            modifier("option", title: "⌥")
            modifier("control", title: "⌃")
            modifier("shift", title: "⇧")
        }
    }

    private func modifier(_ name: String, title: String) -> some View {
        let on = latched.contains(name)
        return Button(title) {
            if on {
                latched.remove(name)
            } else {
                latched.insert(name)
            }
        }
        .buttonStyle(RemoteKeyButtonStyle(latched: on))
        .frame(maxWidth: .infinity, minHeight: 48)
        .disabled(!model.isReady)
        .accessibilityLabel(name)
    }

    private var keyGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tapKey("esc", name: "escape")
                tapKey("tab", name: "tab")
                tapKey("delete", name: "delete")
                tapKey("return", name: "return", prominent: true)
            }
            HStack(alignment: .center, spacing: 8) {
                tapKey("←", name: "arrowLeft", minHeight: 104)
                VStack(spacing: 8) {
                    tapKey("↑", name: "arrowUp")
                    tapKey("↓", name: "arrowDown")
                }
                tapKey("→", name: "arrowRight", minHeight: 104)
            }
            HoldKey(title: "space", minHeight: 52, enabled: model.isReady) { phase in
                model.sendRemote([.key(KeyBody(key: "space", modifiers: orderedModifiers, phase: phase))])
                if phase == "up" {
                    latched = []
                }
            }
        }
    }

    private var orderedModifiers: [String] {
        ["command", "option", "control", "shift"].filter { latched.contains($0) }
    }

    private func tapKey(_ title: String, name: String, prominent: Bool = false, minHeight: CGFloat = 48) -> some View {
        HoldKey(title: title, prominent: prominent, minHeight: minHeight, enabled: model.isReady) { phase in
            let body = KeyBody(key: name, modifiers: orderedModifiers, phase: phase)
            model.sendRemote([.key(body)])
            if phase == "up" {
                latched = []
            }
        }
    }

    private func sendChord(_ key: String) {
        guard let commands = KeyboardTyping.chord(key, modifiers: orderedModifiers) else { return }
        latched = []
        model.sendRemote(commands)
    }
}

struct RemoteKeyButtonStyle: ButtonStyle {
    var latched = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .remoteKey(latched: latched, pressed: configuration.isPressed)
    }
}

private struct HoldKey: View {
    var title: String
    var prominent = false
    var minHeight: CGFloat = 48
    var enabled: Bool
    var onPhase: (String) -> Void
    @State private var held = false

    var body: some View {
        Text(title)
            .font(minHeight > 80 ? .title2.weight(.medium) : .body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .remoteKey(prominent: prominent, pressed: held)
            .opacity(enabled ? 1 : 0.45)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !held else { return }
                        held = true
                        onPhase("down")
                    }
                    .onEnded { _ in
                        guard held else { return }
                        held = false
                        onPhase("up")
                    }
            )
            .allowsHitTesting(enabled)
            .accessibilityLabel(title)
    }
}
