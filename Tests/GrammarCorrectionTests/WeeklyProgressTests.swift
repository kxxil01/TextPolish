import AppKit
import XCTest

@testable import GrammarCorrection

/// Recent Lessons shows this week's progress: messages, changes per message, and the most repeated change.
final class WeeklyProgressTests: XCTestCase {
  private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: value)!
  }

  private func changes(_ lines: [String], at date: Date) -> [RepeatedMistake] {
    lines.compactMap { RepeatedMistake(line: $0, at: date) }
  }

  func testComparesChangesPerMessageWithLastWeek() {
    var progress = WeeklyProgress()
    let lastWeek = date("2026-10-14 10:00")
    let thisWeek = date("2026-10-21 10:00")
    progress.record(changes(["a → b: x", "c → d: y", "e → f: z"], at: lastWeek), at: lastWeek)
    progress.record(changes(["needsed → needed: spelling"], at: thisWeek), at: thisWeek)
    progress.record(changes(["needsed → needed: spelling", "pls → please: spell out"], at: thisWeek), at: thisWeek)

    XCTAssertEqual(progress.summary(now: thisWeek), [
      "2 messages explained, 1.5 changes each",
      "Down from 3.0 last week. Nice work.",
      "Most repeated: needsed → needed (2 times)",
    ])
  }

  func testNothingThisWeekShowsNothingAndOneMessageReadsNaturally() {
    var progress = WeeklyProgress()
    let now = date("2026-10-21 10:00")
    XCTAssertEqual(progress.summary(now: now), [])

    progress.record(changes(["a → b: x", "c → d: y"], at: now), at: now)
    progress.record(changes(["a → b: x", "c → d: y", "e → f: z", "g → h: w"], at: date("2026-10-14 09:00")), at: date("2026-10-14 09:00"))

    XCTAssertEqual(progress.summary(now: now), ["1 message explained, 2.0 changes each", "Down from 4.0 last week. Nice work."])
  }

  func testKeepsEightWeeks() {
    var progress = WeeklyProgress()
    for week in 0..<10 {
      let day = date("2026-08-03 10:00").addingTimeInterval(TimeInterval(week) * 7 * 86_400)
      progress.record([], at: day)
    }
    XCTAssertEqual(progress.weeks.count, WeeklyProgress.weeksKept)
    XCTAssertEqual(WeeklyProgress.weekKey(date("2026-10-21 10:00")), "2026-W43")
  }

  @MainActor
  func testLessonHistoryKeepsProgressAcrossRelaunchAndClearsIt() {
    let name = "lessons-\(UUID().uuidString)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
    addTeardownBlock {
      for suffix in ["", "-mistakes", "-weeks"] {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(name)\(suffix).json"))
      }
    }
    let history = LessonHistory(fileURL: url)
    history.add(["needsed → needed: spelling"])

    XCTAssertEqual(LessonHistory(fileURL: url).progressSummary(), ["1 message explained, 1.0 changes each"])
    history.clear()
    XCTAssertEqual(LessonHistory(fileURL: url).progressSummary(), [])
  }

  @MainActor
  func testRecentLessonsShowsThisWeekFirst() {
    let text = LessonsWindow.formatted(
      [Lesson(date: Date(), lines: ["pls → please: spell out"])],
      progress: ["2 messages explained, 1.5 changes each"]
    ).string

    XCTAssertTrue(text.hasPrefix("This Week\n2 messages explained, 1.5 changes each\n"), text)
  }
}
