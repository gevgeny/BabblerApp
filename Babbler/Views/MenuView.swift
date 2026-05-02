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
    @EnvironmentObject var clipboardHistory: ClipboardHistory
    @Environment(\.openSettings) var openSettings
    @Environment(\.dismiss) var dismiss
    @AppStorage(isTextReplaceEnabledKey) var isTextReplaceEnabled: Bool = true
    @AppStorage(clipboardHistoryEnabledKey) var clipboardHistoryEnabled: Bool = true

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
                            Image(systemName: "circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .opacity(source.id == appDelegate.currentLang?.id ? 1 : 0)
                                .frame(width: 16)
                        }
                    }
                    .buttonStyle(MenuItemButtonStyle())
                }
                Divider()
            }

            // Pinned clipboards
            if clipboardHistoryEnabled && !clipboardHistory.pinnedItems.isEmpty {
                PinnedClipboardsRow()
                Divider()
            }

            // Clipboard history (unpinned)
            let unpinnedItems = clipboardHistory.items.filter { !clipboardHistory.pinnedItems.contains($0) }
            if clipboardHistoryEnabled && !unpinnedItems.isEmpty {
                ClipboardHistoryRow()
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

// Reusable collapsible clipboard section header + item list
private struct CollapsibleClipboardSection: View {
    let title: String
    let entries: [(index: Int, item: String)]  // (full-array index, text)
    var showPinButton: Bool = true
    @EnvironmentObject var clipboardHistory: ClipboardHistory
    @Environment(\.dismiss) var dismiss
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        .frame(width: 16)
                }
            }
            .buttonStyle(MenuItemButtonStyle())

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(entries, id: \.index) { entry in
                        ClipboardItemRow(
                            item: entry.item,
                            isPinned: clipboardHistory.pinnedItems.contains(entry.item),
                            showPinButton: showPinButton
                        ) {
                            dismiss()
                            clipboardHistory.select(at: entry.index)
                        } onPin: {
                            clipboardHistory.pin(at: entry.index)
                        } onRemove: {
                            clipboardHistory.remove(at: entry.index)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .onDisappear { isExpanded = false }
    }
}

private struct PinnedClipboardsRow: View {
    @EnvironmentObject var clipboardHistory: ClipboardHistory
    var body: some View {
        let entries = clipboardHistory.items
            .enumerated()
            .filter { clipboardHistory.pinnedItems.contains($0.element) }
            .map { (index: $0.offset, item: $0.element) }
        CollapsibleClipboardSection(title: "Pinned Clipboards", entries: entries, showPinButton: false)
    }
}

private struct ClipboardHistoryRow: View {
    @EnvironmentObject var clipboardHistory: ClipboardHistory
    var body: some View {
        let entries = clipboardHistory.items
            .enumerated()
            .filter { !clipboardHistory.pinnedItems.contains($0.element) }
            .map { (index: $0.offset, item: $0.element) }
        CollapsibleClipboardSection(title: "Clipboard History", entries: entries)
    }
}

private struct ClipboardItemRow: View {
    let item: String
    let isPinned: Bool
    var showPinButton: Bool = true
    let onSelect: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var isPinHovered = false
    @State private var isRemoveHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 2) {
                Text(item.count > 36 ? String(item.prefix(36)) + "…" : item)
                    .lineLimit(1)
                Spacer()
                // Pin button
                if showPinButton {
                    Button(action: onPin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                            .foregroundStyle(isPinned ? .primary : .secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(isPinHovered ? 0.1 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || isPinned ? 1 : 0)
                    .onHover { isPinHovered = $0 }
                }
                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(isRemoveHovered ? 0.1 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .onHover { isRemoveHovered = $0 }
            }
        }
        .buttonStyle(MenuItemButtonStyle())
        .onHover { isHovered = $0 }
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
