import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    @Published var currentLang: TISInputSource? = InputSourceUtils.getCurrentInputSource()
    @Published var isSecurityInput = false
    @Published var securityApp: String?

    var isWaitingForSwitch = false
    var didFinishAppSetup = false
    let clipboardHistory = ClipboardHistory()
    var permissionCheckTimer: Timer?

    // Keycodes of the current word; resets on word break (space → new char) or cancel.
    // Only .last?.code (word-break detection) and .count (delete count) are used.
    var wordRecord: [(withShift: Bool, code: UInt16)] = []
    // Keycodes since the last hard cancel (escape, enter, arrow, click, app change); spans multiple words.
    var lineRecord: [(withShift: Bool, code: UInt16)] = []

    // String mirrors of wordRecord / lineRecord — used for translation at swap time.
    var text: String = ""
    var lineText: String = ""
    // Captured at action-key press; consumed by onKeyboardInputSourceChanged.
    var pendingText: String = ""
    var pendingCount: Int = 0

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
            self.performPendingReplacement()
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
        if UserDefaults.standard.object(forKey: clipboardHistoryEnabledKey) == nil || UserDefaults.standard.bool(forKey: clipboardHistoryEnabledKey) {
            clipboardHistory.start()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Called on the main thread after the input source has switched.
    /// Performs the pending typed-word or selected-text replacement.
    func performPendingReplacement() {
        if pendingCount > 0 {
            // Translate on the main thread — TIS APIs required by translateText crash off main.
            let translatedText = KeyboardUtils.translateText(pendingText)
            let count = pendingCount
            Task {
                try? await Task.sleep(nanoseconds: keyboardDelay)
                await KeyboardUtils.replaceTypedText(translatedText, count: count)
                // Seed records with the replaced text so subsequent Alt presses can
                // convert it back. wordRecord only needs the right .count for deletion.
                // Must run on main thread — handleGlobalSystemEvent reads these properties.
                await MainActor.run {
                    let charCount = translatedText.count
                    self.text = translatedText
                    self.wordRecord = Array(repeating: (withShift: false, code: 0), count: charCount)
                    let drop = min(count, self.lineRecord.count)
                    self.lineText = String(self.lineText.dropLast(drop)) + translatedText
                    self.lineRecord = Array(self.lineRecord.dropLast(drop))
                        + Array(repeating: (withShift: false, code: 0), count: charCount)
                    self.isWaitingForSwitch = false
                }
            }
        } else {
            KeyboardUtils.fetchSelectedText { text in
                if text.count == 0 { return }
                KeyboardUtils.typeText(text)
            }
            isWaitingForSwitch = false
        }
    }

    func handleGlobalSystemEvent(_ event: NSEvent) {
        if isWaitingForSwitch { return }
        if isSecurityInput { return }
        // Ignore events we synthesized ourselves (Delete + typeText Unicode inject)
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == KeyboardUtils.syntheticEventMarker { return }

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
                self.pendingText = self.text
                self.pendingCount = self.wordRecord.count
                self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .lineAction:
            if preferenceStore.getIsTextReplaceEnabled() {
                self.pendingText = self.lineText
                self.pendingCount = self.lineRecord.count
                self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .none:
            break
        }

        // flagsChanged events (modifier key presses/releases) are fully handled by
        // checkActionKeyPress above. If we let them fall through, releasing Shift while
        // Option is still held would look like "Option + non-Option key" and wipe the records.
        if event.type == .flagsChanged { return }

        // Erase both records on cancel or when a shortcut modifier is active
        if isRecordCanceled || (withOption && code != Key.option) || withCommand || (withActionModifier && code != KeyboardUtils.actionKeyCode) {
            wordRecord = []
            lineRecord = []
            text = ""
            lineText = ""
            return
        }

        // Delete last symbol from both records
        if isDelete && wordRecord.count > 0 {
            wordRecord.removeLast()
            text = String(text.dropLast())
        }
        if isDelete && lineRecord.count > 0 {
            lineRecord.removeLast()
            lineText = String(lineText.dropLast())
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
                lineText = ""
            }
        }

        // Save pressed key to both records
        let entry = (withShift: withShift, code: event.keyCode)
        wordRecord.append(entry)
        lineRecord.append(entry)
        text += event.characters!
        lineText += event.characters!
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
