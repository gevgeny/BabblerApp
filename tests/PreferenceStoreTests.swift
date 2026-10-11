import Foundation

@main
struct PreferenceStoreTests {
  static func main() {
    let suite = "BabblerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferenceStore(defaults: defaults)
    let available: Set<String> = ["en", "ru"]
    let start = Date(timeIntervalSince1970: 1_000_000)
    func source(_ app: String, after seconds: Double = 0) -> String? {
      store.inputSourceForActivation(app, availableSourceIds: available, now: start.addingTimeInterval(seconds))
    }
    store.setInputSource("editor", "en", "English")
    assert(source("editor") == "en")
    // Remembered language wins within the fixed 3-minute window, then the default applies.
    store.rememberInputSource("ru", for: "editor", now: start)
    store.setInputSource("browser", "en", "English")
    assert(source("editor", after: 179) == "ru")
    assert(source("browser") == "en")
    assert(source("editor", after: 180) == "en")
    assert(source("editor", after: 1) == "en") // Expired entries cannot be resurrected.
    // Returning repeatedly without changing language refreshes the departure time.
    store.rememberInputSource("ru", for: "editor", now: start)
    store.rememberInputSource("ru", for: "editor", now: start.addingTimeInterval(100))
    assert(source("editor", after: 279) == "ru")
    assert(source("editor", after: 280) == "en")
    // Apps without a default only get the remembered language back within the window.
    store.rememberInputSource("ru", for: "unconfigured", now: start)
    assert(source("unconfigured", after: 179) == "ru")
    assert(source("unconfigured", after: 180) == nil)
    // A remembered layout that is no longer available falls back to the default.
    store.rememberInputSource("ru", for: "editor", now: start)
    assert(store.inputSourceForActivation("editor", availableSourceIds: ["en"], now: start) == "en")
    store.rememberInputSource("ru", for: "editor", now: start)
    assert(source("editor", after: -1) == "en") // Reject timestamps in the future after a clock change.
    print("PreferenceStore tests passed")
  }
}
