import Cocoa
import Carbon
import SwiftUI

class StatusItemController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var messageMenuItem: NSMenuItem?
    var settingsWindowController: NSWindowController?

    private var currentLang: TISInputSource?
    private var currentIsSecurityInput: Bool = false
    private var enableToggle: NSSwitch?
    private var wordHintItem: NSMenuItem?
    private var lineHintItem: NSMenuItem?
    private var wordHintField: NSTextField?
    private var lineHintField: NSTextField?
    
    override init() {
        super.init()
        NSApp.mainMenu = nil
        NSApp.setActivationPolicy(.accessory)
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        statusItem.menu?.delegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onIndicatorStyleChanged),
            name: .statusBarIndicatorStyleChanged,
            object: nil
        )
        
        
        
        statusItem.menu!.addItem(makeEnableToggleItem())
        wordHintItem = makeShortcutHintItem(label: "Switch last word:")
        lineHintItem = makeShortcutHintItem(label: "Switch last line:")
        wordHintField = wordHintItem!.view?.subviews.compactMap { $0 as? NSTextField }.first
        lineHintField = lineHintItem!.view?.subviews.compactMap { $0 as? NSTextField }.first
        statusItem.menu!.addItem(wordHintItem!)
        statusItem.menu!.addItem(lineHintItem!)

        statusItem.menu!.addItem(NSMenuItem.separator())
            
        messageMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        messageMenuItem!.isHidden = true;
        statusItem.menu!.addItem(messageMenuItem!)
        
        statusItem.menu!.addItem(NSMenuItem.separator())
        
        addInputSourceMenuItems(statusItem.menu!)
        let openSettingsMenuItem = NSMenuItem(
            title: "Open Settings",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        openSettingsMenuItem.target = self;
        statusItem.menu!.addItem(openSettingsMenuItem)
        statusItem.menu!.addItem(NSMenuItem.separator())
        let quitMenuItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitMenuItem.target = self;
        statusItem.menu!.addItem(quitMenuItem)
        
    }
    
    private func makeEnableToggleItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))

        let label = NSTextField(labelWithString: "Replace typed text")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.frame = NSRect(x: 14, y: 6, width: 140, height: 18)

        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(onEnableToggle)
        toggle.frame = NSRect(x: view.frame.width - 54, y: 3, width: 44, height: 24)
        enableToggle = toggle

        view.addSubview(label)
        view.addSubview(toggle)
        item.view = view
        return item
    }

    private func makeShortcutHintItem(label: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 20))

        let textField = NSTextField(labelWithString: label)
        textField.font = NSFont.systemFont(ofSize: 11)
        textField.textColor = NSColor.secondaryLabelColor
        textField.frame = NSRect(x: 14, y: 1, width: 200, height: 18)

        view.addSubview(textField)
        item.view = view
        return item
    }

    private func actionKeySymbol() -> String {
        return KeyboardUtils.actionKeyFlag == .control ? "⌃" : "⌥"
    }

    func menuWillOpen(_ menu: NSMenu) {
        let enabled = preferenceStore.getIsTextReplaceEnabled()
        enableToggle?.state = enabled ? .on : .off
        wordHintItem?.isHidden = !enabled
        lineHintItem?.isHidden = !enabled

        let key = actionKeySymbol()
        wordHintField?.stringValue = "Replace last word: \(key)"
        lineHintField?.stringValue = "Replace last line: ⇧\(key)"
    }

    @objc func onEnableToggle(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        preferenceStore.setIsTextReplaceEnabled(enabled)
        wordHintItem?.isHidden = !enabled
        lineHintItem?.isHidden = !enabled
    }

    @objc func onLanguageItemSelect(_ targetMenuItem: NSMenuItem) {
        InputSourceUtils.switchLang(targetMenuItem.representedObject as! String)
    }
    
    
    @objc func onIndicatorStyleChanged() {
        if let lang = currentLang {
            updateMenuBarIcon(lang, currentIsSecurityInput)
        }
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func openSettings() {
        if let existing = settingsWindowController?.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        let fittingSize = hostingController.view.fittingSize
        window.setContentSize(fittingSize)
        window.title = "Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable]
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()
        settingsWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(self)
    }
    
    func updateMenuBarIcon(_ lang: TISInputSource?, _ isSecurityInput: Bool) {
        currentLang = lang
        currentIsSecurityInput = isSecurityInput
        
        if preferenceStore.getUseSystemInputIndicator() {
            statusItem.button!.attributedTitle = NSAttributedString(string: "")
            statusItem.button!.image = makeInputSourceIcon(for: lang!)
        } else {
            statusItem.button!.image = nil
            statusItem.button!.attributedTitle = NSAttributedString(
                string: LanguageImages[lang!.id] ?? lang!.name,
                attributes: [NSAttributedString.Key.baselineOffset: -0.7])
        }
        
        for menuItem in statusItem.menu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        let currentMenuItem = statusItem.menu!.items.first { $0.title == lang!.name }
        currentMenuItem!.state = NSControl.StateValue.on
    }
    
    func addInputSourceMenuItems(_ menu: NSMenu) -> Void {
        menu.addItem(NSMenuItem.separator())
        for inputSource in InputSourceUtils.inputSources! {
            let item = NSMenuItem(
                title: inputSource.name,
                action: #selector(onLanguageItemSelect),
                keyEquivalent: ""
            )
            item.target = self;
            item.identifier = NSUserInterfaceItemIdentifier(rawValue: inputSource.id)
            if let iconURL = inputSource.iconImageURL,
               let image = NSImage(contentsOf: iconURL) {
                image.size = NSMakeSize(16.0, 16.0)
                item.image = image
            }
            item.representedObject = inputSource.id
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
    }
    
    func updateSecurityInputMessage(_ securityApp: String?, _ isSecurityInput: Bool) {
        let title = securityApp != nil
            ? "⛔️ \"\(securityApp!)\" enabled security input mode"
            : "⛔️ Some app enabled security input mode"
        messageMenuItem?.isHidden = !isSecurityInput;
        messageMenuItem?.attributedTitle = NSAttributedString(string: title, attributes: [NSAttributedString.Key.foregroundColor: NSColor.red]
        )
    }
}
