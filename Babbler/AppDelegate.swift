import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    @Published var currentLang: TISInputSource? = InputSourceUtils.getCurrentInputSource()
    @Published var isSecurityInput = false
    @Published var securityApp: String?
    @Published var hasAccessibility = AXIsProcessTrusted()

    var isWaitingForSwitch = false
    var didFinishAppSetup = false
    let clipboardHistory = ClipboardHistory()
    var permissionCheckTimer: Timer?

    // Keycodes of the current word; resets on word break (space → new char) or cancel.
    var wordRecord: [(withShift: Bool, code: UInt16)] = []
    // Keycodes since the last hard cancel (escape, enter, arrow, click, app change); spans multiple words.
    var lineRecord: [(withShift: Bool, code: UInt16)] = []
    // Snapshot of whichever record the current action fired on; consumed by onKeyboardInputSourceChanged.
    var pendingRecord: [(withShift: Bool, code: UInt16)] = []

    var text: String = ""

    func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApplication.shared.terminate(self)
    }

    func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionCheckTimer = nil
                self.hasAccessibility = true
                KeyboardUtils.addGlobalEventListener(self.handleGlobalSystemEvent)
            }
        }
    }

    func requestAccessibilityPermissions() {
        // The system prompt (re)adds Babbler to the Accessibility list, switched off, and its
        // "Open System Settings" button goes straight there — so the user only flips the switch.
        // No dialog of our own: every call shows the system one, two at once is noise
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        startPermissionPolling()
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

            replaceLog("lang changed → \(self.currentLang?.id ?? "nil") waiting=\(self.isWaitingForSwitch) pending=\(self.pendingRecord.map { $0.code })")
            if !self.isWaitingForSwitch { return }

            // Stay in waiting state until the replacement is posted, so action key taps
            // in the meantime are ignored instead of starting a second, overlapping swap
            if self.pendingRecord.count > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: keyboardDelay)
                    await KeyboardUtils.replaceTypedText(self.pendingRecord)
                    await MainActor.run { self.isWaitingForSwitch = false }
                }
            } else {
                KeyboardUtils.fetchSelectedText { text in
                    if text.count > 0 { KeyboardUtils.typeText(text) }
                    self.isWaitingForSwitch = false
                }
            }
        }

        WorkspaceUtils.onActiveAppChanged { [weak self] app in
            self?.refreshSecureInput()
            if let appId = app.bundleIdentifier {
                let inputSource = preferenceStore.getInputSource(appId)
                if inputSource != nil {
                    InputSourceUtils.switchLang(inputSource![0])
                }
            }
        }

        currentLang = InputSourceUtils.getCurrentInputSource()
        // Everything above works without Accessibility (menu switcher, per-app sources);
        // key monitoring and text replacement need it
        if hasAccessibility {
            KeyboardUtils.addGlobalEventListener(handleGlobalSystemEvent)
        } else {
            requestAccessibilityPermissions()
        }
        if UserDefaults.standard.object(forKey: clipboardHistoryEnabledKey) == nil || UserDefaults.standard.bool(forKey: clipboardHistoryEnabledKey) {
            clipboardHistory.start()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    func refreshSecureInput() {
        let (isEnabled, appName) = SecurityInputUtils.checkSecureInput()
        if isSecurityInput != isEnabled { isSecurityInput = isEnabled }
        if securityApp != appName { securityApp = appName }
    }

    func handleGlobalSystemEvent(_ event: NSEvent) {
        replaceLog("event \(event.type == .flagsChanged ? "flags" : event.type == .keyDown ? "down" : event.type == .keyUp ? "up" : "mouse") code=\(event.type == .leftMouseDown ? 0 : event.keyCode) chars=\(event.type == .keyDown ? event.characters ?? "" : "") flags=\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue) waiting=\(isWaitingForSwitch) synthetic=\(KeyboardUtils.isSynthetic(event))")
        // Our own replacement keystrokes leave the records unchanged: same keycodes deleted and retyped
        if isWaitingForSwitch || KeyboardUtils.isSynthetic(event) { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isLeftMouseDown = event.type == .leftMouseDown
        let code = isLeftMouseDown ? 0 : event.keyCode

        let withOption = flags == .option
        let withCommand = flags == .command
        let withShift = flags == .shift
        let withActionModifier = flags == KeyboardUtils.actionKeyFlag
        let isArrow = code == Key.leftArrow || code == Key.rightArrow || code == Key.upArrow || code == Key.downArrow
        let isEnter = code == Key.enter || code == Key.returnKey
        let isDelete = code == Key.delete
        let isRecordCanceled = code == Key.escape || code == Key.tab || isArrow || isEnter || isLeftMouseDown

        // checkActionKeyPress is stateful — call once only
        let actionResult = KeyboardUtils.checkActionKeyPress(code, flags)

        // Cached value is polled every 10 s, so refresh live: on action key (never block a swap),
        // on click (focus may move into or out of a secure field) and while secure
        // (first keystroke after secure input ends must be recorded, not dropped)
        if actionResult != .none || isLeftMouseDown || isSecurityInput {
            refreshSecureInput()
        }

        if actionResult != .none {
            replaceLog("ACTION \(actionResult) word='\(text)' wordCodes=\(wordRecord.map { $0.code }) lineCodes=\(lineRecord.map { $0.code }) lang=\(currentLang?.id ?? "nil")")
        }

        switch actionResult {
        case .action:
            if preferenceStore.getIsTextReplaceEnabled() && !isSecurityInput {
                self.pendingRecord = self.wordRecord
                self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .lineAction:
            if preferenceStore.getIsTextReplaceEnabled() && !isSecurityInput {
//              print("\n\nlineRecord:", self.lineRecord.map { $0.code},
//                    "\npending record:", self.pendingRecord.map { $0.code},
//                    "\nword record: ", self.wordRecord.map { $0.code},
//                    "\ntext: ", self.text
//              );
              self.pendingRecord = self.lineRecord
              self.isWaitingForSwitch = true
            }
            InputSourceUtils.swapLang()
            return
        case .none:
            break
        }

        if isSecurityInput { return }

        // flagsChanged events (modifier key presses/releases) are fully handled by
        // checkActionKeyPress above. If we let them fall through, releasing Shift while
        // Option is still held would look like "Option + non-Option key" and wipe the records.
        if event.type == .flagsChanged { return }

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

        SecurityInputUtils.listenForSecurityInput { [weak self] _, _ in
            self?.refreshSecureInput()
        }

        finishApplicationSetup()
    }
}
