import XCTest
@testable import NeochiCore

final class ExplainTests: XCTestCase {
    func analysis(rate: Double? = nil, cv: Double? = nil, vol: Double? = nil, sudden: Double? = nil) -> EpisodeAnalysis {
        var a = EpisodeAnalysis(episodeID: "e", speechRate: rate, volumeStdDB: vol, suddenPer10Min: sudden)
        a.speechRateCV = cv
        return a
    }

    func testRateIsTrapezoid() {
        // 290字/分以下は、遅くても満点(遅いほど良い、ではない)
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

    // 用語集(docs/VOICE.md)の使わない言葉が、説明文に入らない
    func testExplainAvoidsForbiddenWords() {
        let banned = ["ゆったり", "癒し", "改善", "効果", "睡眠の質", "聞く", "聞き", "★"]
        var a = analysis(rate: 300, cv: 0.2, vol: 8, sudden: 5)
        a.interestItems = [.init(key: "A", score: 1)]
        let texts = Explain.earParts(a).flatMap { [$0.title, $0.measured, $0.verdict, $0.criterion] }
            + Array(Explain.interestLabels.values) + Array(Explain.calmLabels.values)
            + [InterestLevel.low, .mid, .high].map { Explain.interestVerdict($0, total: 3) } + [Explain.calmVerdict(a.interestItems)]
        for t in texts { for w in banned { XCTAssertFalse(t.contains(w), "\(w) in \(t)") } }
    }

    func testPartsOmittedWhenNoData() {
        XCTAssertTrue(Explain.earParts(analysis()).isEmpty)
    }

    func testInterestObservationCoveredMinutesCountsOverlapOnce() {
        let spans = [InterestObservation(fromMinute: 0, toMinute: 4, quote: "a"),
                     InterestObservation(fromMinute: 3, toMinute: 6, quote: "b"),
                     InterestObservation(fromMinute: 10, toMinute: 10, quote: "c")]
        XCTAssertEqual(spans.coveredMinutes, 8)   // 0〜6 の7分と、10 の1分
        XCTAssertEqual([InterestObservation]().coveredMinutes, 0)
    }
}
