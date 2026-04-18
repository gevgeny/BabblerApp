import Foundation

private func handleUncaughtException(_ exception: NSException) {
    let info = """
    Date: \(ISO8601DateFormatter().string(from: Date()))
    App Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")
    
    Uncaught Exception:
    Name: \(exception.name.rawValue)
    Reason: \(exception.reason ?? "unknown")
    
    Stack Trace:
    \(exception.callStackSymbols.joined(separator: "\n"))
    """
    CrashLogger.writeCrashLog(info)
}

private func handleSignal(_ sig: Int32) {
    let symbols = Thread.callStackSymbols
    let info = """
    Date: \(ISO8601DateFormatter().string(from: Date()))
    App Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")
    
    Signal: \(sig) (\(CrashLogger.signalName(sig)))
    
    Stack Trace:
    \(symbols.joined(separator: "\n"))
    """
    CrashLogger.writeCrashLog(info)
    
    // Re-raise so the OS default handler runs
    Darwin.signal(sig, SIG_DFL)
    Darwin.raise(sig)
}

enum CrashLogger {

    static let crashDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Babbler/Crashes", isDirectory: true)
    }()

    static let errorLogURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Babbler/error.log")
    }()

    /// Write a timestamped error message to the persistent error log.
    /// Use this for real errors only — debug output should use print() instead.
    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: errorLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: errorLogURL, options: .atomic)
        }
    }
    
    static func install() {
        try? FileManager.default.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
        
        NSSetUncaughtExceptionHandler(handleUncaughtException)
        
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE, SIGILL]
        for sig in signals {
            signal(sig, handleSignal)
        }
    }
    
    fileprivate static func writeCrashLog(_ content: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "crash-\(formatter.string(from: Date())).log"
        let fileURL = crashDirectory.appendingPathComponent(filename)
        
        guard let data = content.data(using: .utf8) else { return }
        FileManager.default.createFile(atPath: fileURL.path, contents: data)
    }
    
    fileprivate static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        case SIGFPE:  return "SIGFPE"
        case SIGILL:  return "SIGILL"
        default:      return "UNKNOWN"
        }
    }
}
