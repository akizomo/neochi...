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
    let player = PlayerService()
    let health = HealthService()
    /// 保存した記録(端末内)。
    var logs: [SleepLog] = LogStore.load()
    /// 今夜の再生の入眠(確認できたときだけ)と、再生開始の時刻・回。
    var onsetAt: Date?
    var playStartedAt: Date?
    var playEpisodeID: String?
    var playShowID: String?

    /// いまの時刻。デバッグ時だけ、環境変数 NEOCHI_NOW(例 2026-11-13T22:30:00+09:00)で差し替えて、時間帯を試せる。
    var now: () -> Date = AppModel.defaultClock
    static func defaultClock() -> Date {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["NEOCHI_NOW"], let d = ISO8601DateFormatter().date(from: s) { return d }
        #endif
        return Date()
    }
    /// 初回に聞いた、ふだんの就寝時刻(時刻だけを使う)。聞いたかどうかも覚える。
    var bedtimeFallback: Date? = UserDefaults.standard.object(forKey: "bedtimeFallback") as? Date
    var bedtimeAsked = UserDefaults.standard.bool(forKey: "bedtimeAsked")

    /// ヘルスケアの履歴から読んだ、晩ごとの就寝時刻。確認が済んだら healthChecked。
    var healthStarts: [Date] = []
    var healthChecked = false

    /// 履歴が足りないときだけ、就寝時刻を聞く。
    var needsBedtimeQuestion: Bool {
        healthChecked && !bedtimeAsked && healthStarts.count < BedtimeWindow.minimumSamples
    }

    func loadHealthBedtimes() async {
        do {
            try await health.requestAuthorization()
            let raw = try await health.sleepStarts()
            healthStarts = BedtimeWindow.nightlyStarts(from: raw, calendar: .current)
        } catch { healthStarts = [] }
        healthChecked = true
        openNightIfBedtime()
    }

    /// 記録タブに出す、ふだんの就寝時刻。履歴が十分なら自動(中央値)、足りなければ手で決めたもの。
    var bedtimeIsAuto: Bool { BedtimeWindow.typicalMinute(starts: healthStarts, calendar: .current) != nil }
    var bedtimeMinute: Int? {
        if let m = BedtimeWindow.typicalMinute(starts: healthStarts, calendar: .current) { return m }
        return bedtimeFallback.map { Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
    }

    func saveBedtime(_ date: Date?, openNight: Bool = true) {
        bedtimeFallback = date; bedtimeAsked = true
        UserDefaults.standard.set(date, forKey: "bedtimeFallback")
        UserDefaults.standard.set(true, forKey: "bedtimeAsked")
        if openNight { openNightIfBedtime() }
    }

    var inBedtimeWindow: Bool {
        BedtimeWindow.isInWindow(now: now(), starts: history.map(\.playedAt) + healthStarts, fallback: bedtimeFallback, calendar: .current)
    }

    /// 就寝の時間帯にアプリを開いたら、昼の画面ではなく夜の画面を出す。
    func openNightIfBedtime() {
        guard nightScreen == nil, inBedtimeWindow else { return }
        nightScreen = playing == nil ? .ready : .playing
    }

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

    /// 朝の振り返りに出す寝落ちまでの分。ヘルスケアから確認できなければ nil。
    var pendingLatency: Int? {
        guard let s = playStartedAt, let o = onsetAt else { return lastNight?.minutes }
        return max(0, Int((o.timeIntervalSince(s) / 60).rounded()))
    }

    func refreshOnset() async {
        guard let s = playStartedAt else { return }
        do {
            try await health.requestAuthorization()
            onsetAt = try await health.sleepOnset(after: s)
        } catch { onsetAt = nil }
    }

    /// 「記録する」で保存。入力は任意。
    func saveLog(interest: InterestAnswer?, calm: Int?, note: String) {
        guard let s = playStartedAt, let ep = playEpisodeID, let show = playShowID else { pendingMorning = false; return }
        let listenNo = history.filter { $0.episodeID == ep }.count
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = SleepLog(id: UUID().uuidString, episodeID: ep, showID: show, startedAt: s, sleepOnsetAt: onsetAt,
                           source: onsetAt == nil ? .selfReport : .watch, interestVote: interest?.rawValue, calmVote: calm,
                           note: trimmed.isEmpty ? nil : trimmed, listenNo: max(1, listenNo))
        logs.append(log)
        if let m = log.latencyMinutes { lastNight = LastNight(showID: show, episodeID: ep, minutes: m) }
        pendingMorning = false
        playStartedAt = nil; onsetAt = nil
        LogStore.save(logs)
        Task { try? await SupabaseClient.shared.upload(log) }
    }

    /// 番組と回を読み込む。未設定や失敗のときは、いまの内容のまま(端末内だけで動く)。
    func loadRemote() async {
        guard SupabaseClient.shared.isConfigured else { return }
        guard let fetched = try? await SupabaseClient.shared.fetchShows(), !fetched.isEmpty,
              let e = try? await SupabaseClient.shared.fetchEpisodes() else { return }
        var s = fetched
        if let a = try? await SupabaseClient.shared.fetchAspects(episodes: e) {
            for i in s.indices { if let (asp, line) = a[s[i].id] { s[i].aspects = asp; s[i].oneLiner = line } }
        }
        shows = s; episodes = e
        // 見本の状態は、実データには存在しない番組を指すので外す。
        let r = SessionState(history: history, favorites: favorites, queue: queue, currentShowID: currentShowID,
                             lastNight: lastNight, genreStreakNights: genreStreakNights, pendingMorning: pendingMorning,
                             reservedShowIDs: reservations.mapValues { $0.show.id })
            .reconciled(toShowIDs: Set(s.map(\.id)))
        history = r.history; favorites = r.favorites; queue = r.queue; currentShowID = r.currentShowID
        lastNight = r.lastNight; genreStreakNights = r.genreStreakNights; pendingMorning = r.pendingMorning
        reservations = reservations.filter { r.reservedShowIDs[$0.key] != nil }
    }

    func slate(night: Int) -> [Candidate] { TonightEngine.slate(night: night, ctx: context) }

    func toggleFavorite(_ show: Show) {
        if favorites.contains(show.id) { favorites.remove(show.id) } else { favorites.insert(show.id) }
    }

    func reserve(night: Int, _ candidate: Candidate) { reservations[night] = candidate }
    func cancelReservation(night: Int) { reservations[night] = nil }

    /// 夜の画面を閉じて、再生を止める。朝の振り返りは、そのまま残る。
    func endPlayback() {
        player.stop()
        playing = nil
        nightScreen = nil
    }

    /// 再生を始める。再生した番組が、次の「いまの番組」になる。
    func play(_ candidate: Candidate) {
        if let ep = candidate.episode {
            history.append(PlayRecord(episodeID: ep.id, showID: candidate.show.id, playedAt: Date()))
        }
        currentShowID = candidate.show.id
        playStartedAt = Date(); onsetAt = nil
        playEpisodeID = candidate.episode?.id; playShowID = candidate.show.id
        pendingMorning = true
        playing = candidate
        player.start(url: candidate.episode?.audioURL, title: candidate.show.title)
        if nightScreen == nil { nightScreen = .playing }
    }
}
