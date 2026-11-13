import Foundation
import Observation
import NeochiCore

/// 画面の状態。判断は NeochiCore の TonightEngine に任せる。
@MainActor
@Observable
final class AppModel {
    var shows: [Show]
    var episodes: [String: [Episode]]
    var history: [PlayRecord]
    var favorites: Set<String>
    var queue: [String]
    var currentShowID: String?
    var lastNight: LastNight?
    var genreStreakNights: Int
    /// 晩(0 = 今夜、1 = 明日…)ごとの予約。
    var reservations: [Int: Candidate] = [:]
    /// 朝の振り返りが済んでいないか。
    var pendingMorning: Bool
    var nightScreen: NightScreen?
    var morningOpen = false
    var playing: Candidate?

    enum NightScreen: String, Identifiable { case ready, playing; var id: String { rawValue } }

    init(shows: [Show], episodes: [String: [Episode]], history: [PlayRecord] = [], favorites: Set<String> = [],
         queue: [String] = [], currentShowID: String? = nil, lastNight: LastNight? = nil,
         genreStreakNights: Int = 0, pendingMorning: Bool = false) {
        self.shows = shows; self.episodes = episodes; self.history = history; self.favorites = favorites
        self.queue = queue; self.currentShowID = currentShowID; self.lastNight = lastNight
        self.genreStreakNights = genreStreakNights; self.pendingMorning = pendingMorning
    }

    static func sample() -> AppModel {
        AppModel(shows: SampleData.shows, episodes: SampleData.episodeMap,
                 history: [PlayRecord(episodeID: "phonebook-7", showID: "phonebook", playedAt: Date().addingTimeInterval(-86400))],
                 favorites: ["phonebook", "plant", "train"], currentShowID: "phonebook",
                 lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 18),
                 genreStreakNights: 3, pendingMorning: true)
    }

    var context: TonightContext {
        TonightContext(shows: shows, episodes: episodes, history: history, favorites: favorites, queue: queue,
                       currentShowID: currentShowID, lastNight: lastNight, genreStreakNights: genreStreakNights)
    }

    func slate(night: Int) -> [Candidate] { TonightEngine.slate(night: night, ctx: context) }

    func toggleFavorite(_ show: Show) {
        if favorites.contains(show.id) { favorites.remove(show.id) } else { favorites.insert(show.id) }
    }

    func reserve(night: Int, _ candidate: Candidate) { reservations[night] = candidate }
    func cancelReservation(night: Int) { reservations[night] = nil }

    /// 再生を始める。再生した番組が、次の「いまの番組」になる。
    func play(_ candidate: Candidate) {
        if let ep = candidate.episode {
            history.append(PlayRecord(episodeID: ep.id, showID: candidate.show.id, playedAt: Date()))
        }
        currentShowID = candidate.show.id
        playing = candidate
        nightScreen = .playing
    }
}
