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
