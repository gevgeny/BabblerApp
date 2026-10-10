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
    store.rememberInputSource("ru", for: "editor", now: start)
    defaults.set(true, forKey: rememberAppInputSourcesKey)
    assert(source("editor") == "en")
    assert(store.getAppInputSourceTimeoutMinutes() == 3)
    store.rememberInputSource("ru", for: "editor", now: start)
    store.setInputSource("browser", "en", "English")
    assert(source("editor", after: 179) == "ru")
    assert(source("browser") == "en")
    let restarted = PreferenceStore(defaults: defaults)
    assert(restarted.inputSourceForActivation("editor", availableSourceIds: available,
                                             now: start.addingTimeInterval(179)) == "ru")
    assert(source("editor", after: 180) == "en")
    defaults.set(5, forKey: appInputSourceTimeoutMinutesKey)
    assert(source("editor", after: 181) == "en") // Expired entries cannot be resurrected.
    for minutes in [1, 3, 5, 10, 15] {
      defaults.set(minutes, forKey: appInputSourceTimeoutMinutesKey)
      store.rememberInputSource("ru", for: "editor", now: start)
      assert(source("editor", after: Double(minutes * 60) - 1) == "ru")
      assert(source("editor", after: Double(minutes * 60)) == "en")
    }
    // Returning repeatedly without changing language refreshes the departure time.
    defaults.set(1, forKey: appInputSourceTimeoutMinutesKey)
    store.rememberInputSource("ru", for: "editor", now: start)
    store.rememberInputSource("ru", for: "editor", now: start.addingTimeInterval(50))
    assert(source("editor", after: 109) == "ru")
    assert(source("editor", after: 110) == "en")
    store.rememberInputSource("ru", for: "unconfigured", now: start)
    assert(source("unconfigured", after: 59) == "ru")
    assert(source("unconfigured", after: 60) == nil)
    store.rememberInputSource("ru", for: "editor", now: start)
    assert(store.inputSourceForActivation("editor", availableSourceIds: ["en"], now: start) == "en")
    store.rememberInputSource("ru", for: "editor", now: start)
    defaults.set(false, forKey: rememberAppInputSourcesKey)
    assert(source("editor") == "en")
    assert(source("unconfigured") == nil)
    // Legacy language entries without timestamps expire on their first activation.
    defaults.set(true, forKey: rememberAppInputSourcesKey)
    defaults.set(["editor": "ru"], forKey: lastAppInputSourcesKey)
    defaults.removeObject(forKey: lastAppInputSourceUsedAtKey)
    assert(source("editor") == "en")
    defaults.set(-1, forKey: appInputSourceTimeoutMinutesKey)
    assert(store.getAppInputSourceTimeoutMinutes() == 1)
    // Legacy choices use the next supported duration rather than resetting sooner.
    for (saved, expected) in [(2, 3), (4, 5), (99, 15)] {
      defaults.set(saved, forKey: appInputSourceTimeoutMinutesKey)
      assert(store.getAppInputSourceTimeoutMinutes() == expected)
    }
    store.rememberInputSource("ru", for: "editor", now: start)
    assert(source("editor", after: -1) == "en") // Reject timestamps in the future after a clock change.
    defaults.set(appInputSourceTimeoutNever, forKey: appInputSourceTimeoutMinutesKey)
    assert(store.getAppInputSourceTimeoutMinutes() == 0)
    store.rememberInputSource("ru", for: "editor", now: start)
    let farFuture = start.addingTimeInterval(100 * 365 * 24 * 60 * 60)
    assert(store.inputSourceForActivation("editor", availableSourceIds: available, now: farFuture) == "ru")
    assert(PreferenceStore(defaults: defaults).inputSourceForActivation(
      "editor", availableSourceIds: available, now: farFuture) == "ru")
    // Without a timeout, timestamps are unnecessary, but the layout must still be available.
    defaults.removeObject(forKey: lastAppInputSourceUsedAtKey)
    assert(store.inputSourceForActivation("editor", availableSourceIds: available, now: farFuture) == "ru")
    assert(store.inputSourceForActivation("editor", availableSourceIds: ["en"], now: farFuture) == "en")
    store.rememberInputSource("ru", for: "unconfigured", now: start)
    assert(store.inputSourceForActivation("unconfigured", availableSourceIds: available, now: farFuture) == "ru")
    defaults.set(false, forKey: rememberAppInputSourcesKey)
    assert(source("editor") == "en")
    assert(source("unconfigured") == nil)
    // Invalid stored data must not silently disable the timeout.
    defaults.set("invalid", forKey: appInputSourceTimeoutMinutesKey)
    assert(store.getAppInputSourceTimeoutMinutes() == defaultAppInputSourceTimeoutMinutes)
    print("PreferenceStore tests passed")
  }
}
