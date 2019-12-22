//
//  LanguageUtils.swift
//  Babbler
//
//  Created by Eugene Gluhotorenko on 12/21/19.
//  Copyright © 2019 Eugene Gluhotorenko. All rights reserved.
//

import Cocoa
import Carbon

@objc class LanguageUtils: NSObject {
    static var changeCallback: (() -> Void)?
    
    static var inputSources: [TISInputSource]?
    
    static var enInputSource: TISInputSource?
    
    static var ruInputSource: TISInputSource?
    
    static func getCurrentLanguage() -> TISInputSource {
        return TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
    }
    
    static func isEnglish(_ inputSource: TISInputSource?) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("U.S.") || str.contains("British")
    }
    
    static func isRussian(_ inputSource: TISInputSource?) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("Russian")
    }
    
    static func swapLang() {
        let lang = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
        
        if isRussian(lang) {
            TISSelectInputSource(LanguageUtils.enInputSource)
        } else {
            TISSelectInputSource(LanguageUtils.ruInputSource)
        }
    }
    
    static func switchLang(_ langName: String) {
        let inputSource = inputSources!.first { $0.name == langName }
        
        TISSelectInputSource(inputSource!)
    }
    
    static func fetchInputSources() -> String? {
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        inputSources = inputSourceList.filter {
            $0.category == TISInputSource.Category.keyboardInputSource && $0.isSelectable
        }
        
        guard let en = inputSources!.first(where: isEnglish) else {
            return "English input source not found"
        }
        enInputSource = en
        
        guard let ru = inputSources!.first(where: isRussian) else {
            return "Russian input source not found"
        }
        ruInputSource = ru
        
        print(enInputSource!.name)
        
        return nil
    }
    
    @objc static func change() {
        if LanguageUtils.changeCallback != nil {
            LanguageUtils.changeCallback!()
        }
    }
    
    static func onLanguageChange(_ callback: @escaping () -> Void) -> Void {
        LanguageUtils.changeCallback = callback
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(LanguageUtils.change),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc class func onItemSelect() {
        print("sender")
    }
    
    static func addInputSourceMenuItems(_ menu: NSMenu) -> Void {
//        menu.addItem(
//            withTitle: "inputSource.name",
//            action: #selector(LanguageUtils.change),
//            keyEquivalent: ""
//        )
        
        for inputSource in inputSources! {
//            let item = NSMenuItem(
//                title: inputSource.name,
//                action: #selector(LanguageUtils.onItemSelect),
//                keyEquivalent: ""
//            )
            //item.identifier = NSUserInterfaceItemIdentifier(rawValue: inputSource.id)
//            item.state = NSControl.StateValue.on
            //item.image = NSImage(iconRef: inputSource.iconRef!)
            //item.image?.size = NSMakeSize(16.0, 16.0)
            //item.isEnabled = true
            menu.addItem(withTitle: inputSource.name, action: Selector(("onItemSelect")), keyEquivalent: "")
        }
//        menu.addItem(NSMenuItem.separator())
    }
}
