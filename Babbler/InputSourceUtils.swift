import Cocoa
import Carbon

@objc class InputSourceUtils: NSObject {
    static var changeCallback: (() -> Void)?
    
    static var inputSources: [TISInputSource]?
    
    static var enInputSource: TISInputSource?
    
    static var ruInputSource: TISInputSource?
    
    static func getCurrentInputSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue()
    }
    
    static func isEnglish(_ inputSource: TISInputSource?) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("U.S.") || str.contains("British") || str.contains("ABC")
    }
    
    static func isRussian(_ inputSource: TISInputSource?) -> Bool {
        let str = String(describing: inputSource)
        return str.contains("Russian")
    }
    
    static func swapLang() {
        guard let lang = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else { return }
        var err: OSStatus
        
        if isRussian(lang) {
            err = TISSelectInputSource(InputSourceUtils.enInputSource)
        } else {
            err = TISSelectInputSource(InputSourceUtils.ruInputSource)
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

        guard let en = inputSources!.first(where: isEnglish) else {
            return "English input source not found"
        }
        enInputSource = en
        
        guard let ru = inputSources!.first(where: isRussian) else {
            return "Russian input source not found"
        }
        ruInputSource = ru
        
        return nil
    }

    @objc static func change() {
        if InputSourceUtils.changeCallback != nil {
            InputSourceUtils.changeCallback!()
        }
    }
    
    static func onKeyboardInputSourceChanged(_ callback: @escaping () -> Void) -> Void {
        InputSourceUtils.changeCallback = callback
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(InputSourceUtils.change),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
}
