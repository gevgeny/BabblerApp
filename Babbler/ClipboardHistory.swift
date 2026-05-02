import AppKit

/// Monitors the system clipboard and maintains an in-memory history of plain-text values.
/// Polling interval is 0.5 s; only fires when NSPasteboard.changeCount actually increments.
class ClipboardHistory: ObservableObject {

  /// Ordered history — most recent item first. Pinned items are sorted to the top.
  @Published private(set) var items: [String] = []

  /// Texts that are pinned — they stay at the top and survive the maxItems cap.
  @Published private(set) var pinnedItems: Set<String> = []

  var maxItems: Int

  private var timer: Timer?
  private var lastChangeCount = NSPasteboard.general.changeCount

  init(maxItems: Int = 20) {
    self.maxItems = maxItems
  }

  // MARK: - Lifecycle

  func start() {
    guard timer == nil else { return }
    lastChangeCount = NSPasteboard.general.changeCount
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.poll()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  // MARK: - Public API

  /// Copies the item at `index` to the clipboard, moves it to the top of the history,
  /// and updates `lastChangeCount` so the next poll doesn't re-add it as a new entry.
  func select(at index: Int) {
    guard items.indices.contains(index) else { return }

    let text = items.remove(at: index)
    items.insert(text, at: 0)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    // Sync changeCount so the poll loop doesn't treat this write as a new external change
    lastChangeCount = NSPasteboard.general.changeCount
  }

  /// Toggles the pin state of the item at `index`.
  /// Pinned items are sorted to the front and are exempt from the maxItems cap.
  func pin(at index: Int) {
    guard items.indices.contains(index) else { return }
    let text = items[index]
    if pinnedItems.contains(text) {
      pinnedItems.remove(text)
    } else {
      pinnedItems.insert(text)
    }
    reorder()
  }

  /// Removes the item at `index` from the history.
  func remove(at index: Int) {
    guard items.indices.contains(index) else { return }
    pinnedItems.remove(items[index])
    items.remove(at: index)
  }

  // MARK: - Private

  private func poll() {
    let current = NSPasteboard.general.changeCount
    guard current != lastChangeCount else { return }
    lastChangeCount = current

    guard
      let text = NSPasteboard.general.string(forType: .string),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }

    // Already at the top — nothing to do
    if items.first == text { return }

    // Remove any existing duplicate further down, then prepend
    items.removeAll { $0 == text }
    items.insert(text, at: 0)

    reorder()
  }

  /// Sorts pinned items to the front, then trims unpinned overflow.
  private func reorder() {
    let pinned = items.filter { pinnedItems.contains($0) }
    var unpinned = items.filter { !pinnedItems.contains($0) }
    if unpinned.count > maxItems {
      unpinned.removeLast(unpinned.count - maxItems)
    }
    items = pinned + unpinned
  }
}
