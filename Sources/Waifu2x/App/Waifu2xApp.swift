import SwiftUI

struct Waifu2xApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Waifu2x", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
