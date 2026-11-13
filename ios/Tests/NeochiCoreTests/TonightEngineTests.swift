import XCTest
@testable import NeochiCore

final class TonightEngineTests: XCTestCase {
    // 朗読2つ(電話帳・植物)、解説2つ(鉄道・天気)
    let phonebook = Show(id: "phonebook", title: "電話帳を読む会", genre: "朗読", star: 4.9, rank: .zzz)
    let plant = Show(id: "plant", title: "深夜の植物図鑑", genre: "朗読", star: 4.7, rank: .zz)
    let train = Show(id: "train", title: "地方鉄道の時刻表を読む", genre: "解説", star: 4.1, rank: .z)
    let weather = Show(id: "weather", title: "月曜の天気図", genre: "解説", star: 3.8)

    func eps(_ show: String, top: Int) -> [Episode] {
        (0..<5).compactMap { i in
            let n = top - i
            return n >= 1 ? Episode(id: "\(show)-\(n)", showID: show, title: "第\(n)回", number: n) : nil
        }
    }

    func ctx(history: [PlayRecord] = [], favorites: Set<String> = ["phonebook", "plant", "train"],
             queue: [String] = [], current: String = "phonebook", lastNight: LastNight? = nil, streak: Int = 3) -> TonightContext {
        TonightContext(
            shows: [phonebook, plant, train, weather],
            episodes: ["phonebook": eps("phonebook", top: 7), "plant": eps("plant", top: 12),
                       "train": eps("train", top: 31), "weather": eps("weather", top: 88)],
            history: history, favorites: favorites, queue: queue, currentShowID: current,
            lastNight: lastNight, genreStreakNights: streak)
    }

    func play(_ show: String, _ n: Int, times: Int = 1, day: Int = 1) -> [PlayRecord] {
        (0..<times).map { PlayRecord(episodeID: "\(show)-\(n)", showID: show, playedAt: Date(timeIntervalSince1970: Double(day * 86400 + $0)) ) }
    }

    // 昨夜30分未満で寝落ちできた回は、同じ回(2回目)を先頭に出す
    func testRepeatsEpisodeWhenSleptFast() {
        let c = ctx(history: play("phonebook", 7), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 18))
        let s = TonightEngine.slate(ctx: c)
        XCTAssertEqual(s[0].episode?.id, "phonebook-7")
        XCTAssertEqual(s[0].playCount, 2)
        XCTAssertEqual(s[0].reason, .sleptFast(minutes: 18))
        XCTAssertEqual(s[1].episode?.id, "phonebook-6")
        XCTAssertEqual(s[1].reason, .unlistened)
    }

    // 30分以上かかったら、次の回へ進める。同じ回は2番目に下がる
    func testMovesOnWhenTookLong() {
        let c = ctx(history: play("phonebook", 7), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 40))
        let s = TonightEngine.slate(ctx: c)
        XCTAssertEqual(s[0].episode?.id, "phonebook-6")
        XCTAssertEqual(s[0].reason, .tookLong(minutes: 40))
        XCTAssertEqual(s[1].episode?.id, "phonebook-7")
        XCTAssertEqual(s[1].reason, .sameAsLastNight)
    }

    // 記録がない夜は、次の回へ進める
    func testNoRecordMeansNext() {
        let c = ctx(history: play("phonebook", 7), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: nil))
        let s = TonightEngine.slate(ctx: c)
        XCTAssertEqual(s[0].episode?.id, "phonebook-6")
        XCTAssertEqual(s[0].reason, .latest)
    }

    // 3回聴いた回は外れる(速く眠れていても、同じ回に戻らない)
    func testCapsAtThreePlays() {
        let c = ctx(history: play("phonebook", 7, times: 3), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 9))
        let s = TonightEngine.slate(ctx: c)
        XCTAssertFalse(s.contains { $0.show.id == "phonebook" && $0.episode?.id == "phonebook-7" })
        XCTAssertEqual(s[0].episode?.id, "phonebook-6")
    }

    // 履歴が一切ない初回: 最新の回
    func testFirstRunPicksLatest() {
        let s = TonightEngine.slate(ctx: ctx())
        XCTAssertEqual(s[0].episode?.id, "phonebook-7")
        XCTAssertEqual(s[0].playCount, 1)
    }

    // 3本目は、別ジャンル(冒険)。ジャンルが続いた晩数を理由に出す
    func testThirdIsDifferentGenre() {
        let s = TonightEngine.slate(ctx: ctx())
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[2].show.id, "train")
        XCTAssertEqual(s[2].reason, .genreStreak(from: "朗読", to: "解説", nights: 3))
        XCTAssertEqual(s[2].reason.text, "朗読が3晩続いたので、解説の番組")
    }

    // 「次に聴く」の先頭は、3枚目に優先して出る
    func testQueueHeadTakesThirdSlot() {
        let s = TonightEngine.slate(ctx: ctx(queue: ["weather"]))
        XCTAssertEqual(s[2].show.id, "weather")
        XCTAssertEqual(s[2].reason, .queued)
    }

    // 同じ番組・同じ回を重複して出さない
    func testNoDuplicateCandidates() {
        let s = TonightEngine.slate(ctx: ctx(history: play("phonebook", 7), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 12)))
        let keys = s.map { "\($0.show.id)/\($0.episode?.id ?? "-")" }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // 明日以降: 回を決めない「続き」。別番組と別ジャンルが続く
    func testLaterNightsHaveNoEpisodeForCurrentShow() {
        let s = TonightEngine.slate(night: 1, ctx: ctx())
        XCTAssertNil(s[0].episode)
        XCTAssertEqual(s[0].reason, .continuation)
        XCTAssertEqual(s[1].reason, .sameGenreOther(genre: "朗読"))
        XCTAssertEqual(s[1].show.id, "plant")
        XCTAssertEqual(s[2].reason, .genreContinues(from: "朗読", to: "解説"))
    }

    // 現在の番組がなければ、先頭の番組から
    func testFallsBackToFirstShow() {
        let c = ctx(current: "unknown")
        XCTAssertEqual(TonightEngine.slate(ctx: c).first?.show.id, "phonebook")
    }

    func testReasonSegmentsEmphasizeNumbers() {
        XCTAssertEqual(Reason.sleptFast(minutes: 18).segments,
                       [ReasonSegment("昨夜は"), ReasonSegment("18分", emphasized: true), ReasonSegment("で寝落ち")])
    }

    func testCommentBoundaries() {
        XCTAssertEqual(NCString.comment(minutes: 4), "それは番組の力ではなく、ただの寝不足です")
        XCTAssertEqual(NCString.comment(minutes: 5), "即落ちでした")
        XCTAssertEqual(NCString.comment(minutes: 10), "理想の寝落ちでした")
        XCTAssertEqual(NCString.comment(minutes: 20), "やや粘りました")
        XCTAssertEqual(NCString.comment(minutes: 30), "最後まで聞いてしまいました")
    }

    func testLatencyMinutes() {
        let start = Date(timeIntervalSince1970: 0)
        let log = SleepLog(id: "1", episodeID: "e", showID: "s", startedAt: start, sleepOnsetAt: start.addingTimeInterval(18 * 60 + 20))
        XCTAssertEqual(log.latencyMinutes, 18)
        XCTAssertNil(SleepLog(id: "2", episodeID: "e", showID: "s", startedAt: start).latencyMinutes)
    }

    // 「いま聴く」は、今夜の候補に入っていない番組でも、回を決めて返す
    func testListenNowPicksEpisodeForAnyShow() {
        let c = TonightEngine.listenNow(show: weather, ctx: ctx())
        XCTAssertEqual(c?.show.id, "weather")
        XCTAssertEqual(c?.episode?.id, "weather-88")
        XCTAssertEqual(c?.playCount, 1)
    }

    // 聴いたことのある回は、回数が進む
    func testListenNowCountsRepeat() {
        let c = TonightEngine.listenNow(show: phonebook, ctx: ctx(history: play("phonebook", 7), lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 18)))
        XCTAssertEqual(c?.episode?.id, "phonebook-7")
        XCTAssertEqual(c?.playCount, 2)
    }

    // 回のない番組は nil
    func testListenNowNilWithoutEpisodes() {
        let empty = TonightContext(shows: [weather], episodes: [:], history: [], favorites: [], queue: [], currentShowID: nil, lastNight: nil, genreStreakNights: 0)
        XCTAssertNil(TonightEngine.listenNow(show: weather, ctx: empty))
    }

    // 興味の3択の値は、DB の interest_vote の制約(-1, 0, 1)と同じ
    func testInterestAnswerValuesMatchDatabase() {
        XCTAssertEqual(InterestAnswer.allCases.map(\.rawValue), [-1, 0, 1])
        XCTAssertEqual(NCString.interestLabel(.justRight), "ちょうどよかった")
    }
}
