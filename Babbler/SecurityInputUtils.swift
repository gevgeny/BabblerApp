import Cocoa
import IOKit

class SecurityInputUtils: NSObject {

  /// Synchronous check — safe to call on main thread (IOKit direct, no subprocess).
  static func checkSecureInput() -> (isEnabled: Bool, appName: String?) {
    guard let pid = secureInputPID() else { return (false, nil) }
    let app = NSWorkspace.shared.runningApplications
      .first { $0.processIdentifier == pid }?
      .localizedName
    return (true, app)
  }

  /// Polls every 10 s and fires `callback` on main thread.
  static func listenForSecurityInput(
    _ callback: @escaping (_ isSecureInputEnabled: Bool, _ appName: String?) -> Void
  ) {
    Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
      let (isEnabled, appName) = checkSecureInput()
      callback(isEnabled, appName)
    }
  }

  // MARK: - Private

  private static func secureInputPID() -> pid_t? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(root) }

    guard
      let value = IORegistryEntryCreateCFProperty(
        root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
      ),
      let users = value.takeRetainedValue() as? [[String: Any]]
    else { return nil }

    for session in users {
      if let pid = session["kCGSSessionSecureInputPID"] as? pid_t {
        return pid
      }
    }
    return nil
  }
}
