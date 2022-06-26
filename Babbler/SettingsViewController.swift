import Cocoa


class SettingsViewController: NSViewController {

    @IBOutlet weak var tableView: NSTableView!
    
    var data: [[String: String]]?
    
    var icon: NSImage?
    
    var appList: [AppInfo]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        self.tableView.rowHeight = 40
        WorkspaceUtils.listAllApps { appList in
            self.appList = appList
            self.tableView.reloadData()
        }
    }
}

extension SettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if self.appList == nil {
            return 0
        }
        return self.appList!.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = self.appList![row]
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier(rawValue: "appColumn") {
            let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "appCell")
            let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            cellView?.textField?.stringValue = app.name
            cellView?.imageView?.image = app.icon
            return cellView
        } else {
            let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "inputSourceCell")
            let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as! InputSourceCellView
            cellView.popup!.removeAllItems()
            cellView.initInputOptions(app.id)
            return cellView
        }
    }
}
