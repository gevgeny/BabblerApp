import Cocoa

func getCurrentAppName () -> String {
    let ws = NSWorkspace.shared
    let frontApp = ws.frontmostApplication
    return frontApp?.localizedName ?? ""
}

@objc class WorkspaceUtils: NSObject {
    
    static private var lastActiveAppName = getCurrentAppName();
    static func checkCurrentApp() -> Bool {
        let currentActiveAppName = getCurrentAppName()
        if lastActiveAppName != currentActiveAppName {
            lastActiveAppName = currentActiveAppName
            return true
        }
        return false
    }
}
