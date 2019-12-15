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
    
    var enInputSource: TISInputSource?
    
    var ruInputSource: TISInputSource?
    
    var ruIcon = #imageLiteral(resourceName: "ru")
    
    var enIcon = #imageLiteral(resourceName: "gb")
    
    var alertIcon = #imageLiteral(resourceName: "alert")
    
    var record: [(withShift: Bool, code: UInt16)] = []
    
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
    
    func isEnglish(_ inputSource: TISInputSource) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("U.S.") || str.contains("British")
    }
    
    func isRussian(_ inputSource: TISInputSource) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("Russian")
    }
    
    func setCurrentLangStatusIcon() {
        let lang = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
        if isRussian(lang) {
            statusBarItem.button!.image = ruIcon
        } else {
            statusBarItem.button!.image = enIcon
        }
    }

    
    func getInputSources() {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        
        guard let en = list.first(where: isEnglish) else {
            showError("English input source not found", "")
            return
        }
        enInputSource = en
        
        guard let ru = list.first(where: isRussian) else {
            showError("Russian input source not found", "")
            return
        }
        ruInputSource = ru
    }
    
    func switchLang() {
        let lang = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
        
        if isRussian(lang) {
            TISSelectInputSource(enInputSource)
        } else {
            TISSelectInputSource(ruInputSource)
        }
    }
    
    func handleEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode
        let isWordBreak = code == Key.Esc || code == Key.Tab || code == Key.Space;
    
        if KeyboardUtils.checkActionKeyPress(code, withOption) {
            switchLang()
            KeyboardUtils.changeTypedText(record)
            return
        }
    
        // Reset record and skip event work is break or shorcut is started
        if isLeftMouseDown || isWordBreak || (withOption && code != Key.Option) || withCommand {
            record = []
            return
        }
        
        // Remove last symbol if Backspace
        if code == Key.Backspace && record.count > 0 {
            record.removeLast()
            return
        }
        
        // Record pressed key
        if event.type == .keyDown && !event.isARepeat {
            let entry = [(withShift: withShift, code: event.keyCode)]
            print(event.keyCode)
            record = WorkspaceUtils.appWasChanged()
                ? entry
                : record + entry;
        }
    }

    @objc func change() {
        setCurrentLangStatusIcon()
    }
    
    func observeLangChange() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(change),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ruIcon.size = NSMakeSize(16.0, 16.0)
        enIcon.size = NSMakeSize(16.0, 16.0)
        alertIcon.size = NSMakeSize(16.0, 16.0)
        
        if !hasPrivileges() {
            showError(
                "Accessibility privileges are not granted",
                "Go to System Prefences -> Security & Privacy -> Accessibility, and add the app into the list.\nThen restart the app."
            )
        }
        ruIcon.size = NSMakeSize(16.0, 16.0)
        enIcon.size = NSMakeSize(16.0, 16.0)
        getInputSources()
        setCurrentLangStatusIcon()
        observeLangChange()
        
        NSApp.setActivationPolicy(.accessory)
        statusBarItem.menu = NSMenu()
        statusBarItem.menu?.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "")
        
        KeyboardUtils.addGlobalEventListener(handleEvent)
    }
}
