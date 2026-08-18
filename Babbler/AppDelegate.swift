import Cocoa
import Carbon
import IOKit.hid

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    @Published var currentLang: TISInputSource? = InputSourceUtils.getCurrentInputSource()
    @Published var isSecurityInput = false
    @Published var securityApp: String?

    var isWaitingForSwitch = false
    var didFinishAppSetup = false
    let clipboardHistory = ClipboardHistory()
    var permissionCheckTimer: Timer?
    // Safety net: if the input-source-changed notification never arrives, this fires
    // so isWaitingForSwitch can never latch on and permanently disable event handling.
    var switchWatchdog: Timer?

    // Keycodes of the current word; resets on word break (space → new char) or cancel.
    var wordRecord: [(withShift: Bool, code: UInt16)] = []
    // Keycodes since the last hard cancel (escape, enter, arrow, click, app change); spans multiple words.
    var lineRecord: [(withShift: Bool, code: UInt16)] = []
    // Snapshot of whichever record the current action fired on; consumed by onKeyboardInputSourceChanged.
    var pendingRecord: [(withShift: Bool, code: UInt16)] = []

    var text: String = ""

    // Set right after an automatic correction so the next action-key press is
    // understood as "undo that", and so repeated undos of the same word teach
    // Babbler to leave it alone.
    var lastAutoSwitchWord: String?
    var lastAutoSwitchAt: Date?
    var autoSwitchUndoCounts: [String: Int] = [:]
    let autoSwitchUndoWindow: TimeInterval = 5.0

    // Accessibility lets us post synthetic keystrokes. Input Monitoring is a *separate*
    // grant that NSEvent.addGlobalMonitorForEvents needs for .keyDown/.keyUp — without it
    // the monitor silently delivers only .flagsChanged, so the action key is detected but
    // no typed word is ever recorded.
    func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    func hasInputMonitoringAccess() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func hasPrivileges() -> Bool {
        hasAccessibilityAccess() && hasInputMonitoringAccess()
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
        openPrivacySettings("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacySettings("Privacy_ListenEvent")
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
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
        // Fires the system Input Monitoring prompt if macOS has never asked before.
        if !hasInputMonitoringAccess() {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if hasPrivileges() {
            finishApplicationSetup()
            return
        }

        let needsAccessibility = !hasAccessibilityAccess()
        let needsInputMonitoring = !hasInputMonitoringAccess()

        let alert = NSAlert()
        alert.alertStyle = .warning

        if needsAccessibility && needsInputMonitoring {
            alert.messageText = "Accessibility and Input Monitoring Access Required"
            alert.informativeText = "Babbler needs two separate permissions: Input Monitoring to see the word you are typing, and Accessibility to replace it. Enable Babbler in both lists, then return to the app."
            alert.addButton(withTitle: "Open Input Monitoring")
            alert.addButton(withTitle: "Open Accessibility")
            alert.addButton(withTitle: "Quit")
        } else if needsInputMonitoring {
            alert.messageText = "Input Monitoring Access Required"
            alert.informativeText = "Babbler needs Input Monitoring access to see the word you are typing. Without it the action key is detected but the last typed word cannot be swapped. Enable Babbler in Input Monitoring, then return to the app."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
        } else {
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "Babbler needs Accessibility access to replace typed text. Click Open System Settings, enable Babbler in Accessibility, and return to the app."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
        }

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            NSApplication.shared.terminate(self)
            return
        }
        if response == .alertSecondButtonReturn && !(needsAccessibility && needsInputMonitoring) {
            NSApplication.shared.terminate(self)
            return
        }

        if needsAccessibility && needsInputMonitoring {
            if response == .alertFirstButtonReturn {
                openInputMonitoringSettings()
            } else {
                openAccessibilitySettings()
            }
        } else if needsInputMonitoring {
            openInputMonitoringSettings()
        } else {
            openAccessibilitySettings()
        }
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

        if preferenceStore.getAutoSwitchEnabled() {
            LayoutDictionary.shared.preload()
        }

        InputSourceUtils.onKeyboardInputSourceChanged {
            self.currentLang = InputSourceUtils.getCurrentInputSource()
            self.completePendingSwitch()
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

    // Performs the pending text replacement exactly once. isWaitingForSwitch stays set
    // while synthetic keystrokes are posted so they are not recorded back into wordRecord,
    // and a watchdog guarantees it is always released even if something fails.
    func completePendingSwitch() {
        switchWatchdog?.invalidate()
        switchWatchdog = nil

        if !isWaitingForSwitch { return }

        let record = pendingRecord
        pendingRecord = []

        armWatchdog(2.0) { [weak self] in self?.finishSwitch() }

        if record.count > 0 {
            Task {
                try? await Task.sleep(nanoseconds: keyboardDelay)
                await KeyboardUtils.replaceTypedText(record)
                await MainActor.run { self.finishSwitch() }
            }
        } else {
            KeyboardUtils.fetchSelectedText { text in
                if text.count > 0 { KeyboardUtils.typeText(text) }
                self.finishSwitch()
            }
        }
    }

    func finishSwitch() {
        switchWatchdog?.invalidate()
        switchWatchdog = nil
        isWaitingForSwitch = false
    }

    private func armWatchdog(_ interval: TimeInterval, _ action: @escaping () -> Void) {
        switchWatchdog?.invalidate()
        switchWatchdog = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }

    func beginSwitch(_ record: [(withShift: Bool, code: UInt16)]) {
        if preferenceStore.getIsTextReplaceEnabled() {
            pendingRecord = record
            isWaitingForSwitch = true
            // If the input-source-changed notification never arrives, replace anyway.
            armWatchdog(0.5) { [weak self] in self?.completePendingSwitch() }
        }
        InputSourceUtils.swapLang()
    }

    // MARK: - Automatic layout switch

    private var currentLayout: Layout? {
        guard let source = InputSourceUtils.getCurrentInputSource() else { return nil }
        if InputSourceUtils.isRussian(source) { return .russian }
        if InputSourceUtils.isEnglish(source) { return .english }
        return nil
    }

    private func isAutoSwitchAllowedInCurrentApp() -> Bool {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return !preferenceStore.getAutoSwitchExcludedApps().contains(bundleId)
    }

    /// A key that ends a word, so the word before it can now be judged.
    private func wordTerminator(for event: NSEvent) -> Bool {
        if event.keyCode == Key.space || event.keyCode == Key.enter || event.keyCode == Key.returnKey {
            return true
        }
        guard let characters = event.characters, characters.count == 1 else { return false }
        return ".,!?;:".contains(characters)
    }

    /// Called on the keystroke that ends a word. Returns true if it triggered a
    /// correction, in which case the caller must stop processing the event.
    private func handleAutoSwitch(_ event: NSEvent) -> Bool {
        guard preferenceStore.getAutoSwitchEnabled(),
              preferenceStore.getIsTextReplaceEnabled(),
              wordTerminator(for: event),
              !text.isEmpty,
              !wordRecord.isEmpty,
              let layout = currentLayout,
              isAutoSwitchAllowedInCurrentApp() else {
            return false
        }

        let word = AutoSwitchEngine.normalize(text)
        if preferenceStore.getAutoSwitchIgnoredWords().contains(word) { return false }
        guard AutoSwitchEngine.evaluate(word: text, currentLayout: layout) == .switchLayout else {
            return false
        }

        // The terminator has already reached the focused app, so it has to be
        // deleted and retyped along with the word. Its keycode is layout
        // independent, so replaying it is safe.
        let record = wordRecord + [(withShift: false, code: event.keyCode)]

        lastAutoSwitchWord = word
        lastAutoSwitchAt = Date()

        // Leave the corrected run in wordRecord so pressing the action key right
        // after undoes it. The next typed character clears it as usual, because
        // the record now ends with the terminator.
        wordRecord = record
        text = ""

        beginSwitch(record)
        return true
    }

    /// The action key pressed just after an automatic correction means the user
    /// disagreed. Two disagreements about the same word disable it permanently.
    private func noteManualActionForUndo() {
        guard let word = lastAutoSwitchWord,
              let at = lastAutoSwitchAt,
              Date().timeIntervalSince(at) <= autoSwitchUndoWindow else {
            lastAutoSwitchWord = nil
            lastAutoSwitchAt = nil
            return
        }

        let count = (autoSwitchUndoCounts[word] ?? 0) + 1
        autoSwitchUndoCounts[word] = count
        if count >= 2 {
            preferenceStore.addAutoSwitchIgnoredWord(word)
        }

        lastAutoSwitchWord = nil
        lastAutoSwitchAt = nil
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
            noteManualActionForUndo()
            beginSwitch(wordRecord)
            return
        case .lineAction:
            noteManualActionForUndo()
            beginSwitch(lineRecord)
            return
        case .none:
            break
        }

        // flagsChanged events (modifier key presses/releases) are fully handled by
        // checkActionKeyPress above. If we let them fall through, releasing Shift while
        // Option is still held would look like "Option + non-Option key" and wipe the records.
        if event.type == .flagsChanged { return }

        // A word just ended: judge it before the cancel/record bookkeeping below,
        // so terminators that reset the records (enter) are still covered.
        if event.type == .keyDown, !event.isARepeat, handleAutoSwitch(event) { return }

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
        text += event.characters ?? ""
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
