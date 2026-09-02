import Foundation

/// Persistence used by `AutoSwitchMemory`. A protocol so the tests can drive the
/// state machine against an in-memory fake instead of the real `UserDefaults`.
protocol AutoSwitchMemoryStore: AnyObject {
  func getAutoSwitchRejections() -> [String: AutoSwitchMemory.Entry]
  func setAutoSwitchRejections(_ entries: [String: AutoSwitchMemory.Entry])
  func getAutoSwitchIgnoredWords() -> Set<String>
  func clearAutoSwitchIgnoredWords()
  func didMigrateAutoSwitchRejections() -> Bool
  func setDidMigrateAutoSwitchRejections(_ value: Bool)
}

/// Remembers which words the user does not want corrected, and decides when a
/// gesture counts as a rejection.
///
/// Deliberately free of AppKit, timers and clocks: every input is an explicit
/// event with an explicit timestamp. The bug in v1.4 happened because logic of
/// this kind lived in `AppDelegate`, where the tests could not reach it — this
/// type has more state and more edge cases, so it is built to be driven from
/// `tests/run.sh` instead.
///
/// The rule that shapes the whole design: a manual layout revert only counts as
/// a rejection if the user did **not** edit the text. Reverting and then fixing
/// the text means the user was correcting their own mistake, which is not
/// evidence against us. Since the edit can arrive either before or after the
/// revert, a revert cannot be counted on the spot — it arms a suspicion that a
/// later edit can still cancel.
final class AutoSwitchMemory {

  /// Rejections needed before a word is left alone for good.
  static let rejectionThreshold = 3

  /// A correction is only open to rejection for this long.
  static let rejectionWindow: TimeInterval = 10

  /// After a layout revert, how long to wait for an edit that would cancel it.
  static let suspicionWindow: TimeInterval = 3

  /// Entries not reinforced within this period are forgotten. Without it, three
  /// unrelated rejections spread over a year would silently block a word
  /// forever.
  static let entryLifetime: TimeInterval = 90 * 24 * 60 * 60

  /// Upper bound on stored entries; the least recently seen are evicted.
  static let maximumEntries = 500

  struct Entry {
    var count: Int
    var lastSeen: Date
  }

  /// What we know about the most recent correction.
  private struct PendingCorrection {
    let word: String
    let at: Date
    /// The user pressed Delete after the correction, so any revert reflects
    /// them fixing their own text rather than rejecting ours.
    var wasEdited = false
    /// The layout was reverted at this time; counts once the suspicion window
    /// passes without an edit.
    var revertedAt: Date?
    /// Guards against counting one gesture twice: pressing the action key also
    /// changes the layout, so both signals fire for a single undo.
    var alreadyCounted = false
  }

  private let store: AutoSwitchMemoryStore
  private var entries: [String: Entry]
  private var pending: PendingCorrection?

  init(store: AutoSwitchMemoryStore) {
    self.store = store
    self.entries = store.getAutoSwitchRejections()
    migrateLegacyIgnoreListIfNeeded()
    pruneExpired(now: Date())
  }

  // MARK: - Queries

  /// Whether this word has been rejected often enough to be left alone.
  func shouldSkip(word: String, now: Date = Date()) -> Bool {
    guard let entry = entries[word] else { return false }
    guard now.timeIntervalSince(entry.lastSeen) <= Self.entryLifetime else { return false }
    return entry.count >= Self.rejectionThreshold
  }

  var learnedWords: [String] {
    entries
      .filter { $0.value.count >= Self.rejectionThreshold }
      .keys
      .sorted()
  }

  var learnedWordCount: Int { learnedWords.count }

  // MARK: - Events

  /// A correction was just applied to `word`.
  func noteCorrection(word: String, at now: Date = Date()) {
    settlePending(now: now)
    pending = PendingCorrection(word: word, at: now)
  }

  /// The user pressed the action key. Straight after a correction that is an
  /// unambiguous undo and counts immediately.
  func noteActionKey(at now: Date = Date()) {
    guard var correction = pending,
          now.timeIntervalSince(correction.at) <= Self.rejectionWindow,
          !correction.alreadyCounted else {
      pending = nil
      return
    }
    correction.alreadyCounted = true
    pending = correction
    recordRejection(word: correction.word, at: now)
    // Kept (not cleared) so the layout change this undo causes cannot be
    // counted a second time. settlePending drops it on the next correction.
  }

  /// The user changed the layout themselves. Arms a suspicion rather than
  /// counting, because an edit may still arrive and cancel it.
  func noteLayoutReverted(at now: Date = Date()) {
    guard var correction = pending,
          now.timeIntervalSince(correction.at) <= Self.rejectionWindow,
          !correction.alreadyCounted,
          !correction.wasEdited,
          correction.revertedAt == nil else {
      return
    }
    correction.revertedAt = now
    pending = correction
  }

  /// The user deleted something after the correction, so they are fixing their
  /// own text. Cancels an armed suspicion and blocks any later revert.
  func noteTextEdited(at now: Date = Date()) {
    guard var correction = pending,
          now.timeIntervalSince(correction.at) <= Self.rejectionWindow else {
      pending = nil
      return
    }
    correction.wasEdited = true
    correction.revertedAt = nil
    pending = correction
  }

  /// Commits or discards a pending correction whose windows have elapsed. Call
  /// on a timer and before recording a new correction.
  func settlePending(now: Date = Date()) {
    guard let correction = pending else { return }

    if let revertedAt = correction.revertedAt,
       !correction.wasEdited,
       !correction.alreadyCounted,
       now.timeIntervalSince(revertedAt) >= Self.suspicionWindow {
      recordRejection(word: correction.word, at: now)
      pending = nil
      return
    }

    if now.timeIntervalSince(correction.at) > Self.rejectionWindow,
       correction.revertedAt == nil {
      pending = nil
    }
  }

  // MARK: - Storage

  func forgetAll() {
    entries = [:]
    pending = nil
    store.setAutoSwitchRejections(entries)
    store.clearAutoSwitchIgnoredWords()
  }

  private func recordRejection(word: String, at now: Date) {
    guard !word.isEmpty else { return }
    var entry = entries[word] ?? Entry(count: 0, lastSeen: now)
    // A stale entry starts over rather than resuming an old count.
    if now.timeIntervalSince(entry.lastSeen) > Self.entryLifetime {
      entry.count = 0
    }
    entry.count += 1
    entry.lastSeen = now
    entries[word] = entry

    pruneExpired(now: now)
    evictIfNeeded()
    store.setAutoSwitchRejections(entries)
  }

  private func pruneExpired(now: Date) {
    entries = entries.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.entryLifetime }
  }

  private func evictIfNeeded() {
    guard entries.count > Self.maximumEntries else { return }
    let survivors = entries
      .sorted { $0.value.lastSeen > $1.value.lastSeen }
      .prefix(Self.maximumEntries)
    entries = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
  }

  /// Words blocked by earlier versions were stored as a plain list with no
  /// counts. Bring them across as already having reached the threshold. The old
  /// key is left in place so downgrading does not lose the data.
  private func migrateLegacyIgnoreListIfNeeded() {
    guard !store.didMigrateAutoSwitchRejections() else { return }
    let now = Date()
    for word in store.getAutoSwitchIgnoredWords() where entries[word] == nil {
      entries[word] = Entry(count: Self.rejectionThreshold, lastSeen: now)
    }
    store.setAutoSwitchRejections(entries)
    store.setDidMigrateAutoSwitchRejections(true)
  }
}
