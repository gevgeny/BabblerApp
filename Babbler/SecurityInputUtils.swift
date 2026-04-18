//
//  SecurityInputUtils.swift
//  Babbler
//
//  Created by Eugene Gluhotorenko on 12/19/19.
//  Copyright © 2019 Eugene Gluhotorenko. All rights reserved.
//

import Cocoa
import Carbon

class SecurityInputUtils: NSObject {
    
    static func runCommand(_ command: String) -> String? {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", String(format:"%@", command)]
        task.standardOutput = pipe
        let file = pipe.fileHandleForReading
        task.launch()
        if let result = NSString(data: file.readDataToEndOfFile(), encoding: String.Encoding.utf8.rawValue) {
            return result as String
        }
        else {
            return nil
        }
    }
    static func getSecurityInputEnablerPid() -> String? {
        let output = SecurityInputUtils.runCommand("ioreg -l -w 0 | grep kCGSSessionSecureInputPID")
        
        var strings = output?.components(separatedBy: "kCGSSessionSecureInputPID\"=") ?? []
        
        if strings.count < 2 { return nil }
        strings = strings[1].components(separatedBy: ",")
        
        if strings.count < 1 { return nil }
        return strings[0]
    }
    
    static func getSecurityInputEnablerApp() -> String? {
        let pid = SecurityInputUtils.getSecurityInputEnablerPid()
        let app = NSWorkspace.shared.runningApplications.first { String($0.processIdentifier) == pid }
        
        if let name = app?.localizedName {
            return name
        }
        return nil
        
    }
    
    static func listenForSecurityInput(
        _ callback: @escaping (_ isSecureInputEnabled: Bool, _ appName: String?) -> Void
    ) -> Void {
        // Run on a background thread so the ioreg shell command never blocks the main thread.
        // Dispatch results back to main before touching any @Published properties.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                let isSecureInputEnabled = self.getSecurityInputEnablerPid() != nil
                let securityInputEnablerApp = isSecureInputEnabled ? self.getSecurityInputEnablerApp() : nil
                DispatchQueue.main.async {
                    callback(isSecureInputEnabled, securityInputEnablerApp)
                }
            }
        }
    }
}
