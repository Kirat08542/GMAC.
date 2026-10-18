import GLOTRemoteCore
import SwiftUI

struct MediaScreen: View {
    @Bindable var model: PhoneModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            if let gate = gateCopy {
                Text(gate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RemoteTheme.secondary)
            }
            HStack(alignment: .center, spacing: 28) {
                transport("Previous", systemImage: "backward.fill", action: "previous", size: 68)
                transport("Play Pause", systemImage: "playpause.fill", action: "playPause", size: 128, prominent: true)
                transport("Next", systemImage: "forward.fill", action: "next", size: 68)
            }
            HStack(spacing: 8) {
                volumeButton("Volume Down", systemImage: "speaker.minus.fill", action: "volumeDown")
                muteButton
                volumeButton("Volume Up", systemImage: "speaker.plus.fill", action: "volumeUp")
            }
            .padding(8)
            .background(RemoteTheme.well, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            Text("Play, pause, and skip use the Mac media keys. Volume is the system volume. Hold a volume key to keep going.")
                .font(.caption)
                .foregroundStyle(RemoteTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RemoteTheme.canvas)
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
                .foregroundStyle(RemoteTheme.text)
                .frame(width: size, height: size)
                .background(prominent ? RemoteTheme.accent : RemoteTheme.keyFill, in: Circle())
        }
        .buttonStyle(RemotePressStyle())
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
                .foregroundStyle(RemoteTheme.text)
                .frame(maxWidth: .infinity, minHeight: 64)
                .remoteKey(capsule: true)
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
            .frame(maxWidth: .infinity, minHeight: 64)
            .remoteKey(pressed: held, capsule: true)
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
