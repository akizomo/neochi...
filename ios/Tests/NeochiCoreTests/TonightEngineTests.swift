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
            return n >= 1 ? Episode(id: "\(show)-\(n)", showID: show, title: "第\(n)話", number: n) : nil
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

    // 最初の番組は、好みのジャンルの中で評点がいちばん高い番組。理由は「好みの〜」
    func testFirstRunStartsWithPreferredGenreBestShow() {
        var c = ctx(favorites: [], current: "")
        c.currentShowID = nil
        c.preferredGenres = ["解説"]
        let s = TonightEngine.slate(ctx: c)
        XCTAssertEqual(s[0].show.id, "train")                       // 解説の中で評点が高い(4.1)。全体の最高は朗読の電話帳(4.9)
        XCTAssertEqual(s[0].reason, .preferredGenre(genre: "解説"))
        XCTAssertEqual(Reason.preferredGenre(genre: "朗読").text, "好みの朗読")
    }

    // 好みがなければ、全体で評点がいちばん高い番組から始める
    func testFirstRunWithoutPreferenceStartsWithBestShow() {
        var c = ctx(favorites: [], current: "")
        c.currentShowID = nil
        XCTAssertEqual(TonightEngine.slate(ctx: c)[0].show.id, "phonebook")
    }

    // 好みのジャンルの番組が、ほかより先に並ぶ。好みがなければ、ちがう系統(解説)が先になる
    func testPreferredGenreIsOrderedBeforeOthers() {
        var c = ctx(favorites: [], current: "phonebook")
        XCTAssertEqual(TonightEngine.slate(ctx: c).last?.show.id, "train")
        c.preferredGenres = ["朗読"]
        let s = TonightEngine.slate(ctx: c)
        XCTAssertEqual(s.last?.show.id, "plant")
        XCTAssertEqual(s.last?.reason, .preferredGenre(genre: "朗読"))
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

    // 3本目がお気に入りなら、お気に入りを理由にする(お気に入りを先に選んでいるので)
    func testThirdFavoriteSaysFavorite() {
        let s = TonightEngine.slate(ctx: ctx())
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[2].show.id, "train")
        XCTAssertEqual(s[2].reason, .favorite(genre: "解説"))
        XCTAssertEqual(s[2].reason.text, "お気に入りの解説")
    }

    // 3本目は、別ジャンル(冒険)。晩数を数えていれば晩数を、なければ系統の移り変わりだけを出す
    func testThirdIsDifferentGenre() {
        let s = TonightEngine.slate(ctx: ctx(favorites: ["phonebook"]))
        XCTAssertEqual(s[2].show.id, "train")
        XCTAssertEqual(s[2].reason, .genreStreak(from: "朗読", to: "解説", nights: 3))
        XCTAssertEqual(s[2].reason.text, "朗読が3晩。解説へ")
        let one = TonightEngine.slate(ctx: ctx(favorites: ["phonebook"], streak: 0))
        XCTAssertEqual(one[2].reason.text, "朗読から、解説へ")
    }

    // 理由の文: 内部の分類は系統名に直す。出せない分類は名前を出さない。「1晩続いた」とは書かない
    func testReasonCopy() {
        XCTAssertEqual(Reason.genreStreak(from: "寝落ち・睡眠導入", to: "芸人ラジオ・バラエティ", nights: 1).text, "寝落ち用から、コメディへ")
        XCTAssertEqual(Reason.genreStreak(from: "寝落ち・睡眠導入", to: "とても長い分類の名前です", nights: 1).text, "ちがう系統の番組")
        XCTAssertEqual(Reason.genreContinues(from: "朗読", to: "朗読").text, "ちがう系統の番組")
        XCTAssertEqual(Reason.sameGenreOther(genre: "教養（比較用含む）").text, "同じ教養の、別の番組")
        XCTAssertEqual(Reason.sameGenreOther(genre: "とても長い分類の名前です").text, "同じ系統の、別の番組")
        XCTAssertEqual(Reason.favorite(genre: "とても長い分類の名前です").text, "お気に入りの番組")
        XCTAssertEqual(Reason.tookLong(minutes: 40).text, "昨夜は40分。次の話へ")
        XCTAssertEqual(GenreLabel.display("寝落ち・睡眠導入（海外基準）"), "寝落ち用")
        XCTAssertNil(GenreLabel.display("とても長い分類の名前です"))
        // どの理由も20字まで(カードの1行に収める)
        let all: [Reason] = [.sleptFast(minutes: 120), .tookLong(minutes: 120), .queued, .continuation, .unlistened,
                             .favorite(genre: "芸人ラジオ・バラエティ"), .sameGenreOther(genre: "寝落ち・睡眠導入（海外基準）"),
                             .genreStreak(from: "芸人ラジオ・バラエティ", to: "寝落ち・睡眠導入", nights: 12),
                             .genreContinues(from: "芸人ラジオ・バラエティ", to: "寝落ち・睡眠導入")]
        for r in all { XCTAssertLessThanOrEqual(r.text.count, 20, r.text); XCTAssertFalse(r.text.contains("1晩")) }
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
        XCTAssertEqual(NCString.comment(minutes: 4), "即落ちでした")
        XCTAssertEqual(NCString.comment(minutes: 9), "即落ちでした")
        XCTAssertEqual(NCString.comment(minutes: 10), "理想の寝落ちでした")
        XCTAssertEqual(NCString.comment(minutes: 20), "やや粘りました")
        XCTAssertEqual(NCString.comment(minutes: 30), "最後まで聴いてしまいました")
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

    // 🎯 の10段階のゾーンは、AIの採点(config/scoring.yaml の interest_zone 4〜6)と同じ区切り
    func testInterestZonesMatchScoring() {
        XCTAssertEqual((1...10).map { NCString.interestZone($0) },
                       [.bored, .bored, .bored, .justRight, .justRight, .justRight, .absorbed, .absorbed, .absorbed, .absorbed])
        XCTAssertEqual(NCString.interestZoneName(.justRight), "ちょうどよい")
    }

    // 話を指定した候補。聴いた回数から、何回目かと理由を決める
    func testCandidateForEpisode() {
        let c = ctx(history: play("phonebook", 7, times: 2))
        let heard = TonightEngine.candidate(show: phonebook, episode: eps("phonebook", top: 7)[0], ctx: c)
        XCTAssertEqual(heard.playCount, 3); XCTAssertEqual(heard.reason, .heardBefore)
        let fresh = TonightEngine.candidate(show: phonebook, episode: eps("phonebook", top: 7)[1], ctx: c)
        XCTAssertEqual(fresh.playCount, 1); XCTAssertEqual(fresh.reason, .unlistened)
    }
}
