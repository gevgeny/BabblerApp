import SwiftUI
import Carbon

struct SwitchKeyOption: Identifiable {
    let label: String
    let code: UInt16
    var id: UInt16 { code }
}

let switchKeyOptions: [SwitchKeyOption] = [
    SwitchKeyOption(label: "Option", code: Key.option),
    SwitchKeyOption(label: "Right Option", code: Key.rightOption),
    SwitchKeyOption(label: "Control", code: Key.control),
    SwitchKeyOption(label: "Right Control", code: Key.rightControl),
]

struct AppListItem: Identifiable {
    let name: String
    let id: String
    let icon: NSImage
}

struct SettingsView: View {
    @State private var selectedSwitchKeyCode: UInt16
    @State private var appList: [AppListItem] = []

    init() {
        _selectedSwitchKeyCode = State(initialValue: preferenceStore.getSwitchKeyCode())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lang switch key:")
                Picker("", selection: $selectedSwitchKeyCode) {
                    ForEach(switchKeyOptions) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            Text("Set default keyboard input for apps below:")

            List(appList) { app in
                AppInputSourceRow(app: app)
            }
        }
        .padding()
        .frame(width: 480, height: 350)
        .onChange(of: selectedSwitchKeyCode) { _, newValue in
            preferenceStore.setSwitchKeyCode(newValue)
            KeyboardUtils.setActionKey(code: newValue)
        }
        .onAppear {
            WorkspaceUtils.listAllApps { apps in
                appList = apps.map { AppListItem(name: $0.name, id: $0.id, icon: $0.icon) }
            }
        }
    }
}

struct AppInputSourceRow: View {
    let app: AppListItem
    @State private var selectedInputSourceId: String

    init(app: AppListItem) {
        self.app = app
        let saved = preferenceStore.getInputSource(app.id)
        _selectedInputSourceId = State(initialValue: saved?[0] ?? "")
    }

    var body: some View {
        HStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
            Spacer()
            Picker("", selection: $selectedInputSourceId) {
                Text("(not set)")
                    .tag("")
                if let sources = LanguageUtils.inputSources {
                    ForEach(sources, id: \.id) { source in
                        Text(source.name).tag(source.id)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .onChange(of: selectedInputSourceId) { _, newValue in
            if newValue.isEmpty {
                preferenceStore.resetInputSource(app.id)
            } else if let source = LanguageUtils.inputSources?.first(where: { $0.id == newValue }) {
                preferenceStore.setInputSource(app.id, newValue, source.name)
            }
        }
    }
}
