//
//  PreferenceStore.swift
//  Babbler
//
//  Created by Eugene Gluhotorenko on 6.03.21.
//  Copyright © 2021 Eugene Gluhotorenko. All rights reserved.
//

import Foundation

let appInputSourcesKey = "appInputSources"

class PreferenceStore {
    var appInputSources: [String: String]
    
    init() {
        let defaults = UserDefaults.standard
        let appInputSources = defaults.dictionary(forKey: appInputSourcesKey) as? [String: String]
        if (appInputSources == nil) {
            self.appInputSources = [:]
            defaults.set(self.appInputSources, forKey: appInputSourcesKey)
        } else {
            self.appInputSources = appInputSources!
        }
    }
    
    func setInputSource(_ appId: String, _ inputSourceName: String) {
        self.appInputSources[appId] = inputSourceName
        UserDefaults.standard.set(self.appInputSources, forKey: appInputSourcesKey)
    }
    
    func resetInputSource(_ appId: String) {
        self.appInputSources[appId] = nil
        UserDefaults.standard.set(self.appInputSources, forKey: appInputSourcesKey)
    }
}

let preferenceStore = PreferenceStore()
