import SwiftUI

@main
struct BabblerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(clipboardHistoryEnabledKey) var clipboardHistoryEnabled: Bool = true

    init() {
        // Before any view reads @AppStorage, so the menu bar never flashes the default style
        preferenceStore.migrateMenuBarIconStyle()
    }

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
        .onChange(of: clipboardHistoryEnabled) { _, enabled in
            if enabled { appDelegate.clipboardHistory.start() }
            else { appDelegate.clipboardHistory.stop() }
        }
    }
}

