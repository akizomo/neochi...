import XCTest
@testable import NeochiCore

final class SplashTimelineTests: XCTestCase {
    func testNStandsThenFallsNinetyDegrees() {
        XCTAssertEqual(SplashTimeline.angle(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(SplashTimeline.angle(at: SplashTimeline.fallStart), 0, accuracy: 0.001)
        let end = SplashTimeline.fallStart + SplashTimeline.fallDuration
        XCTAssertEqual(SplashTimeline.angle(at: end), 90, accuracy: 0.001)
        XCTAssertEqual(SplashTimeline.angle(at: end + 3), 90, accuracy: 0.001)         // 倒れたあとは動かない
        XCTAssertEqual(SplashTimeline.angle(at: SplashTimeline.fallStart + SplashTimeline.fallDuration / 2), 45, accuracy: 0.001)
    }

    func testFallNeverReverses() {
        var last = -1.0
        for i in 0...600 {
            let a = SplashTimeline.angle(at: Double(i) / 100)
            XCTAssertGreaterThanOrEqual(a, last)
            last = a
        }
    }

    func testSmallZsFloatAndFade() {
        for f in SplashTimeline.floaters {
            XCTAssertEqual(SplashTimeline.opacity(f, at: f.start), 0, accuracy: 0.001)
            XCTAssertEqual(SplashTimeline.opacity(f, at: f.start + f.duration * 0.4), SplashTimeline.floatPeak, accuracy: 0.001)
            XCTAssertEqual(SplashTimeline.opacity(f, at: f.start + f.duration), 0, accuracy: 0.001)
            XCTAssertEqual(SplashTimeline.rise(f, at: f.start + f.duration), SplashTimeline.floatRise, accuracy: 0.001)
        }
        XCTAssertLessThan(SplashTimeline.floaters[0].start, SplashTimeline.floaters[1].start)   // ずらして出る
    }

    func testScreenFadesOutAtTheEnd() {
        XCTAssertEqual(SplashTimeline.screenOpacity(at: 0), 1)
        XCTAssertEqual(SplashTimeline.screenOpacity(at: SplashTimeline.fadeStart), 1)
        XCTAssertEqual(SplashTimeline.screenOpacity(at: SplashTimeline.total), 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(SplashTimeline.floaters.map { $0.start + $0.duration }.max()!, SplashTimeline.total)
    }

    func testReduceMotionOnlyShowsTheMark() {
        XCTAssertEqual(SplashTimeline.angle(at: 2, reduceMotion: true), 0)
        XCTAssertEqual(SplashTimeline.opacity(SplashTimeline.floaters[0], at: 3, reduceMotion: true), 0)
        XCTAssertEqual(SplashTimeline.duration(reduceMotion: true), SplashTimeline.reducedTotal)
        XCTAssertEqual(SplashTimeline.screenOpacity(at: SplashTimeline.reducedTotal, reduceMotion: true), 0, accuracy: 0.001)
    }

    func testWordmarkAppearsFirst() {
        XCTAssertEqual(SplashTimeline.wordmarkOpacity(at: 0), 0)
        XCTAssertEqual(SplashTimeline.wordmarkOpacity(at: SplashTimeline.wordmarkFadeIn), 1)
        XCTAssertLessThan(SplashTimeline.wordmarkFadeIn, SplashTimeline.fallStart)               // 倒れる前に、下の名前が見える
    }
}
