import SwiftUI
import Carbon
import UniformTypeIdentifiers

extension Notification.Name {
    static let statusBarIndicatorStyleChanged = Notification.Name("statusBarIndicatorStyleChanged")
}

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
    @State private var useSystemInputIndicator: Bool
    @State private var configuredApps: [AppListItem] = []

    init() {
        _selectedSwitchKeyCode = State(initialValue: preferenceStore.getSwitchKeyCode())
        _useSystemInputIndicator = State(initialValue: preferenceStore.getUseSystemInputIndicator())
    }

    var body: some View {
        Form {
            Section("General") {
                VStack(alignment: .leading, spacing: 3) {
                    Picker("Action key", selection: $selectedSwitchKeyCode) {
                        ForEach(switchKeyOptions) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    Text("Press the action key to convert the last typed word or selected text to the other keyboard layout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Toggle("Use system input indicator", isOn: $useSystemInputIndicator)
            }
            
            Section {
                ScrollView {
                    if configuredApps.isEmpty {
                        Text("No apps configured.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(configuredApps) { app in
                                AppInputSourceRow(app: app, onRemove: { removeApp(app) })
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                Button {
                    addApp()
                } label: {
                    Label("Add App", systemImage: "plus")
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Input Source")
                    Text("Keyboard input automatically switches when the app is activated.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: selectedSwitchKeyCode) { _, newValue in
            preferenceStore.setSwitchKeyCode(newValue)
            KeyboardUtils.setActionKey(code: newValue)
        }
        .onChange(of: useSystemInputIndicator) { _, newValue in
            preferenceStore.setUseSystemInputIndicator(newValue)
            NotificationCenter.default.post(name: .statusBarIndicatorStyleChanged, object: nil)
        }
        .onAppear {
            loadConfiguredApps()
        }
    }
    
    private func loadConfiguredApps() {
        let saved = preferenceStore.getAllConfiguredApps()
        let availableSourceIds = Set(InputSourceUtils.inputSources?.map { $0.id } ?? [])
        configuredApps = saved.compactMap { (bundleId, values) -> AppListItem? in
            guard values.count >= 2 else { return nil }
            // Remove entries whose input source is no longer available
            if !availableSourceIds.contains(values[0]) {
                preferenceStore.resetInputSource(bundleId)
                return nil
            }
            let name: String
            let icon: NSImage
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                icon = NSWorkspace.shared.icon(forFile: appURL.path)
            } else {
                name = bundleId
                icon = NSWorkspace.shared.icon(for: .application)
            }
            return AppListItem(name: name, id: bundleId, icon: icon)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }
        
        // Skip if already configured
        if configuredApps.contains(where: { $0.id == bundleId }) { return }
        
        // Save with the first available input source
        guard let firstSource = InputSourceUtils.inputSources?.first else { return }
        preferenceStore.setInputSource(bundleId, firstSource.id, firstSource.name)
        
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let item = AppListItem(name: name, id: bundleId, icon: icon)
        configuredApps.append(item)
        configuredApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func removeApp(_ app: AppListItem) {
        preferenceStore.resetInputSource(app.id)
        configuredApps.removeAll { $0.id == app.id }
    }
}

struct AppInputSourceRow: View {
    let app: AppListItem
    let onRemove: () -> Void
    @State private var selectedInputSourceId: String

    init(app: AppListItem, onRemove: @escaping () -> Void) {
        self.app = app
        self.onRemove = onRemove
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
                if let sources = InputSourceUtils.inputSources {
                    ForEach(sources, id: \.id) { source in
                        Text(source.name).tag(source.id)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selectedInputSourceId) { _, newValue in
            if let source = InputSourceUtils.inputSources?.first(where: { $0.id == newValue }) {
                preferenceStore.setInputSource(app.id, newValue, source.name)
            }
        }
    }
}
