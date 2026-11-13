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
        "phonebook": episodes("phonebook", top: 7), "plant": episodes("plant", top: 12),
        "train": episodes("train", top: 31), "weather": episodes("weather", top: 88), "port": episodes("port", top: 204),
    ]
}
