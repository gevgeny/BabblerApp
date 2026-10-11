//
//  PreferenceStore.swift
//  Babbler
//
//  Created by Eugene Gluhotorenko on 6.03.21.
//  Copyright © 2021 Eugene Gluhotorenko. All rights reserved.
//

import Foundation

let appInputSourcesKey = "appInputSources"
let lastAppInputSourcesKey = "lastAppInputSources"
let lastAppInputSourceUsedAtKey = "lastAppInputSourceUsedAt"
// Returning to an app within this window restores the language last used there; after it,
// the app's default applies. ponytail: fixed on purpose, make it a setting only if users ask
let appInputSourceMemorySeconds: Double = 3 * 60
let globeActionKeyEnabledKey = "globeActionKeyEnabled"
let langSwitchKeyCodeKey = "langSwitchKeyCode"
let useSystemInputIndicatorKey = "useSystemInputIndicator"  // legacy, migrated to menuBarIconStyleKey
let menuBarIconStyleKey = "menuBarIconStyle"
let isTextReplaceEnabledKey = "isTextReplaceEnabled"
let clipboardHistoryEnabledKey = "clipboardHistoryEnabled"
let pinnedClipboardItemsKey = "pinnedClipboardItems"

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case appIcon, langCode, flag
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flag: "Flag"
        case .langCode: "Language code"
        case .appIcon: "Babbler icon"
        }
    }
}

class PreferenceStore {
    private let defaults: UserDefaults
    private var appInputSources: [String: [String]]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        defaults.set(self.appInputSources, forKey: appInputSourcesKey)
    }
    
    func getInputSource(_ appId: String) -> [String]? {
        let inputSource = self.appInputSources[appId]

        return inputSource
    }
    
    func rememberInputSource(_ sourceId: String, for appId: String, now: Date = Date()) {
      var remembered = defaults.dictionary(forKey: lastAppInputSourcesKey) as? [String: String] ?? [:]
      var usedAt = defaults.dictionary(forKey: lastAppInputSourceUsedAtKey) as? [String: Double] ?? [:]
      // Refresh the timestamp even when the language did not change. On app
      // departure this starts the timeout from when the user stopped using it.
      remembered[appId] = sourceId
      usedAt[appId] = now.timeIntervalSince1970
      defaults.set(remembered, forKey: lastAppInputSourcesKey)
      defaults.set(usedAt, forKey: lastAppInputSourceUsedAtKey)
    }

    func inputSourceForActivation(_ appId: String, availableSourceIds: Set<String>, now: Date = Date()) -> String? {
      if var remembered = defaults.dictionary(forKey: lastAppInputSourcesKey) as? [String: String],
         let sourceId = remembered[appId] {
        var usedAt = defaults.dictionary(forKey: lastAppInputSourceUsedAtKey) as? [String: Double] ?? [:]
        if let timestamp = usedAt[appId] {
          let age = now.timeIntervalSince1970 - timestamp
          if age >= 0 && age < appInputSourceMemorySeconds && availableSourceIds.contains(sourceId) {
            return sourceId
          }
        }
        // Expired entries and entries without timestamps must not return later,
        // e.g. once a disabled layout is re-enabled.
        remembered[appId] = nil
        usedAt[appId] = nil
        defaults.set(remembered, forKey: lastAppInputSourcesKey)
        defaults.set(usedAt, forKey: lastAppInputSourceUsedAtKey)
      }
      guard let sourceId = appInputSources[appId]?.first,
            availableSourceIds.contains(sourceId) else { return nil }
      return sourceId
    }

    func resetInputSource(_ appId: String) {
        self.appInputSources[appId] = nil
        defaults.set(self.appInputSources, forKey: appInputSourcesKey)
    }
    
    func getAllConfiguredApps() -> [String: [String]] {
        return appInputSources
    }
    
    func getSwitchKeyCode() -> UInt16 {
        if defaults.object(forKey: langSwitchKeyCodeKey) != nil {
            return UInt16(defaults.integer(forKey: langSwitchKeyCodeKey))
        }
        return Key.option
    }
    
    func setSwitchKeyCode(_ code: UInt16) {
        defaults.set(Int(code), forKey: langSwitchKeyCodeKey)
    }
    
    // The on/off "contrast input indicator" became a 3-way menu bar icon style; convert it once
    func migrateMenuBarIconStyle() {
        guard defaults.object(forKey: menuBarIconStyleKey) == nil,
              defaults.object(forKey: useSystemInputIndicatorKey) != nil else { return }
        let style: MenuBarIconStyle = defaults.bool(forKey: useSystemInputIndicatorKey) ? .langCode : .flag
        defaults.set(style.rawValue, forKey: menuBarIconStyleKey)
        defaults.removeObject(forKey: useSystemInputIndicatorKey)
    }

    func getIsTextReplaceEnabled() -> Bool {
        // Default to true if never set
        if defaults.object(forKey: isTextReplaceEnabledKey) == nil { return true }
        return defaults.bool(forKey: isTextReplaceEnabledKey)
    }

    func setIsTextReplaceEnabled(_ value: Bool) {
        defaults.set(value, forKey: isTextReplaceEnabledKey)
    }

    func getPinnedClipboardItems() -> Set<String> {
        let array = defaults.stringArray(forKey: pinnedClipboardItemsKey) ?? []
        return Set(array)
    }

    func setPinnedClipboardItems(_ items: Set<String>) {
        defaults.set(Array(items), forKey: pinnedClipboardItemsKey)
    }
}

let preferenceStore = PreferenceStore()
