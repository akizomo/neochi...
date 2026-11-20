import XCTest
@testable import NeochiCore

final class SleepAttributionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    func testOnsetWhileStillPlayingCounts() {
        XCTAssertEqual(SleepAttribution.judge(onset: at(18), lastAudible: at(40)), .onset(at(18)))
    }

    func testOnsetSoonAfterPlaybackStoppedCounts() {
        // スリープタイマーで20分で止まり、その25分後に眠った。
        XCTAssertEqual(SleepAttribution.judge(onset: at(45), lastAudible: at(20)), .onset(at(45)))
        XCTAssertEqual(SleepAttribution.judge(onset: at(50), lastAudible: at(20)), .onset(at(50)))   // ちょうど30分は含む
    }

    func testTrialPlayInTheEveningIsNotSleepOnset() {
        // 17時に数分だけ試しで聴き、22時すぎに眠った(312分と出ていた例)。
        XCTAssertEqual(SleepAttribution.judge(onset: at(312), lastAudible: at(3)), .afterPlayback)
    }

    func testNoOnsetIsUnknown() {
        XCTAssertEqual(SleepAttribution.judge(onset: nil, lastAudible: at(3)), .unknown)
    }

    func testUnknownPlaybackEndKeepsOnset() {
        // 前の版で残った晩は、止まった時刻が分からないので、入眠をそのまま使う。
        XCTAssertEqual(SleepAttribution.judge(onset: at(312), lastAudible: nil), .onset(at(312)))
    }
}
