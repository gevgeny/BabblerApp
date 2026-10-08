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
    
    // The on/off "contrast input indicator" became a 3-way menu bar icon style; convert it once
    func migrateMenuBarIconStyle() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: menuBarIconStyleKey) == nil,
              defaults.object(forKey: useSystemInputIndicatorKey) != nil else { return }
        let style: MenuBarIconStyle = defaults.bool(forKey: useSystemInputIndicatorKey) ? .langCode : .flag
        defaults.set(style.rawValue, forKey: menuBarIconStyleKey)
        defaults.removeObject(forKey: useSystemInputIndicatorKey)
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
}

let preferenceStore = PreferenceStore()
