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

    // いまが時間帯の中か。初回に聞いた 23:00 なら、22:00〜翌0:30
    func testIsInWindowWithFallback() {
        let f = date(2026, 11, 12, 23, 0)
        func inside(_ d: Date) -> Bool { BedtimeWindow.isInWindow(now: d, starts: [], fallback: f, calendar: cal) }
        XCTAssertTrue(inside(date(2026, 11, 12, 22, 30)))
        XCTAssertTrue(inside(date(2026, 11, 13, 0, 20)))
        XCTAssertFalse(inside(date(2026, 11, 13, 0, 40)))
        XCTAssertFalse(inside(date(2026, 11, 12, 14, 0)))
        XCTAssertFalse(inside(date(2026, 11, 13, 7, 0)))
    }

    // 記録も初回の時刻もなければ、いつでも昼の画面
    func testIsInWindowWithoutAnyData() {
        XCTAssertFalse(BedtimeWindow.isInWindow(now: date(2026, 11, 12, 23, 0), starts: [], fallback: nil, calendar: cal))
    }

    // 晩ごとに最も早い開始を取り、昼寝は除く。夜中の目覚めのあとの再入眠は、同じ晩に数える
    func testNightlyStarts() {
        let s = [date(2026, 11, 10, 23, 10), date(2026, 11, 11, 2, 30),   // 10日の晩: 23:10(夜中の再入眠 2:30 は同じ晩)
                 date(2026, 11, 11, 14, 0),                                 // 昼寝は除く
                 date(2026, 11, 11, 22, 50)]                                // 11日の晩
        let n = BedtimeWindow.nightlyStarts(from: s, calendar: cal)
        XCTAssertEqual(n, [date(2026, 11, 10, 23, 10), date(2026, 11, 11, 22, 50)])
    }

    // 就寝時刻の中央値。23:50 と 0:10 が混ざっても、夜またぎで数える。件数が足りなければ nil
    func testTypicalMinute() {
        let s = [date(2026, 11, 2, 23, 50), date(2026, 11, 4, 0, 10), date(2026, 11, 5, 23, 30), date(2026, 11, 6, 23, 40), date(2026, 11, 9, 23, 55)]
        XCTAssertEqual(BedtimeWindow.typicalMinute(starts: s, calendar: cal), 23 * 60 + 50)
        XCTAssertNil(BedtimeWindow.typicalMinute(starts: Array(s.prefix(4)), calendar: cal))
    }

    // 手で決める候補は 15 分刻みで、18:00 から始まり、翌日の 17:45 で終わる
    func testPickerMinutes() {
        let m = BedtimeWindow.pickerMinutes
        XCTAssertEqual(m.count, 96)
        XCTAssertEqual(m.first, 18 * 60)
        XCTAssertEqual(m[24], 0)            // 24 個目で 0:00
        XCTAssertEqual(m.last, 17 * 60 + 45)
        XCTAssertEqual(Set(m).count, 96)
    }

    func testSnappedAndLabel() {
        XCTAssertEqual(BedtimeWindow.snapped(23 * 60 + 7), 23 * 60)
        XCTAssertEqual(BedtimeWindow.snapped(23 * 60 + 8), 23 * 60 + 15)
        XCTAssertEqual(BedtimeWindow.snapped(23 * 60 + 53), 0)      // 24:00 は 0:00 に戻す
        XCTAssertEqual(BedtimeWindow.label(minute: 23 * 60 + 5), "23:05")
        XCTAssertEqual(BedtimeWindow.label(minute: 0), "0:00")
    }
}
