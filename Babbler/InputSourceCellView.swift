import Cocoa
import Carbon

class InputSourceCellView: NSTableCellView {
    
    var appPath: String?
    
    @IBOutlet weak var popup: NSPopUpButton?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)!
    }
    
    @objc func resetInputLanguage(_ targetMenuItem: NSMenuItem) {
        let appPath = targetMenuItem.representedObject as! String
        
        preferenceStore.resetInputSource(appPath)
    }
    
    @objc func setInputLanguage(_ targetMenuItem: NSMenuItem) {
        let data = targetMenuItem.representedObject as! (appPath: String, inputSource: TISInputSource)
        print(data.appPath)
        preferenceStore.setInputSource(data.appPath, data.inputSource.name)
    }
    
    func initInputOptions(_ appPath: String) {
        self.appPath = appPath
        
        let selectedLangInput = preferenceStore.appInputSources[appPath]
        let menu = self.popup!.menu!
        
        let item = NSMenuItem(
            title: "(not set)",
            action: #selector(resetInputLanguage),
            keyEquivalent: ""
        )
        item.attributedTitle = NSAttributedString(string: "(not set)", attributes: [NSAttributedString.Key.foregroundColor: NSColor.gray])
        item.target = self
        item.representedObject = appPath
        
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
            item.representedObject = (appPath: appPath, inputSource: inputSource)
            item.target = self
            
            item.image = NSImage(iconRef: inputSource.iconRef!)
            item.image!.size = NSMakeSize(16.0, 16.0)
            
            menu.addItem(item)
            if (selectedLangInput == inputSource.name) {
                menu.performActionForItem(at: menu.index(of: item))
            }
        }
    }
}
