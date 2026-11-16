import XCTest
@testable import NeochiCore

final class SelfReportTests: XCTestCase {
    func testChoicesMapToIncreasingMinutes() {
        let m = SelfReportLatency.allCases.map(\.minutes)
        XCTAssertEqual(m, m.sorted())
        XCTAssertEqual(Set(m).count, 4)
    }

    func testSelfReportUploadsApproximateMinutesButNotMeasured() {
        var log = SleepLog(id: "a", episodeID: "e", showID: "s", startedAt: Date(), source: .selfReport, selfReport: .short)
        XCTAssertNil(log.latencyMinutes)              // 実測の分数としては扱わない
        XCTAssertEqual(log.uploadLatencyMinutes, 15)  // 送るのはおおよその分数
        log.selfReport = nil
        XCTAssertNil(log.uploadLatencyMinutes)
    }

    func testOldLogsWithoutSelfReportStillDecode() throws {
        let json = #"{"id":"a","episodeID":"e","showID":"s","startedAt":0,"source":"self","listenNo":1}"#
        let d = JSONDecoder()
        let log = try d.decode(SleepLog.self, from: Data(json.utf8))
        XCTAssertNil(log.selfReport)
    }

    func testMeasuredWinsOverSelfReport() {
        let start = Date()
        let log = SleepLog(id: "a", episodeID: "e", showID: "s", startedAt: start, sleepOnsetAt: start.addingTimeInterval(12 * 60),
                           source: .watch, selfReport: .never)
        XCTAssertEqual(log.uploadLatencyMinutes, 12)
    }
}
