import XCTest
@testable import NeochiCore

final class LatencyZoneTests: XCTestCase {
    // ゾーンは、朝のひとこと(comment)と同じ区切り
    func testZonesMatchComment() {
        for m in [0, 9, 10, 19, 20, 29, 30, 90] {
            let z = LatencyZone.of(minutes: m)
            switch m {
            case ..<10: XCTAssertEqual(z, .instant); XCTAssertEqual(NCString.comment(minutes: m), "即落ちでした")
            case 10..<20: XCTAssertEqual(z, .ideal); XCTAssertEqual(NCString.comment(minutes: m), "理想の寝落ちでした")
            case 20..<30: XCTAssertEqual(z, .lingered); XCTAssertEqual(NCString.comment(minutes: m), "やや粘りました")
            default: XCTAssertEqual(z, .long); XCTAssertEqual(NCString.comment(minutes: m), "最後まで聴いてしまいました")
            }
        }
    }

    func testRangesAreContiguous() {
        XCTAssertEqual(LatencyZone.allCases.map(\.range), [0...10, 10...20, 20...30, 30...45])
    }

    // 早い寝落ちの境目は、今夜の提案が使う 30分 と同じ
    func testLongStartsAtFastThreshold() {
        XCTAssertEqual(LatencyZone.long.range.lowerBound, TonightEngine.fastThresholdMinutes)
    }
}
