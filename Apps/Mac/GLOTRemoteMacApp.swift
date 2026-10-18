import SwiftUI

@main
struct GLOTRemoteMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        WindowGroup {
            MacHomeView(model: model)
        }
        .defaultSize(width: 980, height: 660)
        MenuBarExtra {
            MacMenuView(model: model)
        } label: {
            Image(systemName: model.isReady ? "dot.radiowaves.left.and.right" : "wave.3.right")
        }
        .menuBarExtraStyle(.menu)
    }
}
