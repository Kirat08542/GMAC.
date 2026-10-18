import GLOTRemoteCore
import SwiftUI

struct KeyboardScreen: View {
    @Bindable var model: PhoneModel
    @State private var draft = ""
    @State private var latched: Set<String> = []
    @State private var skipNextEdit = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tight: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        let key: CGFloat = tight ? 36 : 48
        let gap: CGFloat = tight ? 4 : 8
        Group {
            if verticalSizeClass == .compact {
                HStack(alignment: .top, spacing: 0) {
                    canvasBand(captionLimit: 2)
                        .frame(maxWidth: 280)
                    deck(key: key, gap: gap)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                VStack(spacing: 0) {
                    canvasBand(captionLimit: tight ? 1 : nil)
                    Spacer(minLength: 0)
                    deck(key: key, gap: gap)
                }
            }
        }
        .clipped()
    }

    private func canvasBand(captionLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            field
                .padding(.horizontal, 20)
                .padding(.top, 4)
            Text("Highlight a shortcut key, then type a letter. Password fields on the Mac reject these keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(captionLimit)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            if let gate = gateCopy {
                Text(gate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private func deck(key: CGFloat, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            modifierRow(minHeight: key)
            keyGrid(key: key, gap: gap)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
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
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.return)
            .font(.title3)
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

    private func modifierRow(minHeight: CGFloat) -> some View {
        HStack(spacing: 8) {
            modifier("command", title: "⌘", minHeight: minHeight)
            modifier("option", title: "⌥", minHeight: minHeight)
            modifier("control", title: "⌃", minHeight: minHeight)
            modifier("shift", title: "⇧", minHeight: minHeight)
        }
    }

    private func modifier(_ name: String, title: String, minHeight: CGFloat) -> some View {
        let on = latched.contains(name)
        return Button(title) {
            if on {
                latched.remove(name)
            } else {
                latched.insert(name)
            }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .buttonStyle(on ? .borderedProminent : .bordered)
        .disabled(!model.isReady)
        .accessibilityLabel(name)
    }

    private func keyGrid(key: CGFloat, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            HStack(spacing: 8) {
                tapKey("esc", name: "escape", minHeight: key)
                tapKey("tab", name: "tab", minHeight: key)
                tapKey("delete", name: "delete", minHeight: key)
                tapKey("return", name: "return", prominent: true, minHeight: key)
            }
            HStack(spacing: 8) {
                tapKey("←", name: "arrowLeft", minHeight: key)
                tapKey("↑", name: "arrowUp", minHeight: key)
                tapKey("↓", name: "arrowDown", minHeight: key)
                tapKey("→", name: "arrowRight", minHeight: key)
            }
            HoldKey(title: "space", minHeight: key == 36 ? 40 : 52, enabled: model.isReady) { phase in
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

private struct HoldKey: View {
    var title: String
    var prominent = false
    var minHeight: CGFloat = 48
    var enabled: Bool
    var onPhase: (String) -> Void
    @State private var held = false

    var body: some View {
        Text(title)
            .font(minHeight > 80 ? .system(size: 28, weight: .medium) : .body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(prominent ? .white : .primary)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(held ? 0.96 : 1)
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

    private var fill: Color {
        if prominent {
            return .accentColor
        }
        if held {
            return Color(.systemGray3)
        }
        return Color(.secondarySystemBackground)
    }
}
