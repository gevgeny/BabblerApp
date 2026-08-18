//
//  PreferenceStore.swift
//  Babbler
//
//  Created by Eugene Gluhotorenko on 6.03.21.
//  Copyright © 2021 Eugene Gluhotorenko. All rights reserved.
//

import Foundation

let appInputSourcesKey = "appInputSources"
let langSwitchKeyCodeKey = "langSwitchKeyCode"
let useSystemInputIndicatorKey = "useSystemInputIndicator"
let isTextReplaceEnabledKey = "isTextReplaceEnabled"
let clipboardHistoryEnabledKey = "clipboardHistoryEnabled"
let pinnedClipboardItemsKey = "pinnedClipboardItems"
let autoSwitchEnabledKey = "autoSwitchEnabled"
let autoSwitchExcludedAppsKey = "autoSwitchExcludedApps"
let autoSwitchIgnoredWordsKey = "autoSwitchIgnoredWords"

/// Apps where an automatic rewrite is more likely to be wrong than right.
let autoSwitchDefaultExcludedApps = [
  "com.apple.Terminal",
  "com.googlecode.iterm2",
  "dev.warp.Warp-Stable",
  "com.apple.dt.Xcode",
  "com.microsoft.VSCode",
  "com.jetbrains.intellij",
  "com.1password.1password",
]

class PreferenceStore {
    private var appInputSources: [String: [String]]
    
    init() {
        let defaults = UserDefaults.standard
        let appInputSources = defaults.dictionary(forKey: appInputSourcesKey) as? [String: [String]]
        if (appInputSources == nil) {
            self.appInputSources = [:]
            defaults.set(self.appInputSources, forKey: appInputSourcesKey)
        } else {
            self.appInputSources = appInputSources!
        }
    }
    
    func setInputSource(_ appId: String, _ inputSourceId: String, _ inputSourceName: String) {
        self.appInputSources[appId] = [inputSourceId, inputSourceName]
        UserDefaults.standard.set(self.appInputSources, forKey: appInputSourcesKey)
    }
    
    func getInputSource(_ appId: String) -> [String]? {
        let inputSource = self.appInputSources[appId]

        return inputSource
    }
    
    func resetInputSource(_ appId: String) {
        self.appInputSources[appId] = nil
        UserDefaults.standard.set(self.appInputSources, forKey: appInputSourcesKey)
    }
    
    func getAllConfiguredApps() -> [String: [String]] {
        return appInputSources
    }
    
    func getSwitchKeyCode() -> UInt16 {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: langSwitchKeyCodeKey) != nil {
            return UInt16(defaults.integer(forKey: langSwitchKeyCodeKey))
        }
        return Key.option
    }
    
    func setSwitchKeyCode(_ code: UInt16) {
        UserDefaults.standard.set(Int(code), forKey: langSwitchKeyCodeKey)
    }
    
    func getUseSystemInputIndicator() -> Bool {
        return UserDefaults.standard.bool(forKey: useSystemInputIndicatorKey)
    }
    
    func setUseSystemInputIndicator(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: useSystemInputIndicatorKey)
    }

    func getIsTextReplaceEnabled() -> Bool {
        let defaults = UserDefaults.standard
        // Default to true if never set
        if defaults.object(forKey: isTextReplaceEnabledKey) == nil { return true }
        return defaults.bool(forKey: isTextReplaceEnabledKey)
    }

    func setIsTextReplaceEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: isTextReplaceEnabledKey)
    }

    func getPinnedClipboardItems() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: pinnedClipboardItemsKey) ?? []
        return Set(array)
    }

    func setPinnedClipboardItems(_ items: Set<String>) {
        UserDefaults.standard.set(Array(items), forKey: pinnedClipboardItemsKey)
    }

    // Auto switch is opt-in: an upgrade must not silently start rewriting text.
    func getAutoSwitchEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: autoSwitchEnabledKey)
    }

    func setAutoSwitchEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: autoSwitchEnabledKey)
    }

    func getAutoSwitchExcludedApps() -> Set<String> {
        let defaults = UserDefaults.standard
        guard let stored = defaults.stringArray(forKey: autoSwitchExcludedAppsKey) else {
            return Set(autoSwitchDefaultExcludedApps)
        }
        return Set(stored)
    }

    func setAutoSwitchExcludedApps(_ apps: Set<String>) {
        UserDefaults.standard.set(Array(apps), forKey: autoSwitchExcludedAppsKey)
    }

    /// Words the user has undone twice; never auto-switched again.
    func getAutoSwitchIgnoredWords() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: autoSwitchIgnoredWordsKey) ?? []
        return Set(array)
    }

    func addAutoSwitchIgnoredWord(_ word: String) {
        var words = getAutoSwitchIgnoredWords()
        words.insert(word)
        UserDefaults.standard.set(Array(words), forKey: autoSwitchIgnoredWordsKey)
    }

    func clearAutoSwitchIgnoredWords() {
        UserDefaults.standard.removeObject(forKey: autoSwitchIgnoredWordsKey)
    }
}

let preferenceStore = PreferenceStore()
