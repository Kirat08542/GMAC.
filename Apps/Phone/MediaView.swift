import GLOTRemoteCore
import SwiftUI

struct MediaScreen: View {
    @Bindable var model: PhoneModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var compact: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        let play: CGFloat = compact ? 88 : 120
        let side = play * 72 / 120
        let gap = play * 28 / 120
        let transportRow = HStack(alignment: .center, spacing: gap) {
            transport("Previous", systemImage: "backward.fill", action: "previous", size: side)
            transport("Play Pause", systemImage: "playpause.fill", action: "playPause", size: play, prominent: true)
            transport("Next", systemImage: "forward.fill", action: "next", size: side)
        }
        let caption = Text("Play, pause, and skip use the Mac media keys. Volume is the system volume. Hold a volume key to keep going.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(compact ? 1 : nil)
            .padding(.horizontal, verticalSizeClass == .compact ? 12 : 24)
        let volume = HStack(spacing: 12) {
            volumeButton("Volume Down", systemImage: "speaker.minus.fill", action: "volumeDown")
            muteButton
            volumeButton("Volume Up", systemImage: "speaker.plus.fill", action: "volumeUp")
        }
        .padding(.horizontal, 24)
        Group {
            if verticalSizeClass == .compact {
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 16) {
                        if let gate = gateCopy {
                            Text(gate)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                        transportRow
                        caption
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    volume
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.46 }
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 18) {
                        if let gate = gateCopy {
                            Text(gate)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                        transportRow
                            .padding(.horizontal, 24)
                        caption
                    }
                    Spacer(minLength: 0)
                    volume
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var gateCopy: String? {
        guard !model.isReady else { return nil }
        if case .pairing = model.snapshot.state {
            return "Compare the pairing code on Link."
        }
        return "Open Link to connect."
    }

    private func transport(_ title: String, systemImage: String, action: String, size: CGFloat, prominent: Bool = false) -> some View {
        Button {
            model.sendRemote([.media(MediaBody(action: action))])
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 36 : 20, weight: .semibold))
                .foregroundStyle(prominent ? .white : .primary)
                .frame(width: size, height: size)
                .background(prominent ? Color.accentColor : Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.45)
        .accessibilityLabel(title)
    }

    private var muteButton: some View {
        Button {
            model.sendRemote([.media(MediaBody(action: "mute"))])
        } label: {
            Image(systemName: "speaker.slash.fill")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.45)
        .accessibilityLabel("Mute")
    }

    private func volumeButton(_ title: String, systemImage: String, action: String) -> some View {
        VolumeKey(title: title, systemImage: systemImage, enabled: model.isReady) {
            model.sendRemote([.media(MediaBody(action: action))])
        }
    }
}

private struct VolumeKey: View {
    var title: String
    var systemImage: String
    var enabled: Bool
    var send: () -> Void
    @State private var held = false
    @State private var pump: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(held ? Color(.systemGray3) : Color(.secondarySystemBackground), in: Capsule())
            .opacity(enabled ? 1 : 0.45)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !held else { return }
                        held = true
                        send()
                        pump = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            while !Task.isCancelled {
                                send()
                                try? await Task.sleep(for: .milliseconds(180))
                            }
                        }
                    }
                    .onEnded { _ in
                        held = false
                        pump?.cancel()
                        pump = nil
                    }
            )
            .allowsHitTesting(enabled)
            .accessibilityLabel(title)
    }
}
