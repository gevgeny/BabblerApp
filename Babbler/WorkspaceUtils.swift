import Cocoa

func getCurrentAppName () -> String {
    let ws = NSWorkspace.shared
    let frontApp = ws.frontmostApplication
    return frontApp?.localizedName ?? ""
}

typealias AppInfo = (name: String, id: String, icon: NSImage)

@objc class WorkspaceUtils: NSObject {
    
    static private var lastActiveAppName = getCurrentAppName();
    
    static private var listAllAppsCallback: ((_ apps: [AppInfo]) -> Void)?
    
    static private var onActiveAppChangedHandler: ((_ app: NSRunningApplication) -> Void)?
    
    static func checkCurrentApp() -> Bool {
        let currentActiveAppName = getCurrentAppName()
        if lastActiveAppName != currentActiveAppName {
            lastActiveAppName = currentActiveAppName
            return true
        }
        return false
    }
    
    static private var query: NSMetadataQuery? {
        willSet {
            if let query = self.query {
                query.stop()
            }
        }
    }

    public static func listAllApps(_ callback: @escaping (_ apps: [AppInfo]) -> Void) {
        WorkspaceUtils.listAllAppsCallback = callback
        WorkspaceUtils.query = NSMetadataQuery()
        
        let predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(WorkspaceUtils.queryDidFinish(_:)),
            name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
            object: nil
        )
        WorkspaceUtils.query?.searchScopes = ["/Applications"]
        WorkspaceUtils.query?.predicate = predicate
        WorkspaceUtils.query?.start()
    }

    @objc private static func queryDidFinish(_ notification: NSNotification) {
        let query = notification.object as! NSMetadataQuery;
        
        
        let apps = query.results.map { result -> AppInfo in
            let item = result as! NSMetadataItem
            let name = item.value(forAttribute: kMDItemDisplayName as String) as! String;
            let path = item.value(forAttribute: kMDItemPath as String) as! String;
            let id = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as! String;
            let icon = NSWorkspace.shared.icon(forFile: path);
            return (name, id, icon)
        }.sorted {
            $0.name < $1.name
        }
        
        WorkspaceUtils.listAllAppsCallback!(apps)
    
    }
    
    public static func onActiveAppChanged(_ callback: @escaping (_ app: NSRunningApplication) -> Void) {
        WorkspaceUtils.onActiveAppChangedHandler = callback
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(WorkspaceUtils.appActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private static func appActivated(notification: NSNotification) {
        let info = notification.userInfo!
        let app = info[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
        WorkspaceUtils.onActiveAppChangedHandler!(app)
    }
}
