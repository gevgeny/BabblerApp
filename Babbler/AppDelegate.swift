import Cocoa
import Carbon


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    var messageMenuItem: NSMenuItem?
    
    var isWaitingForSwitch = false
    
    var isSecurityInput = false { didSet { updateSecurityInputMessage() } }
    
    var securityApp: String?
    
    var currentLang: TISInputSource? { didSet { updateMenuBarIcon() } }
    
    var icons = [
        "ru": #imageLiteral(resourceName: "ru"),
        "ru_warn": #imageLiteral(resourceName: "ru_warn"),
        "en": #imageLiteral(resourceName: "gb"),
        "en_warn": #imageLiteral(resourceName: "gb_warn"),
        "default": #imageLiteral(resourceName: "default"),
        "default_warn": #imageLiteral(resourceName: "default_warn")
    ]
    
    var record: [(withShift: Bool, code: UInt16)] = []
    
    var text: String = ""
    
    static func print(_ items: Any...) {
        let dateFormatter : DateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm:ss:SSS"
        let date = Date()

        Swift.print( dateFormatter.string(from: date), items)
    }
    
    func print(_ items: Any...) {
        AppDelegate.print(items)
    }
    
    func hasPrivileges() -> Bool {
      return AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        quit()
    }

    func updateMenuBarIcon() {
        var iconName = ""
        if LanguageUtils.isRussian(currentLang) {
            iconName = "ru"
        } else if LanguageUtils.isEnglish(currentLang) {
            iconName = "en"
        } else {
            iconName = "default"
        }
        
        if isSecurityInput {
            iconName += "_warn"
        }
        statusBarItem.button!.image = icons[iconName]
        
        for menuItem in statusBarItem.menu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        let currentMenuItem = statusBarItem.menu!.items.first { $0.title == currentLang!.name }
        currentMenuItem!.state = NSControl.StateValue.on
    }
    
    func updateSecurityInputMessage() {
        let title = securityApp != nil
            ? "⛔️ \"\(securityApp!)\" enabled security input mode"
            : "⛔️ Some app enabled security input mode"
        messageMenuItem?.isHidden = !isSecurityInput;
        messageMenuItem?.attributedTitle = NSAttributedString(string: title, attributes: [NSAttributedString.Key.foregroundColor: NSColor.red]
        )
        updateMenuBarIcon()
    }
    
    func handleEvent(_ event: NSEvent) {
        if isWaitingForSwitch { return }
        if (event.type == .keyDown) {
            //print("event",event.keyCode,  event.characters!)
        }
        

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode
        let isArrow = code == Key.leftArrow || code == Key.rightArrow || code == Key.upArrow || code == Key.downArrow
        let isEnter = code == Key.enter
        let isDelete = code == Key.delete
        let isRecordCanceled = code == Key.escape || code == Key.tab || isArrow || isEnter || isLeftMouseDown

        if KeyboardUtils.checkActionKeyPress(code, withOption) {
            //print("switch", text)
            self.isWaitingForSwitch = true
            LanguageUtils.swapLang()
            return
        }
        
        // Erase record and skip event word is break or shorcut is started
        if isRecordCanceled || (withOption && code != Key.option) || withCommand {
            record = []
            text = ""
            
            return
        }
        
        // Delete last symbol if delete was pressed
        if isDelete && record.count > 0 {
            record.removeLast()
            text = String(text.dropLast())
        }
        
        if code == Key.delete || event.type != .keyDown || event.isARepeat {
            return
        }
        
        let isWordBreak = record.last?.code == Key.space && event.keyCode != Key.space
        let appDidChange = WorkspaceUtils.checkCurrentApp()
        if (isWordBreak || appDidChange) {
            record = []
            text = ""
        }
        
        // Save pressed key
        let entry = (withShift: withShift, code: event.keyCode)
        record.append(entry)
        text += event.characters!
        //print("text", text)
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func onLanguageItemSelect(_ targetMenuItem: NSMenuItem) {
        LanguageUtils.switchLang(targetMenuItem.title)
    }

    func addInputSourceMenuItems(_ menu: NSMenu) -> Void {
        menu.addItem(NSMenuItem.separator())
        for inputSource in LanguageUtils.inputSources! {
            let item = NSMenuItem(
                title: inputSource.name,
                action: #selector(onLanguageItemSelect),
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier(rawValue: inputSource.id)
            item.image = NSImage(iconRef: inputSource.iconRef!)
            item.image!.size = NSMakeSize(16.0, 16.0)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        SecurityInputUtils.listenForSecurityInput {
            self.securityApp = $1
            if self.isSecurityInput != $0 {
                self.isSecurityInput = $0
            }
        }
        NSApp.setActivationPolicy(.regular)
        icons.forEach { icon in
            icon.value.size = NSMakeSize(16.0, 16.0)
        }
        
        if !hasPrivileges() {
            showError(
                "Accessibility privileges are not granted",
                "Go to System Prefences -> Security & Privacy -> Accessibility, and add the app into the list.\nThen restart the app."
            )
        }
        let error = LanguageUtils.fetchInputSources();
        
        if error != nil {
            showError(error!, "")
            return
        }

        LanguageUtils.onLanguageChange {
            self.currentLang = LanguageUtils.getCurrentLanguage()
            
            if (self.isWaitingForSwitch) {
                if (self.record.count > 0) {
                    // Replace typed text with delay in order to wait till the lang is changed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        KeyboardUtils.replaceTypedText(self.record)
                    }
                } else {
                    KeyboardUtils.fetchSelectedText {text in
                        self.print("fetched text",  text)
                        KeyboardUtils.typeText(text);
                        
                    }
                }
                self.isWaitingForSwitch = false
            }
        }

        NSApp.setActivationPolicy(.accessory)
        statusBarItem.menu = NSMenu()
        statusBarItem.menu?.autoenablesItems = true
        messageMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        messageMenuItem!.isHidden = true;
        statusBarItem.menu!.addItem(messageMenuItem!)
        addInputSourceMenuItems(statusBarItem.menu!)
        statusBarItem.menu!.addItem(NSMenuItem.separator())
        statusBarItem.menu!.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "")

        currentLang = LanguageUtils.getCurrentLanguage()
        KeyboardUtils.addGlobalEventListener(handleEvent)
    }
}
