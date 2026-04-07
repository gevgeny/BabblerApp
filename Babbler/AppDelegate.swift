import Cocoa
import Carbon

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItemController: StatusItemController?;
    
    var isWaitingForSwitch = false
    var didFinishAppSetup = false
    var permissionCheckTimer: Timer?

    
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
    
    
    func hasPrivileges() -> Bool {
        AXIsProcessTrusted()
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

    func openAccessibilitySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            if self.hasPrivileges() {
                timer.invalidate()
                self.permissionCheckTimer = nil
                self.finishApplicationSetup()
            }
        }
    }

    func requestAccessibilityPermissions() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Babbler needs Accessibility access to monitor keyboard shortcuts and replace typed text. Click Open System Settings, enable Babbler in Accessibility, and return to the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
            startPermissionPolling()
            return
        }

        NSApplication.shared.terminate(self)
    }

    func finishApplicationSetup() {
        if didFinishAppSetup {
            return
        }
        didFinishAppSetup = true

        KeyboardUtils.loadActionKeyFromPreferences()
        let error = LanguageUtils.initInputSources();
        
        if error != nil {
            showError(error!, "")
            return
        }
           
        LanguageUtils.onLanguageChange {
            self.currentLang = LanguageUtils.getCurrentInputSource()
           
            if (!self.isWaitingForSwitch) { return }
        
                
            // If the last word need to be translated
            if (self.record.count > 0) {
                // Replace typed text with delay in order to wait till the lang is changed.
                Task {
                    try? await Task.sleep(nanoseconds: keyboardDelay)
                    await KeyboardUtils.replaceTypedText(self.record)
                }
            }
            // If the record is empty, it makes sense to try check if selected text need to be translated
            else {
                KeyboardUtils.fetchSelectedText {text in
                    if (text.count == 0) { return }
                    
                    KeyboardUtils.typeText(text);
                }
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
    
    func handleEvent(_ event: NSEvent) {
        if isWaitingForSwitch { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let withActionModifier = flags == KeyboardUtils.actionKeyFlag
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode
        let isArrow = code == Key.leftArrow || code == Key.rightArrow || code == Key.upArrow || code == Key.downArrow
        let isEnter = code == Key.enter || code == Key.returnKey
        let isDelete = code == Key.delete
        let isRecordCanceled = code == Key.escape || code == Key.tab || isArrow || isEnter || isLeftMouseDown
       
        if KeyboardUtils.checkActionKeyPress(code, flags) {
            self.isWaitingForSwitch = true
            LanguageUtils.swapLang()
            return
        }
        // Erase record and skip event word is break or shorcut is started
        if isRecordCanceled || (withOption && code != Key.option) || withCommand || (withActionModifier && code != KeyboardUtils.actionKeyCode) {
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
        CrashLogger.install()
        
        SecurityInputUtils.listenForSecurityInput {
            self.securityApp = $1
            if self.isSecurityInput != $0 {
                self.isSecurityInput = $0
            }
        }
        NSApp.setActivationPolicy(.regular)
        
        if !hasPrivileges() {
            requestAccessibilityPermissions()
            return
        }
        
        finishApplicationSetup()
    }
}
