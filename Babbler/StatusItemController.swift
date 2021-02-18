import Cocoa
import Carbon

class StatusItemController {
    let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    var messageMenuItem: NSMenuItem?
    
    var icons = [
        "ru": #imageLiteral(resourceName: "ru"),
        "ru_warn": #imageLiteral(resourceName: "ru_warn"),
        "en": #imageLiteral(resourceName: "gb"),
        "en_warn": #imageLiteral(resourceName: "gb_warn"),
        "default": #imageLiteral(resourceName: "default"),
        "default_warn": #imageLiteral(resourceName: "default_warn")
    ]
    
    init() {
        icons.forEach { icon in
            icon.value.size = NSMakeSize(16.0, 16.0)
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = true
        messageMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        messageMenuItem!.isHidden = true;
        statusItem.menu!.addItem(messageMenuItem!)
        addInputSourceMenuItems(statusItem.menu!)
        statusItem.menu!.addItem(NSMenuItem.separator())
        statusItem.menu!.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "")
    }
    
    @objc func onLanguageItemSelect(_ targetMenuItem: NSMenuItem) {
        LanguageUtils.switchLang(targetMenuItem.title)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    func updateMenuBarIcon(_ lang: TISInputSource?, _ isSecurityInput: Bool) {
        var iconName = ""
        if LanguageUtils.isRussian(lang) {
            iconName = "ru"
        } else if LanguageUtils.isEnglish(lang) {
            iconName = "en"
        } else {
            iconName = "default"
        }
        
        if isSecurityInput {
            iconName += "_warn"
        }
        statusItem.button!.image = icons[iconName]
        
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
