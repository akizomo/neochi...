import XCTest
@testable import NeochiCore

final class ContentStartTests: XCTestCase {
    private func a(_ sec: Int?, _ anchor: String?, dur: Double? = 1800) -> EpisodeAnalysis {
        var x = EpisodeAnalysis(episodeID: "e", durationSec: dur)
        x.contentStartSec = sec; x.contentStartAnchor = anchor
        return x
    }

    func testReturnsSecondsWhenAnchored() { XCTAssertEqual(a(95, "こんばんは").contentStart, 95) }
    func testNilWhenNoOpeningToSkip() { XCTAssertNil(a(0, nil).contentStart); XCTAssertNil(a(nil, nil).contentStart) }
    func testNilWithoutAnchor() { XCTAssertNil(a(95, nil).contentStart); XCTAssertNil(a(95, "  ").contentStart) }
    func testNilWhenImplausible() {
        XCTAssertNil(a(400, "x").contentStart)             // 冒頭5分を超える
        XCTAssertNil(a(100, "x", dur: 120).contentStart)   // 回の終わりに近すぎる
    }
}
