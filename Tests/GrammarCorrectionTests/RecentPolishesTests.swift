import AppKit
import XCTest

@testable import GrammarCorrection

/// Recent Polishes: opt-in, on this Mac only, so earlier text can be found again.
final class RecentPolishesTests: XCTestCase {
  private func entry(_ index: Int) -> RecentPolish {
    RecentPolish(date: Date(timeIntervalSince1970: TimeInterval(index)), appName: "Discord", styleName: "Natural",
                 original: "pls chek \(index)", polished: "Please check \(index).")
  }

  @MainActor
  private func makeStore() -> (RecentPolishes, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID().uuidString).json")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return (RecentPolishes(fileURL: url), url)
  }

  @MainActor
  func testKeepsTheLastTwentyNewestFirstPrivatelyAndAcrossRelaunch() throws {
    let (store, url) = makeStore()
    for index in 0..<(RecentPolishes.maxEntries + 3) {
      store.add(entry(index))
    }

    XCTAssertEqual(store.entries.count, RecentPolishes.maxEntries)
    XCTAssertEqual(store.entries.first?.original, "pls chek 22")
    XCTAssertEqual(RecentPolishes(fileURL: url).entries, store.entries)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    XCTAssertEqual(permissions, 0o600, "Only the writer can read their text")

    store.clear()
    XCTAssertTrue(RecentPolishes(fileURL: url).entries.isEmpty)
  }

  @MainActor
  func testWindowShowsTheSelectedPolishAndClears() {
    let (store, _) = makeStore()
    store.add(entry(1))
    store.add(entry(2))
    let window = RecentPolishesWindow(store: store)
    window.reload()

    XCTAssertEqual(window.debugRowCount, 2)
    XCTAssertEqual(window.debugOriginal, "pls chek 2", "The newest is selected first")
    window.debugSelect(row: 1)
    XCTAssertEqual(window.debugPolished, "Please check 1.")
    window.debugClearAll()
    XCTAssertEqual(window.debugRowCount, 0)
    XCTAssertTrue(store.entries.isEmpty)
  }

  @MainActor
  func testRowTitleShowsWhenWhereAndHow() {
    let title = RecentPolishesWindow.rowTitle(entry(1), date: "Today 22:42").string
    XCTAssertEqual(title, "Today 22:42 · Discord · Natural\nPlease check 1.")
  }

  func testSettingIsOffByDefaultAndRoundTrips() throws {
    XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).keepRecentPolishes)
    var settings = Settings()
    settings.keepRecentPolishes = true
    XCTAssertTrue(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).keepRecentPolishes)
  }

  @MainActor
  func testAppKeepsPolishesOnlyWhileTurnedOn() throws {
    let notKept = try makeDelegate(Settings())
    notKept.debugRecentPolishes.clear()
    notKept.debugKeep(PolishRecord(original: "pls", polished: "please", processID: nil, style: .clarify))
    XCTAssertTrue(notKept.debugRecentPolishes.entries.isEmpty)
    XCTAssertFalse(notKept.debugRecentPolishesEnabled)

    var settings = Settings()
    settings.keepRecentPolishes = true
    let kept = try makeDelegate(settings)
    kept.debugRecentPolishes.clear()
    addTeardownBlock { kept.debugRecentPolishes.clear() }
    kept.debugKeep(PolishRecord(original: "pls", polished: "Please.", processID: nil, style: .formal))
    kept.debugKeep(PolishRecord(original: "tolong", polished: "please", processID: nil, style: .translateToEnglish))

    XCTAssertEqual(kept.debugRecentPolishes.entries.map(\.styleName), ["Translate", "Formal"])
    XCTAssertEqual(kept.debugRecentPolishes.entries.first?.appName, "Unknown app")
    XCTAssertTrue(kept.debugRecentPolishesEnabled)
  }

  @MainActor
  private func makeDelegate(_ settings: Settings) throws -> AppDelegate {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(settings)
    addTeardownBlock { try? Settings.save(Settings()) }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()
    return delegate
  }
}
