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
        var err: OSStatus
        
        if isRussian(lang) {
            AppDelegate.print("current ru, set en")
            err = TISSelectInputSource(LanguageUtils.enInputSource)
        } else {
            AppDelegate.print("current en, set ru")
            err = TISSelectInputSource(LanguageUtils.ruInputSource)
        }
        if (err != 0) {
            AppDelegate.print("TISSelectInputSource error")
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
        AppDelegate.print(TISCopyCurrentKeyboardInputSource().takeUnretainedValue())
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
}
