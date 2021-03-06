import Cocoa

func getCurrentAppName () -> String {
    let ws = NSWorkspace.shared
    let frontApp = ws.frontmostApplication
    return frontApp?.localizedName ?? ""
}

typealias AppInfo = (name: String, path: String, icon: NSImage)

@objc class WorkspaceUtils: NSObject {
    
    static private var lastActiveAppName = getCurrentAppName();
    
    static private var listAllAppsCallback: ((_ apps: [AppInfo]) -> Void)?
    
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
            let icon = NSWorkspace.shared.icon(forFile: path);
            
            return (name, path, icon)
        }.sorted {
            $0.name < $1.name
        }
        
        WorkspaceUtils.listAllAppsCallback!(apps)
        

//        for result in query.results {
//            ??            guard let item = result as? NSMetadataItem else {
//                print("Result was not an NSMetadataItem, \(result)")
//                continue
//            }
//            print(item.value(forAttribute: kMDItemPath as String))
////            print(result)
//        }
    }
}
