import SwiftUI

struct MenuBarLabel: View {
  @EnvironmentObject var appDelegate: AppDelegate
    @AppStorage(useSystemInputIndicatorKey) var useSystemInputIndicator: Bool = false
  var menuBarTitle: String {
    guard let lang = appDelegate.currentLang else { return "??" }
    return ImageUtils.languageImages[lang.id] ?? ImageUtils.getLangCode(for: lang)
  }

    var body: some View {
        if useSystemInputIndicator,
           let lang = appDelegate.currentLang,
           let icon = ImageUtils.makeInputSourceIcon(for: lang) {
            Image(nsImage: icon)
        } else {
            Text(menuBarTitle)
                .baselineOffset(-1)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.openSettings) var openSettings
    @Environment(\.dismiss) var dismiss
    @AppStorage(isTextReplaceEnabledKey) var isTextReplaceEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Replace typed text toggle
            HStack {
                Text("Replace typed text")
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: $isTextReplaceEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if appDelegate.isSecurityInput {
                let name = appDelegate.securityApp ?? "An app"
                Text("⛔️ \"\(name)\" enabled security input mode")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isTextReplaceEnabled {
                let key = actionKeySymbol()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Replace last word: \(key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    Text("Replace last line: ⇧\(key)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            // Language sources
            if let sources = InputSourceUtils.inputSources {
                Text("Input Sources")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                ForEach(sources, id: \.id) { source in
                    Button {
                        dismiss()
                        InputSourceUtils.switchLang(source.id)
                    } label: {
                        HStack {
                            Text(source.name)
                            Spacer()
                            if source.id == appDelegate.currentLang?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(MenuItemButtonStyle())
                }
                Divider()
            }

            // Settings
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                        NSApp.keyWindow?.orderFrontRegardless()
                    }
                }
            } label: {
                Text("Settings...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuItemButtonStyle())

            Divider()

            // Quit
            Button {
                dismiss()
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuItemButtonStyle())
            .padding(.bottom, 6)
        }
        .frame(width: 220)
        .animation(.easeInOut(duration: 0.2), value: isTextReplaceEnabled)
        .animation(.easeInOut(duration: 0.2), value: appDelegate.isSecurityInput)
    }

    private func actionKeySymbol() -> String {
        KeyboardUtils.actionKeyFlag == .control ? "⌃" : "⌥"
    }
}

// Native menu-item look: plain style with subtle highlight on hover
private struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .foregroundStyle(Color.primary)
            .cornerRadius(6)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .onHover { isHovered = $0 }
    }
}
