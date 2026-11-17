import XCTest
@testable import NeochiCore

final class DiscoverTests: XCTestCase {
    func show(_ id: String, _ genre: String, _ star: Double?, count: Int? = nil, avg: Int? = nil) -> Show {
        Show(id: id, title: id, genre: genre, star: star, rank: .zzz, avgMinutes: avg,
             stats: count.map { ShowStats(count: $0, avgMinutes: avg ?? 0, minMinutes: 0, maxMinutes: 0, under30: 0) })
    }

    // 同点は、実測の件数が多い番組、平均が短い番組、名前の順
    func testRankedTieBreaks() {
        let s = [show("c", "雑談", 4.5), show("b", "雑談", 4.5, count: 3, avg: 20), show("a", "雑談", 4.5, count: 3, avg: 10),
                 show("z", "雑談", 4.7), show("none", "雑談", nil)]
        XCTAssertEqual(Discover.ranked(s).map(\.id), ["z", "a", "b", "c"])
        XCTAssertEqual(Discover.best(s)?.id, "z")
    }

    // 寝落ち用の棚(朗読・環境音を含む)と、寝落ち用ではない棚は、系統で分かれる
    func testShelvesSplitByGenre() {
        let s = [show("sleep1", "寝落ち用", 4.6), show("sleep2", "寝落ち用", 5.0), show("read", "朗読", 4.9), show("amb", "環境音", 4.8),
                 show("com", "コメディ", 4.7), show("talk", "雑談", 4.4), show("edu", "教養", 4.5)]
        XCTAssertEqual(Discover.sleepMade(s).map(\.id), ["sleep2", "read", "amb", "sleep1"])
        XCTAssertEqual(Discover.notSleepMade(s).map(\.id), ["com", "edu", "talk"])
        XCTAssertEqual(Discover.notSleepMade(s, limit: 2).count, 2)
        XCTAssertTrue(Discover.sleepMadeGenres.isDisjoint(with: Discover.notSleepMadeGenres))
    }

    // チップは決まった順。番組のない系統は出さず、知らない系統は最後
    func testGenresOrder() {
        let s = [show("a", "教養", 4), show("b", "寝落ち用", 4), show("c", "コメディ", 4), show("d", "ふしぎ", 4), show("e", "", 4)]
        XCTAssertEqual(Discover.genres(in: s), ["寝落ち用", "コメディ", "教養", "ふしぎ"])
    }

    // 上のカードは日替わり: 総合 → 寝落ち用 → 寝落ち用ではない。3つの番組は重ならない
    func testSpotlightRotatesAndNeverRepeatsShows() {
        let s = [show("read", "朗読", 4.9), show("sleep", "寝落ち用", 4.6), show("com", "コメディ", 4.7), show("edu", "教養", 4.5)]
        let a = (0..<3).compactMap { Discover.spotlight(s, day: $0) }
        XCTAssertEqual(a.map(\.kind), [.overall, .sleepMade, .notSleepMade])
        XCTAssertEqual(a.map(\.show.id), ["read", "sleep", "com"])          // 寝落ち用の1位(read)は総合と重なるので、次点(sleep)
        XCTAssertEqual(Set(a.map(\.show.id)).count, 3)
        XCTAssertEqual(Discover.spotlight(s, day: 3)?.show.id, "read")        // 3日で一巡
        XCTAssertEqual(Discover.spotlight(s, day: -1)?.kind, .notSleepMade)
    }

    // 種類の番組がなければ、次の種類へ回す。番組がなければ nil
    func testSpotlightSkipsEmptyKinds() {
        let onlySleep = [show("read", "朗読", 4.9)]
        XCTAssertEqual(Discover.spotlight(onlySleep, day: 1)?.kind, .overall)
        XCTAssertNil(Discover.spotlight([], day: 0))
    }
}
