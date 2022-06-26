import Cocoa
import Carbon

class InputSourceCellView: NSTableCellView {
    
    var appId: String?
    
    @IBOutlet weak var popup: NSPopUpButton?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)!
    }
    
    @objc func resetInputLanguage(_ targetMenuItem: NSMenuItem) {
        let appId = targetMenuItem.representedObject as! String
        
        preferenceStore.resetInputSource(appId)
    }
    
    @objc func setInputLanguage(_ targetMenuItem: NSMenuItem) {
        let data = targetMenuItem.representedObject as! (appId: String, inputSource: TISInputSource)
        preferenceStore.setInputSource(data.appId, data.inputSource.id, data.inputSource.name)
    }
    
    func initInputOptions(_ appId: String) {
        self.appId = appId
        
        let selectedLangInput = preferenceStore.getInputSource(appId)
        print("appId", appId, selectedLangInput)
        let menu = self.popup!.menu!
        
        let item = NSMenuItem(
            title: "(not set)",
            action: #selector(resetInputLanguage),
            keyEquivalent: ""
        )
        item.attributedTitle = NSAttributedString(string: "(not set)", attributes: [NSAttributedString.Key.foregroundColor: NSColor.gray])
        item.target = self
        item.representedObject = appId
        
        menu.addItem(item)
        if (selectedLangInput == nil) {
            menu.performActionForItem(at: menu.index(of: item))
        }
        LanguageUtils.inputSources?.forEach { inputSource in
            let item = NSMenuItem(
                title: inputSource.name,
                action: #selector(setInputLanguage),
                keyEquivalent: ""
            )
            item.representedObject = (appId: appId, inputSource: inputSource)
            item.target = self
            
            item.image = NSImage(iconRef: inputSource.iconRef!)
            item.image!.size = NSMakeSize(16.0, 16.0)
            
            menu.addItem(item)
            if (selectedLangInput?[0] == inputSource.id) {
                menu.performActionForItem(at: menu.index(of: item))
            }
        }
    }
}
