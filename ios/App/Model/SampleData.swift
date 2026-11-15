import Foundation
import NeochiCore

/// 開発用のサンプル(Supabase につなぐまでの仮)。画面の確認に使う。
enum SampleData {
    static let shows: [Show] = [
        Show(id: "phonebook", title: "電話帳を読む会", genre: "朗読", star: 4.9, rank: .zzz,
             oneLiner: "抑揚のない読み上げが続く番組です", avgMinutes: 9),
        Show(id: "plant", title: "深夜の植物図鑑", genre: "朗読", star: 4.7, rank: .zz,
             oneLiner: "声がゆっくりで、音量の変化が小さい番組です", avgMinutes: 14),
        Show(id: "train", title: "地方鉄道の時刻表を読む", genre: "解説", star: 4.1, rank: .z,
             oneLiner: "解説が淡々と進み、駅名の列挙で抑揚が出ます", avgMinutes: 34),
        Show(id: "weather", title: "月曜の天気図", genre: "解説", star: 3.8,
             oneLiner: "読み上げは一定ですが、内容が単調です"),
        Show(id: "port", title: "港町ラジオ", genre: "雑談", star: 3.1,
             oneLiner: "会話が中心で、掛け合いが多い番組です"),
    ]

    static func episodes(_ show: String, top: Int) -> [Episode] {
        (0..<5).compactMap { i in
            let n = top - i
            return n >= 1 ? Episode(id: "\(show)-\(n)", showID: show, title: i == 0 ? "第\(n)回" : "第\(n)回", number: n) : nil
        }
    }

    static let episodeMap: [String: [Episode]] = [
        "phonebook": episodes("phonebook", top: 7), "plant": (0..<10).map { i in
            Episode(id: "plant-\(82 - i)", showID: "plant", title: "第\(82 - i)回", number: 82 - i)
        },
        "train": episodes("train", top: 31), "weather": episodes("weather", top: 88), "port": episodes("port", top: 204),
    ]

    /// 番組詳細の図の見本(深夜の植物図鑑)。最新の82回は解析中、81回が最新の解析済み。
    static let analyses: [String: EpisodeAnalysis] = {
        var out: [String: EpisodeAnalysis] = [:]
        let stars = [4.0, 4.2, 3.9, 4.4, 4.1, 4.5, 4.3, 4.4]   // 74回〜81回
        for (i, v) in stars.enumerated() {
            out["plant-\(74 + i)"] = EpisodeAnalysis(episodeID: "plant-\(74 + i)", finalStar: v, calmStar: 4.5, earStar: 4.0,
                                                    interest: .mid, interestScore: 5)   // 起伏・興味も判定済み
        }
        var a = EpisodeAnalysis(
            episodeID: "plant-81", finalStar: 4.4, calmStar: 4.5, earStar: 4.1, interest: .mid, interestScore: 5,
            reason: "話題は身近で、声の高さがほとんど変わりません。", inputDepth: "transcript",
            earParts: EarParts(rate: 4.6, rateCV: 4.2, volume: 4.0, sudden: 3.6),
            speechRate: 274, speechRateCV: 0.16, volumeStdDB: 4.6, suddenPer10Min: 1.3,
            interestItems: [.init(key: "A", score: 0), .init(key: "B", score: 1, minute: 3), .init(key: "C", score: 2, minute: 6),
                            .init(key: "D", score: 0), .init(key: "E", score: 2, minute: 16)],
            calmItems: [.init(key: "A", score: 1, minute: 6), .init(key: "B", score: 0), .init(key: "C", score: 0),
                        .init(key: "D", score: 1, minute: 14)],
            ratePerMin: [300, 280, 265, 270, 290, 345, 300, 270, 262, 255, 260, 250, 248, 252, 270, 260, 250, 245, 240, 238],
            volumePerMin: [0.5, -1.2, 0.8, 1.5, -0.4, 3.1, 2.0, -0.8, -1.5, 0.2, 0.4, -0.6, 1.1, 0.9, 2.4, 0.3, -0.2, -1.0, -0.7, 0.1],
            suddenAtSec: [372, 845],
            moments: [Moment(minute: 6, note: "笑いで声が上ずる", level: 2), Moment(minute: 14, note: "話題が急に変わる", level: 1)])
        a.calmPerMin = [0.2, 0.3, 0.2, 0.4, 0.5, 0.9, 1.6, 0.8, 0.4, 0.3, 0.2, 0.3, 0.4, 0.7, 1.1, 0.6, 0.3, 0.2, 0.2, 0.1]
        a.contentSummary = "冬に布団を買い替えた話から、実家の毛布の思い出へ移ります。後半はお便りを2通読みます。"
        out["plant-81"] = a
        return out
    }()

    static let sleepPoints: [String: [SleepPoint]] = {
        let cal = Calendar(identifier: .gregorian)
        let days = [(10, 18, 19), (10, 22, 16), (10, 25, 38), (10, 29, 12), (11, 1, 14), (11, 5, 11), (11, 8, 9), (11, 12, 6)]
        return ["plant": days.compactMap { m, d, v in
            cal.date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Tokyo"), year: 2026, month: m, day: d))
                .map { SleepPoint(night: $0, minutes: v) }
        }]
    }()
}
