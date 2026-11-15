import XCTest
@testable import NeochiCore

final class DetailMathTests: XCTestCase {
    func testDeltaNeedsEight() {
        XCTAssertNil(DetailMath.delta([1, 2, 3, 4, 5, 6, 7]))
        // 見本の値: 前の4件 19,16,38,12(平均21.25)→ 直近 14,11,9,6(平均10)
        XCTAssertEqual(DetailMath.delta([19, 16, 38, 12, 14, 11, 9, 6])!, -11.25, accuracy: 1e-9)
        // 9件以上でも、直近4件とその前の4件だけを比べる
        XCTAssertEqual(DetailMath.delta([100, 4.0, 4.2, 3.9, 4.4, 4.1, 4.5, 4.3, 4.4])!, 0.2, accuracy: 1e-9)
    }

    func testEpisodeNumber() {
        func ep(_ t: String, _ n: Int? = nil) -> Episode { Episode(id: "e", showID: "s", title: t, number: n) }
        XCTAssertEqual(DetailMath.episodeNumber(ep("第81回 冬の布団の話")), 81)
        XCTAssertEqual(DetailMath.episodeNumber(ep("#204 港の朝")), 204)
        XCTAssertEqual(DetailMath.episodeNumber(ep("82話 冬の布団")), 82)
        XCTAssertEqual(DetailMath.episodeNumber(ep("EP12: night")), 12)
        XCTAssertEqual(DetailMath.episodeNumber(ep("何もない", 7)), 7)
        XCTAssertNil(DetailMath.episodeNumber(ep("冬の布団の話")))
    }

    func testCalmVerdictAndWords() {
        XCTAssertEqual(DetailMath.calmCurveVerdict([], minutes: 20), "冒頭20分に、昂らせる山はありません。")
        let ms = [Moment(minute: 6, note: "a", level: 1), Moment(minute: 14, note: "b", level: 1)]
        XCTAssertEqual(DetailMath.calmCurveVerdict(ms, minutes: 20), "冒頭20分に、小さな山が2つだけです。")
        XCTAssertEqual(DetailMath.momentStrength(Moment(minute: 1, note: "", level: 2)), "多い")
        XCTAssertNil(DetailMath.momentStrength(Moment(minute: 1, note: "")))
        XCTAssertEqual(DetailMath.calmWord(0.2), "なし"); XCTAssertEqual(DetailMath.calmWord(1.6), "多い")
        XCTAssertEqual(DetailMath.clampedMinutes(75), 60)
    }

    func testMomentA11yLabel() {
        XCTAssertEqual(NCString.momentLabel(minute: 6), "6分の山")
    }

    // 用語集の使わない言葉と、「！」が、新しい文言に入らない
    func testNewCopyAvoidsForbiddenWords() {
        let texts = [DetailMath.calmCurveVerdict([Moment(minute: 1, note: "", level: 2)], minutes: 20),
                     NCString.summaryHeader, NCString.interestZoneNote, NCString.analyzing,
                     NCString.deltaCaptionRecords, NCString.deltaCaptionEpisodes]
        for t in texts {
            for w in ["！", "ゆったり", "癒し", "改善", "効果", "睡眠の質", "聞く", "退屈", "エピソード", "話の平均"] {
                XCTAssertFalse(t.contains(w), "\(t) に \(w)")
            }
        }
    }

    func testRankMeaningMatchesZRankYaml() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../config/z_rank.yaml").standardized
        let yaml = try String(contentsOf: url, encoding: .utf8)
        for (key, r) in [("z", ZRank.z), ("zz", .zz), ("zzz", .zzz)] {
            XCTAssertTrue(yaml.contains("\(key):") && yaml.contains("min_star: \(RankCriteria.minStar(r))"), key)
        }
        // 実績の軸の帯: 0〜60分を切れ目なく、30分で「寝落ちした」とそれ以外に分ける。即落ちを、別の(低い)区間にしない
        let zones = DetailMath.sleepZones
        XCTAssertEqual(zones.first?.lo, 0); XCTAssertEqual(zones.last?.hi, DetailMath.recordAxisMax)
        for (a, b) in zip(zones, zones.dropFirst()) { XCTAssertEqual(a.hi, b.lo) }
        XCTAssertEqual(zones.filter(\.fell).map(\.hi), [30])
        XCTAssertNotEqual(NCString.comment(minutes: 29), NCString.comment(minutes: 30), "30分で、コメントも変わる")
        let view = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../supabase/migrations/0006_show_stats.sql").standardized, encoding: .utf8)
        XCTAssertTrue(view.contains("latency_min < \(DetailMath.fellAsleepMinutes)"), "寝落ちの線は、show_stats(DBの集計)と同じ")
        // バッジの横は、基準の数字ではなく、番組の勧め方のひとこと(ミシュランのように)。基準は「解析について」に書く
        for r in [ZRank.z, .zz, .zzz] {
            XCTAssertFalse(NCString.rankMeaning(r).contains("以上"), "基準の数字を、バッジの横に出さない")
            for banned in ["確実", "必ず", "効", "改善", "安眠", "熟睡", "ぐっすり"] {
                XCTAssertFalse(NCString.rankMeaning(r).contains(banned), "\(banned) を使わない(docs/VOICE.md)")
            }
        }
        XCTAssertEqual(NCString.rankMeaning(.zzz), "眠りたい夜は、まずこの番組")
        XCTAssertTrue(NCString.rankCriteriaNote.contains("3.0") && NCString.rankCriteriaNote.contains("3.6") && NCString.rankCriteriaNote.contains("4.2"))
    }

    func testDeltaTone() {
        XCTAssertEqual(DetailMath.tone(0.2, .higherIsBetter, flat: false), .positive)   // 評点が上がった
        XCTAssertEqual(DetailMath.tone(-0.2, .higherIsBetter, flat: false), .negative)
        XCTAssertEqual(DetailMath.tone(-11, .lowerIsBetter, flat: false), .positive)    // 寝落ちまでが短くなった
        XCTAssertEqual(DetailMath.tone(3, .lowerIsBetter, flat: false), .negative)
        XCTAssertEqual(DetailMath.tone(0.04, .higherIsBetter, flat: true), .neutral)    // 表示では 0.0
    }
}
