import Cocoa
import Carbon

@objc class LanguageUtils: NSObject {
    static var changeCallback: (() -> Void)?
    
    static var inputSources: [TISInputSource]?
    
    static var latinInputSource: TISInputSource?

    static var cyrillicInputSource: TISInputSource?
    
    static func getCurrentInputSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue()
    }
    
    static func isLatin(_ inputSource: TISInputSource?) -> Bool {
        guard let id = inputSource?.id else { return false }
        return latinLayoutIDs.contains(id)
    }

    static func isCyrillic(_ inputSource: TISInputSource?) -> Bool {
        guard let id = inputSource?.id else { return false }
        return cyrillicLayoutIDs.contains(id)
    }
    
    static func swapLang() {
        guard let lang = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else { return }
        var err: OSStatus

        if isCyrillic(lang) {
            print("current cyrillic, set latin")
            err = TISSelectInputSource(LanguageUtils.latinInputSource)
        } else {
            print("current latin, set cyrillic")
            err = TISSelectInputSource(LanguageUtils.cyrillicInputSource)
        }
        if (err != 0) {
            print("TISSelectInputSource error")
        }
    }

    static func switchLang(_ langId: String) {
        guard let inputSource = inputSources?.first(where: { $0.id == langId }) else { return }
        TISSelectInputSource(inputSource)
    }
    
    static func initInputSources() -> String? {
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        inputSources = inputSourceList.filter {
            $0.category == TISInputSource.Category.keyboardInputSource && $0.isSelectable
        }
        
        // Remove app bindings for input sources that no longer exist
        let availableIds = Set(inputSources!.map { $0.id })
        for (appId, values) in preferenceStore.getAllConfiguredApps() {
            if values.count >= 2 && !availableIds.contains(values[0]) {
                preferenceStore.resetInputSource(appId)
            }
        }

        guard let latin = inputSources!.first(where: isLatin) else {
            return "No Latin keyboard layout found"
        }
        latinInputSource = latin

        guard let cyrillic = inputSources!.first(where: isCyrillic) else {
            return "No Cyrillic keyboard layout found"
        }
        cyrillicInputSource = cyrillic
        
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
}
