import XCTest
@testable import NeochiCore

final class ExplainTests: XCTestCase {
    func analysis(rate: Double? = nil, cv: Double? = nil, vol: Double? = nil, sudden: Double? = nil) -> EpisodeAnalysis {
        var a = EpisodeAnalysis(episodeID: "e", speechRate: rate, volumeStdDB: vol, suddenPer10Min: sudden)
        a.speechRateCV = cv
        return a
    }

    func testRateIsTrapezoid() {
        // 290字/分以下は、遅くても満点(「ゆったり」)
        XCTAssertTrue(Explain.earParts(analysis(rate: 92)).first!.good)
        XCTAssertTrue(Explain.earParts(analysis(rate: 290)).first!.good)
        XCTAssertFalse(Explain.earParts(analysis(rate: 380)).first!.good)
        XCTAssertEqual(Explain.earParts(analysis(rate: 450)).first!.verdict, "かなり速いです")
    }

    // 実データの回(突発音 9.8回/10分 は、★1.1 のほぼ最低)で、「ときどき」と言わない
    func testSuddenNearWorstIsNotSoftened() {
        let r = Explain.earParts(analysis(sudden: 9.8)).first!
        XCTAssertEqual(r.verdict, "急な音が多めです")
        XCTAssertFalse(r.good)
    }

    func testCriteriaMatchScoringYaml() {
        XCTAssertEqual(EarCriteria.rateBestMax, 290); XCTAssertEqual(EarCriteria.rateWorst, 450)
        XCTAssertEqual(EarCriteria.cvBest, 0.10); XCTAssertEqual(EarCriteria.cvWorst, 0.40)
        XCTAssertEqual(EarCriteria.volumeBest, 4); XCTAssertEqual(EarCriteria.volumeWorst, 12)
        XCTAssertEqual(EarCriteria.suddenBest, 0); XCTAssertEqual(EarCriteria.suddenWorst, 10)
    }

    func testInterestTotalFloorIsOne() {
        XCTAssertEqual(Explain.interestTotal([]), 1)
        XCTAssertEqual(Explain.interestTotal([.init(key: "B", score: 1), .init(key: "E", score: 2)]), 3)
    }

    func testPartsOmittedWhenNoData() {
        XCTAssertTrue(Explain.earParts(analysis()).isEmpty)
    }
}
