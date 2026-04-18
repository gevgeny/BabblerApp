import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    @Published var currentLang: TISInputSource? = InputSourceUtils.getCurrentInputSource()
    @Published var isSecurityInput = false
    @Published var securityApp: String?

    var menuBarTitle: String {
        guard let lang = currentLang else { return "??" }
        return LanguageImages[lang.id] ?? lang.name
    }

    var isWaitingForSwitch = false
    var didFinishAppSetup = false
    var permissionCheckTimer: Timer?

    // Keycodes of the current word; resets on word break (space → new char) or cancel.
    var wordRecord: [(withShift: Bool, code: UInt16)] = []
    // Keycodes since the last hard cancel (escape, enter, arrow, click, app change); spans multiple words.
    var lineRecord: [(withShift: Bool, code: UInt16)] = []
    // Snapshot of whichever record the current action fired on; consumed by onKeyboardInputSourceChanged.
    var pendingRecord: [(withShift: Bool, code: UInt16)] = []

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
        if didFinishAppSetup { return }
        didFinishAppSetup = true

        KeyboardUtils.loadActionKeyFromPreferences()
        let error = InputSourceUtils.initInputSources()

        if error != nil {
            showError(error!, "")
            return
        }

        InputSourceUtils.onKeyboardInputSourceChanged {
            self.currentLang = InputSourceUtils.getCurrentInputSource()

            if !self.isWaitingForSwitch { return }

            if self.pendingRecord.count > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: keyboardDelay)
                    await KeyboardUtils.replaceTypedText(self.pendingRecord)
                }
            } else {
                KeyboardUtils.fetchSelectedText { text in
                    if text.count == 0 { return }
                    KeyboardUtils.typeText(text)
                }
            }

            self.isWaitingForSwitch = false
        }

        WorkspaceUtils.onActiveAppChanged { app in
            if let appId = app.bundleIdentifier {
                let inputSource = preferenceStore.getInputSource(appId)
                if inputSource != nil {
                    InputSourceUtils.switchLang(inputSource![0])
                }
            }
        }

        currentLang = InputSourceUtils.getCurrentInputSource()
        KeyboardUtils.addGlobalEventListener(handleGlobalSystemEvent)
        NSApp.setActivationPolicy(.accessory)
    }

    func handleGlobalSystemEvent(_ event: NSEvent) {
        if isWaitingForSwitch { return }
        if isSecurityInput { return }

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

        switch KeyboardUtils.checkActionKeyPress(code, flags) {
        case .action:
            if preferenceStore.getIsTextReplaceEnabled() {
                self.pendingRecord = self.wordRecord
                self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .lineAction:
            if preferenceStore.getIsTextReplaceEnabled() {
                self.pendingRecord = self.lineRecord
                self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .none:
            break
        }

        // Erase both records on cancel or when a shortcut modifier is active
        if isRecordCanceled || (withOption && code != Key.option) || withCommand || (withActionModifier && code != KeyboardUtils.actionKeyCode) {
            wordRecord = []
            lineRecord = []
            text = ""
            return
        }

        // Delete last symbol from both records
        if isDelete && wordRecord.count > 0 {
            wordRecord.removeLast()
            text = String(text.dropLast())
        }
        if isDelete && lineRecord.count > 0 {
            lineRecord.removeLast()
        }

        if code == Key.delete || event.type != .keyDown || event.isARepeat {
            return
        }

        let isWordBreak = wordRecord.last?.code == Key.space && event.keyCode != Key.space
        let appDidChange = WorkspaceUtils.checkCurrentApp()
        if isWordBreak || appDidChange {
            wordRecord = []
            text = ""
            if appDidChange {
                lineRecord = []
            }
        }

        // Save pressed key to both records
        let entry = (withShift: withShift, code: event.keyCode)
        wordRecord.append(entry)
        lineRecord.append(entry)
        text += event.characters!
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        CrashLogger.install()
        currentLang = InputSourceUtils.getCurrentInputSource()

        let bundleID = Bundle.main.bundleIdentifier!
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        if running.count > 1 {
            NSApplication.shared.terminate(self)
            return
        }

        SecurityInputUtils.listenForSecurityInput { [weak self] isEnabled, appName in
            guard let self else { return }
            if self.isSecurityInput != isEnabled { self.isSecurityInput = isEnabled }
            if self.securityApp != appName { self.securityApp = appName }
        }

        NSApp.setActivationPolicy(.regular)

        if !hasPrivileges() {
            requestAccessibilityPermissions()
            return
        }
        
        finishApplicationSetup()
    }
}
