import Cocoa
import Carbon

class StatusItemController: NSObject {
    let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    var messageMenuItem: NSMenuItem?
    
    var settingsViewController: SettingsViewController?
    
    override init() {
        super.init()
        NSApp.setActivationPolicy(.accessory)
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
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
    
    @objc func onLanguageItemSelect(_ targetMenuItem: NSMenuItem) {
        LanguageUtils.switchLang(targetMenuItem.title)
    }
    
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func openSettings() {
        var myWindow: NSWindow? = nil
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"),bundle: nil)
        settingsViewController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("preferencesView")) as? SettingsViewController
        myWindow = NSWindow(contentViewController: settingsViewController!)
        NSApp.activate(ignoringOtherApps: true)
        myWindow?.makeKeyAndOrderFront(self)
        let vc = NSWindowController(window: myWindow)
        vc.showWindow(self)
    }
    
    func updateMenuBarIcon(_ lang: TISInputSource?, _ isSecurityInput: Bool) {
        let inputSource = LanguageUtils.getCurrentInputSource()
        print(LanguageUtils.getCurrentInputSource())
        statusItem.button!.image = ImageUtils.getLangImage(inputSource, isSecurityInput)
        
        for menuItem in statusItem.menu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        let currentMenuItem = statusItem.menu!.items.first { $0.title == lang!.name }
        currentMenuItem!.state = NSControl.StateValue.on
    }
    
    func addInputSourceMenuItems(_ menu: NSMenu) -> Void {
        menu.addItem(NSMenuItem.separator())
        for inputSource in LanguageUtils.inputSources! {
            let item = NSMenuItem(
                title: inputSource.name,
                action: #selector(onLanguageItemSelect),
                keyEquivalent: ""
            )
            item.target = self;
            item.identifier = NSUserInterfaceItemIdentifier(rawValue: inputSource.id)
            item.image = NSImage(iconRef: inputSource.iconRef!)
            item.image!.size = NSMakeSize(16.0, 16.0)
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
