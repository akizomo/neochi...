import XCTest
@testable import NeochiCore

final class BedtimeWindowTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testMinuteSinceNoonHandlesMidnight() {
        XCTAssertEqual(BedtimeWindow.minuteSinceNoon(date(2026, 11, 12, 22, 40), calendar: cal), 640)
        XCTAssertEqual(BedtimeWindow.minuteSinceNoon(date(2026, 11, 13, 1, 10), calendar: cal), 790)
        XCTAssertEqual(BedtimeWindow.minuteSinceNoon(date(2026, 11, 12, 12, 0), calendar: cal), 0)
    }

    // 午前に始めた再生は、前の日の晩に数える。2026-11-14 は土曜
    func testWeekendNightsUseThePreviousEveningAfterMidnight() {
        XCTAssertTrue(BedtimeWindow.isWeekendNight(date(2026, 11, 13, 22, 30), calendar: cal))   // 金曜の晩
        XCTAssertTrue(BedtimeWindow.isWeekendNight(date(2026, 11, 14, 0, 30), calendar: cal))    // 金曜の晩(日付は土曜)
        XCTAssertFalse(BedtimeWindow.isWeekendNight(date(2026, 11, 12, 22, 30), calendar: cal))  // 木曜の晩
    }

    // 記録から幅を決める: 下位1割の60分前から、上位1割の90分後まで
    func testWindowFromRecords() {
        let times = [(22, 20), (22, 30), (22, 40), (22, 45), (22, 50), (23, 0), (23, 10), (23, 20), (23, 30), (23, 40)]
        let starts = times.enumerated().map { date(2026, 11, 2 + $0.offset % 4, $0.element.0, $0.element.1) } // 月〜木の晩
        let w = BedtimeWindow.make(starts: starts, weekendNight: false, calendar: cal)
        XCTAssertNotNil(w)
        let sorted = times.map { $0.0 * 60 + $0.1 - 720 }.sorted()
        XCTAssertEqual(w?.lower, sorted[0] - 60)       // 22:20 の60分前 = 21:20
        XCTAssertEqual(w?.upper, sorted[9] + 90)       // 23:40 の90分後 = 01:10
    }

    func testContainsAcrossMidnight() throws {
        let w = BedtimeWindow(lower: 560, upper: 790)   // 21:20 〜 01:10
        XCTAssertTrue(w.contains(date(2026, 11, 12, 22, 40), calendar: cal))
        XCTAssertTrue(w.contains(date(2026, 11, 13, 1, 0), calendar: cal))
        XCTAssertFalse(w.contains(date(2026, 11, 12, 14, 0), calendar: cal))
        XCTAssertFalse(w.contains(date(2026, 11, 13, 7, 0), calendar: cal))
    }

    // 記録が足りないうちは、初回に聞いた就寝時刻の前後。なければ nil(昼の画面)
    func testFallbackAndNil() {
        let w = BedtimeWindow.make(starts: [], weekendNight: false, calendar: cal, fallback: date(2026, 11, 12, 23, 0))
        XCTAssertEqual(w?.lower, 23 * 60 - 720 - 60)
        XCTAssertEqual(w?.upper, 23 * 60 - 720 + 90)
        XCTAssertNil(BedtimeWindow.make(starts: [], weekendNight: false, calendar: cal))
    }

    // 平日と週末は分ける
    func testWeekdayAndWeekendAreSeparate() {
        var starts: [Date] = []
        for d in [2, 3, 4, 5, 9, 10] { starts.append(date(2026, 11, d, 22, 30)) }          // 月〜木の晩
        for d in [6, 7, 13, 14] { starts.append(date(2026, 11, d, 0 + 24 - 24 + 1, 0)) }     // 土・日の午前1時 = 金・土の晩(日付は翌日)
        let weekday = BedtimeWindow.make(starts: starts, weekendNight: false, calendar: cal)
        let weekend = BedtimeWindow.make(starts: starts, weekendNight: true, calendar: cal)
        XCTAssertNotNil(weekday)
        XCTAssertNil(weekend, "週末は4件しかなく、最低件数(5)に満たない")
    }
}
