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
let autoSwitchRejectionsKey = "autoSwitchRejections"
let autoSwitchRejectionsMigratedKey = "autoSwitchRejectionsMigrated"

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

class PreferenceStore: AutoSwitchMemoryStore {
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

    /// Legacy storage: words blocked before rejection counts existed. Read once
    /// by AutoSwitchMemory's migration and then left alone, so downgrading to an
    /// earlier version does not lose them.
    func getAutoSwitchIgnoredWords() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: autoSwitchIgnoredWordsKey) ?? []
        return Set(array)
    }

    func clearAutoSwitchIgnoredWords() {
        UserDefaults.standard.removeObject(forKey: autoSwitchIgnoredWordsKey)
    }

    /// Rejection counts per word, with the date each was last reinforced.
    /// Stored as [word: [count, lastSeen]] because UserDefaults only takes
    /// property-list types.
    func getAutoSwitchRejections() -> [String: AutoSwitchMemory.Entry] {
        guard let raw = UserDefaults.standard.dictionary(forKey: autoSwitchRejectionsKey) else {
            return [:]
        }
        var entries: [String: AutoSwitchMemory.Entry] = [:]
        for (word, value) in raw {
            guard let pair = value as? [Double], pair.count == 2 else { continue }
            entries[word] = AutoSwitchMemory.Entry(
                count: Int(pair[0]),
                lastSeen: Date(timeIntervalSince1970: pair[1])
            )
        }
        return entries
    }

    func setAutoSwitchRejections(_ entries: [String: AutoSwitchMemory.Entry]) {
        let raw = entries.mapValues { [Double($0.count), $0.lastSeen.timeIntervalSince1970] }
        UserDefaults.standard.set(raw, forKey: autoSwitchRejectionsKey)
    }

    func didMigrateAutoSwitchRejections() -> Bool {
        UserDefaults.standard.bool(forKey: autoSwitchRejectionsMigratedKey)
    }

    func setDidMigrateAutoSwitchRejections(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: autoSwitchRejectionsMigratedKey)
    }
}

let preferenceStore = PreferenceStore()

/// Shared alongside `preferenceStore`: Settings and AppDelegate both need it,
/// and it owns persisted state that must not be duplicated. Declared here rather
/// than in AutoSwitchMemory.swift so that file stays free of app globals and can
/// be compiled on its own by tests/run.sh.
let autoSwitchMemory = AutoSwitchMemory(store: preferenceStore)
