import XCTest
@testable import NeochiCore

final class SessionStateTests: XCTestCase {
    func sample() -> SessionState {
        SessionState(history: [PlayRecord(episodeID: "a-1", showID: "a", playedAt: Date()),
                               PlayRecord(episodeID: "b-1", showID: "b", playedAt: Date())],
                     favorites: ["a", "b"], queue: ["a", "b"], currentShowID: "a",
                     lastNight: LastNight(showID: "a", episodeID: "a-1", minutes: 18),
                     genreStreakNights: 3, pendingMorning: true, reservedShowIDs: [0: "a", 1: "b"])
    }

    func testKeepsEverythingWhenAllShowsExist() {
        let s = sample()
        XCTAssertEqual(s.reconciled(toShowIDs: ["a", "b"]), s)
    }

    func testDropsSampleStateWhenShowsAreReplaced() {
        let r = sample().reconciled(toShowIDs: ["x", "y"])
        XCTAssertTrue(r.history.isEmpty); XCTAssertTrue(r.favorites.isEmpty); XCTAssertTrue(r.queue.isEmpty)
        XCTAssertTrue(r.reservedShowIDs.isEmpty)
        XCTAssertNil(r.currentShowID); XCTAssertNil(r.lastNight)
        XCTAssertEqual(r.genreStreakNights, 0); XCTAssertFalse(r.pendingMorning)
    }

    func testKeepsOnlyExistingParts() {
        let r = sample().reconciled(toShowIDs: ["b"])
        XCTAssertEqual(r.history.map(\.showID), ["b"]); XCTAssertEqual(r.favorites, ["b"])
        XCTAssertEqual(r.reservedShowIDs, [1: "b"]); XCTAssertNil(r.currentShowID)
    }
}
import XCTest
@testable import NeochiCore

final class SessionStateCodableTests: XCTestCase {
    /// お気に入り・次に聴く・再生の記録は、保存して読み直しても同じになる(アプリを閉じても残す)。
    func testRoundTrip() throws {
        let s = SessionState(history: [PlayRecord(episodeID: "e1", showID: "a", playedAt: Date(timeIntervalSince1970: 1_700_000_000))],
                             favorites: ["a", "b"], queue: ["b"], currentShowID: "a",
                             lastNight: LastNight(showID: "a", episodeID: "e1", minutes: 12), genreStreakNights: 2,
                             pendingMorning: false, reservedShowIDs: [0: "a"])
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(SessionState.self, from: e.encode(s)), s)
    }

    // 予約(今夜聴く・明日聴く)も保存できる。予約を足す前の保存でも読める
    func testReservationsRoundTripAndOldFile() throws {
        let night = Date(timeIntervalSince1970: 1_700_000_000)
        let s = SessionState(favorites: ["a"], reservations: [SavedReservation(night: night, showID: "a", episodeID: "e1"),
                                                              SavedReservation(night: night.addingTimeInterval(86400), showID: "b", episodeID: nil)])
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(SessionState.self, from: e.encode(s)), s)
        let old = #"{"history":[],"pendingMorning":false,"favorites":["a"],"queue":[],"genreStreakNights":0,"reservedShowIDs":{}}"#
        XCTAssertNil(try d.decode(SessionState.self, from: Data(old.utf8)).reservations)
    }
}
