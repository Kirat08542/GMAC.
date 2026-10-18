# GLOT Remote

An iPhone and a Mac on the same Wi-Fi. Phase 1 is discovery, TLS, pairing, and one authenticated test command. Pointer, keyboard, media, app launch, and clipboard transfer are not implemented.

## Layout

- `Package.swift` and `Sources/GLOTRemoteCore/` — protocol, pairing, TLS, Bonjour.
- `Tests/GLOTRemoteCoreTests/ProtocolTests.swift` — encoding, validation, and loopback TLS tests.
- `Apps/Phone/` — GLOT Remote, iOS 18, iPhone only. Bundle id `com.glot.remote.phone`.
- `Apps/Mac/` — GLOT Remote Mac, macOS 15, sandboxed. Bundle id `com.glot.remote.mac`.
- `Apps/Shared/` — theme and connection copy used by both apps.
- `GLOTRemote.xcodeproj` — both app targets, local package `GLOTRemoteCore`.
- `SECURITY.md` — threat model.

The Xcode project uses ad-hoc signing (`CODE_SIGN_IDENTITY = -`) so it builds without a team. App Store or TestFlight needs a development team and automatic or distribution signing. `ITSAppUsesNonExemptEncryption` is false because the app uses standard TLS.

## Build

```sh
cd /Users/kirat/gmac
swift test
xcodebuild -project GLOTRemote.xcodeproj -scheme "GLOT Remote" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcodebuild -project GLOTRemote.xcodeproj -scheme "GLOT Remote Mac" -destination 'platform=macOS' -configuration Debug build
```

Replace the simulator name with one from `xcrun simctl list devices available`.

Checked on this Mac on 2026-10-17: `swift test` passed 21 tests, including loopback TLS pairing. Both schemes built. An iPhone and a Mac on Wi-Fi have not been tested. The Mac app was not launched, so the local-network prompt has not been accepted.

## What Phase 1 does

On the Mac, Listening is off until you turn it on. The choice is stored in Application Support, not UserDefaults. Start at login is off. Turning it on calls `SMAppService.mainApp.register()`. An ad-hoc signature often fails that call. The Mac shows the error and does not pretend it succeeded.

The iPhone browses `_glotremote._tcp`. Connect starts TLS 1.3. Both screens show the same six-digit code. Approve on the Mac and tap Codes match on the iPhone. Send test then expects the Mac note “Test command acknowledged.”

Accessibility is not requested. The Mac says so.

## Input limits, from the SDKs

These APIs exist and are not wired up:

- Mouse and keyboard: `CGEvent.post` requires Accessibility (`AXIsProcessTrustedWithOptions`). Secure input blocks synthetic keys in password fields. No kernel extension and no privileged helper.
- Launching an app: `NSWorkspace.openApplication(at:configuration:completionHandler:)`, and only for bundle ids the Mac user has approved. No shell.
- Volume and mute: Core Audio `kAudioDevicePropertyVolumeScalar` and `kAudioDevicePropertyMute`. There is no public API that drives every media app the same way.
- Sleep: `IOPMSleepSystem` exists and has not been tested.
- Lock screen: no public `NSWorkspace` lock. Private lock calls are not used.
- Brightness: `IODisplaySetFloatParameter` is not reliable on Apple Silicon and is not claimed.
- Clipboard: `NSPasteboard` / `UIPasteboard`, user initiated, text only, when that phase exists.

The apps run in the logged-in user session. They do not control the login window.

## Hardware checklist

Loopback tests do not prove Wi-Fi, Bonjour permission, or the local-network prompt.

1. Install both apps on a real iPhone and the Mac. The Mac build is sandboxed and ad-hoc signed.
2. On the Mac, turn Listening on and allow the local-network and incoming-connection prompts.
3. On the iPhone, allow Local Network. Confirm the Mac name appears.
4. Connect. Confirm both codes match, then approve on both sides.
5. Tap They differ on one side and confirm the Mac does not keep the iPhone.
6. Pair again, send the test command, and confirm the Mac shows the acknowledgement.
7. Quit the iPhone app, reopen it, and confirm the saved Mac connects without a new code.
8. Revoke on the Mac and confirm the iPhone cannot reconnect until Forget.
9. Turn Wi-Fi off for a few seconds and confirm the iPhone shows Reconnecting, then Connected.
10. Confirm Start at login stays off, and that enabling it reports an error on an ad-hoc build.
