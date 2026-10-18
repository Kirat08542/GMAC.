import Foundation
import Testing
@testable import GLOTRemoteCore

@Test func typingInsertsTextAndDeletesCharacters() {
    let typed = KeyboardTyping.commands(replacing: "", with: "Hi")
    #expect(typed == [.text(TextBody(text: "Hi"))])
    let edited = KeyboardTyping.commands(replacing: "cat", with: "car")
    #expect(edited == [
        .key(KeyBody(key: "delete", modifiers: [], phase: "down")),
        .key(KeyBody(key: "delete", modifiers: [], phase: "up")),
        .text(TextBody(text: "r")),
    ])
    #expect(KeyboardTyping.commands(replacing: "a", with: "a").isEmpty)
}

@Test func aLatchedCommandSendsAShortcut() {
    let shortcut = KeyboardTyping.shortcut("c", modifiers: ["command"])
    #expect(shortcut == [
        .key(KeyBody(key: "c", modifiers: ["command"], phase: "down")),
        .key(KeyBody(key: "c", modifiers: ["command"], phase: "up")),
    ])
    let shifted = KeyboardTyping.shortcut("C", modifiers: ["command"])
    #expect(shifted == [
        .key(KeyBody(key: "c", modifiers: ["command", "shift"], phase: "down")),
        .key(KeyBody(key: "c", modifiers: ["command", "shift"], phase: "up")),
    ])
    #expect(KeyboardTyping.shortcut("!", modifiers: ["command"]) == nil)
    #expect(KeyboardTyping.shortcut("c", modifiers: []) == nil)
    #expect(KeyboardTyping.chord("return", modifiers: [])?.count == 2)
    #expect(KeyboardTyping.chord("c", modifiers: []) == nil)
}

@Test func keyboardCommandsAreAcceptedWhenAuthenticated() throws {
    let key = try WireCoding.encodePayload(KeyBody(key: "c", modifiers: ["command"], phase: "down"))
    let text = try WireCoding.encodePayload(TextBody(text: "Hello"))
    let media = try WireCoding.encodePayload(MediaBody(action: "playPause"))
    #expect(ControlPolicy.decide(type: WireType.key, authenticated: true, payload: key) == .handle)
    #expect(ControlPolicy.decide(type: WireType.text, authenticated: true, payload: text) == .handle)
    #expect(ControlPolicy.decide(type: WireType.media, authenticated: true, payload: media) == .handle)
    let launch = try WireCoding.encodePayload(LaunchBody(bundleID: "com.apple.Safari"))
    #expect(ControlPolicy.decide(type: WireType.launch, authenticated: true, payload: launch) == .handle)
    let system = try WireCoding.encodePayload(SystemBody(action: "lock", confirmed: true))
    #expect(ControlPolicy.decide(type: WireType.system, authenticated: true, payload: system) == .unsupported)
    let sleep = try WireCoding.encodePayload(SystemBody(action: "sleep", confirmed: true))
    #expect(ControlPolicy.decide(type: WireType.system, authenticated: true, payload: sleep) == .handle)
    let unconfirmed = try WireCoding.encodePayload(SystemBody(action: "sleep", confirmed: false))
    #expect(ControlPolicy.decide(type: WireType.system, authenticated: true, payload: unconfirmed) == .invalid("This action needs confirmation."))
    #expect(throws: RemoteError.invalid("Sleep is not running in this process.")) {
        try DeniedPower().sleep()
    }
    #expect(ControlPolicy.decide(type: WireType.key, authenticated: false, payload: key) == .unauthorized)
    let rejected = try WireCoding.encodePayload(MediaBody(action: "eject"))
    #expect(ControlPolicy.decide(type: WireType.media, authenticated: true, payload: rejected) == .invalid("The media action is not supported."))
    #expect(throws: RemoteError.invalid("Keyboard control is not running in this process.")) {
        try DeniedKeyboard().text(TextBody(text: "Hi"))
    }
    #expect(throws: RemoteError.invalid("Media control is not running in this process.")) {
        try DeniedMedia().perform(MediaBody(action: "mute"))
    }
    let apps = try WireCoding.encodePayload(AppCatalog(apps: []))
    #expect(ControlPolicy.decide(type: WireType.apps, authenticated: true, payload: apps) == .unsupported)
}

@Test func approvedAppsStayOnTheUserList() throws {
    var list = try ApprovedApps().adding(bundleID: "com.apple.Safari", name: "Safari")
    #expect(list.allows("com.apple.Safari"))
    #expect(list.allows("com.apple.TextEdit") == false)
    list = list.removing("com.apple.Safari")
    #expect(list.allows("com.apple.Safari") == false)

    var full = ApprovedApps()
    for index in 0..<40 {
        full = try full.adding(bundleID: "app.example.\(index)", name: "App \(index)")
    }
    let replaced = try full.adding(bundleID: "app.example.0", name: "Renamed")
    #expect(replaced.apps.count == 40)
    #expect(replaced.allows("app.example.0"))
    #expect(replaced.apps.contains { $0.bundleID == "app.example.0" && $0.name == "Renamed" })
    #expect(throws: RemoteError.invalid("The Mac already has 40 approved apps.")) {
        try full.adding(bundleID: "app.example.extra", name: "Extra")
    }
    #expect(throws: RemoteError.invalid("The application identifier is not valid.")) {
        try ApprovedApps().adding(bundleID: "../bin", name: "Bad")
    }

    let duplicate = AppCatalog(apps: [
        AppRecord(bundleID: "com.apple.Safari", name: "Safari"),
        AppRecord(bundleID: "com.apple.Safari", name: "Safari"),
    ])
    #expect(throws: RemoteError.invalid("The app list repeats an app.")) {
        try PayloadValidation.catalog(duplicate)
    }
    var tooMany: [AppRecord] = []
    for index in 0..<41 {
        tooMany.append(AppRecord(bundleID: "app.example.\(index)", name: "App"))
    }
    #expect(throws: RemoteError.invalid("The app list is too long.")) {
        try PayloadValidation.catalog(AppCatalog(apps: tooMany))
    }
}

@Test func deniedLauncherRefusesToOpen() async {
    await #expect(throws: RemoteError.invalid("App launch is not running in this process.")) {
        try await DeniedLauncher().launch(bundleID: "com.apple.Safari")
    }
}
