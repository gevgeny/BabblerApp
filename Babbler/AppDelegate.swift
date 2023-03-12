import Cocoa
import Carbon

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItemController: StatusItemController?;
    
    var isWaitingForSwitch = false
    
    var isAlreadyTranslatingWord = false
    
    var isSecurityInput = false {
        didSet {
            statusItemController!.updateSecurityInputMessage(securityApp, isSecurityInput)
            statusItemController!.updateMenuBarIcon(currentLang, isSecurityInput)
        }
    }
    
    var securityApp: String?
    
    var currentLang: TISInputSource? {
        didSet {
            statusItemController!.updateMenuBarIcon(currentLang, isSecurityInput)
        }
    }
    
    var record: [(withShift: Bool, code: UInt16)] = []
    
    var text: String = ""
    
    var counter = 1
    
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
        NSApplication.shared.terminate(self)
    }
    
    func handleEvent(_ event: NSEvent) {
        if isWaitingForSwitch { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode
        let isArrow = code == Key.leftArrow || code == Key.rightArrow || code == Key.upArrow || code == Key.downArrow
        let isEnter = code == Key.enter || code == Key.returnKey
        let isDelete = code == Key.delete
        let isRecordCanceled = code == Key.escape || code == Key.tab || isArrow || isEnter || isLeftMouseDown

        print(code, flags)
        if KeyboardUtils.checkActionKeyPress(code, flags) {
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
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        SecurityInputUtils.listenForSecurityInput {
            self.securityApp = $1
            if self.isSecurityInput != $0 {
                self.isSecurityInput = $0
            }
        }
        NSApp.setActivationPolicy(.regular)
        
        if !hasPrivileges() {
            showError(
                "Accessibility privileges are not granted",
                "Go to System Prefences -> Security & Privacy -> Accessibility, and add the app into the list.\nThen restart the app.\n\n ⚠️ By adding the app into the list you allow it to read your keyboard!"
            )
        }
        let error = LanguageUtils.initInputSources();
        
        if error != nil {
            showError(error!, "")
            return
        }

        LanguageUtils.onLanguageChange {
            self.counter += 1;
            let counter = self.counter;
            self.currentLang = LanguageUtils.getCurrentInputSource()
           
            if (!self.isWaitingForSwitch) { return }
            

            self.isAlreadyTranslatingWord = true
                
            // If the last word need to be translated
            if (self.record.count > 0) {
                // Replace typed text with delay in order to wait till the lang is changed.
                print(counter, "start")
                Task {
                    try? await Task.sleep(nanoseconds: keyboardDelay)
                    await KeyboardUtils.replaceTypedText(self.record)
                    print(counter, "done")
                    self.isAlreadyTranslatingWord = false
                }
            }
            // If the selected text need to be translated
            else {
                KeyboardUtils.fetchSelectedText {text in
                    KeyboardUtils.typeText(text);
                }
                self.isAlreadyTranslatingWord = false
            }
            self.isWaitingForSwitch = false
        
        }
        
        WorkspaceUtils.onActiveAppChanged { app in
            if let appId = app.bundleIdentifier {
                let inputSource = preferenceStore.getInputSource(appId)
                if (inputSource != nil) {
                    LanguageUtils.switchLang(inputSource![0])
                }
            }
        }
        
        statusItemController = StatusItemController();
        currentLang = LanguageUtils.getCurrentInputSource()
        KeyboardUtils.addGlobalEventListener(handleEvent)
    }
}

