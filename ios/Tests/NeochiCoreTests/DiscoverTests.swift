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
}
