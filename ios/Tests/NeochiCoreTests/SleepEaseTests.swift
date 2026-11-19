import XCTest
@testable import NeochiCore

final class SleepEaseTests: XCTestCase {
    private func analysis(calm: [Double], rate: [Double?] = [], vol: [Double?] = [], sudden: [Int] = []) -> EpisodeAnalysis {
        var a = EpisodeAnalysis(episodeID: "e")
        a.calmPerMin = calm; a.ratePerMin = rate; a.volumePerMin = vol; a.suddenAtSec = sudden
        return a
    }

    func testNilWhenTooLittleData() {
        XCTAssertNil(SleepEase.estimate(from: analysis(calm: [])))
        XCTAssertNil(SleepEase.estimate(from: analysis(calm: [0, 0, 0])))
    }

    func testCalmRunBecomesZone() {
        // 0〜5分は起伏が大きく、6〜14分は静か
        let calm = Array(repeating: 1.8, count: 6) + Array(repeating: 0.1, count: 9)
        let e = SleepEase.estimate(from: analysis(calm: calm))!
        XCTAssertEqual(e.perMin.count, 15)
        XCTAssertEqual(e.zones.count, 1)
        XCTAssertTrue(e.contains(minute: 10))
        XCTAssertFalse(e.contains(minute: 1))
    }

    func testShortCalmIsNotAZone() {
        let calm = Array(repeating: 1.8, count: 6) + [0.1, 0.1] + Array(repeating: 1.8, count: 6)
        XCTAssertTrue(SleepEase.estimate(from: analysis(calm: calm))!.zones.isEmpty)
    }

    func testSuddenSoundBreaksTheZone() {
        let calm = Array(repeating: 0.2, count: 20)
        let quiet = SleepEase.estimate(from: analysis(calm: calm))!
        XCTAssertEqual(quiet.zones, [0...19])
        let loud = SleepEase.estimate(from: analysis(calm: calm, sudden: [600, 610, 660, 670]))!   // 10〜11分に突発音
        XCTAssertLessThan(loud.perMin[10], quiet.perMin[10])
    }

    func testUsesRateAndVolumeWhenNoCalm() {
        let rate: [Double?] = Array(repeating: 300, count: 10)
        let vol: [Double?] = Array(repeating: -30, count: 10)
        let e = SleepEase.estimate(from: analysis(calm: [], rate: rate, vol: vol))!
        XCTAssertEqual(e.zones, [0...9])
    }
}
