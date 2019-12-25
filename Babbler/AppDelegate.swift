//
//  AppDelegate.swift
//  test
//
//  Created by Eugene Gluhotorenko on 12/7/19.
//  Copyright © 2019 Eugene Gluhotorenko. All rights reserved.
//

import Cocoa
import Carbon


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    var messageMenuItem: NSMenuItem?
    
    var isRecordPaused = false
    
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
    
    func print(_ items: Any...) {
//        let dateFormatter : DateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "hh:mm:ss:SSS"
//        let date = Date()
//
//        Swift.print( dateFormatter.string(from: date), items)
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
        print("update")
        let title = securityApp != nil
            ? "⛔️ \"\(securityApp!)\" enabled security input mode"
            : "⛔️ Some app enabled security input mode"
        messageMenuItem?.isHidden = !isSecurityInput;
        messageMenuItem?.attributedTitle = NSAttributedString(string: title, attributes: [NSAttributedString.Key.foregroundColor: NSColor.red]
        )
        updateMenuBarIcon()
    }
    
    func handleEvent(_ event: NSEvent) {
//        let pasteboard = NSPasteboard.general
        // let copiedString = pasteboard.string(forType: .string)
//        print(copiedString)
        if isRecordPaused { return }
        print("event", event.type == .leftMouseDown ? -1 : event.keyCode)

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode
        let isArrow = code == Key.LeftArrow || code == Key.RightArrow || code == Key.UpArrow || code == Key.DownArrow
        let isEnter = code == Key.Enter
        let isRecordCanceled = code == Key.Esc || code == Key.Tab || isArrow || isEnter || isLeftMouseDown
        
    
        if KeyboardUtils.checkActionKeyPress(code, withOption) {
            print("switch")
            isRecordPaused = true
            LanguageUtils.swapLang()
            KeyboardUtils.changeTypedText(record)
            isRecordPaused = false
            return
        }
    
        // Reset record and skip event word is break or shorcut is started
        if isRecordCanceled || (withOption && code != Key.Option) || withCommand {
            record = []
            return
        }
        
        // Remove last symbol if Backspace
        if code == Key.Backspace {
            if record.count > 0 {
                record.removeLast()
            }
            return
        }
        
        if event.type != .keyDown || event.isARepeat {
            return
        }
        
        // Record pressed key
        let entry = (withShift: withShift, code: event.keyCode)
        let isWordBreak = record.last?.code == Key.Space && entry.code != Key.Space
        if (isWordBreak || WorkspaceUtils.appWasChanged()) {
            record = []
        }
        record.append(entry)
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
