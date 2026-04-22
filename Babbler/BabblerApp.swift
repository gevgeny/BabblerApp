import SwiftUI

@main
struct BabblerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.clipboardHistory)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

