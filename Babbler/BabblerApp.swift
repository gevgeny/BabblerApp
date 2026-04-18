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
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

