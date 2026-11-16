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
    /// 聴く晩ごとの予約。キーは、その晩の日付(`nightDay`)。日をまたぐと、明日の予約は自然に今夜になる。
    var reservations: [Date: Candidate] = [:]
    /// 朝の振り返りが済んでいないか。
    var pendingMorning: Bool
    var nightScreen: NightScreen?
    var morningOpen = false
    var playing: Candidate?
    let player = PlayerService()
    let health = HealthService()
    /// 保存した記録(端末内)。
    /// 回ごとの解析(根拠のデータ込み)。
    var analyses: [String: EpisodeAnalysis] = [:]
    /// 番組ごとの実績の点(古い順)。番組の詳細の「寝落ちの実績」で使う。
    var sleepPoints: [String: [SleepPoint]] = [:]
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
        restorePendingNight()
    }

    /// 再生した晩のこと。夜のうちにアプリが終了されても、朝に振り返りを出せるよう、端末に残す。
    private struct PendingNight: Codable {
        var startedAt: Date; var episodeID: String?; var showID: String?
    }
    private static let pendingNightKey = "pendingNight"

    private func savePendingNight() {
        guard pendingMorning, let s = playStartedAt else {
            UserDefaults.standard.removeObject(forKey: Self.pendingNightKey); return
        }
        let v = PendingNight(startedAt: s, episodeID: playEpisodeID, showID: playShowID)
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: Self.pendingNightKey)
    }

    private func restorePendingNight() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingNightKey),
              let v = try? JSONDecoder().decode(PendingNight.self, from: data) else { return }
        playStartedAt = v.startedAt; playEpisodeID = v.episodeID; playShowID = v.showID
        pendingMorning = true
    }

    /// 番組の読み込みの状態。Release で接続先があるときは、見本の番組を出さず、読み込めるまで待つ(取り違えを防ぐ)。
    enum LoadState: Equatable { case loading, ready, failed }
    var loadState: LoadState = .ready

    /// 起動時の状態。DEBUG と、接続先がないときは見本で動く。Release で接続先があるときは、空から読み込む。
    static func launch() -> AppModel {
        #if DEBUG
        return sample()
        #else
        guard SupabaseClient.shared.isConfigured else { return sample() }
        let m = AppModel(shows: [], episodes: [:])
        m.loadState = .loading
        return m
        #endif
    }

    /// 読み込みをやり直す(読み込めなかったとき)。
    func reload() async {
        if loadState == .failed { loadState = .loading }
        await loadRemote()
    }

    private func loadFailed(_ status: String) {
        remoteStatus = status
        if loadState == .loading { loadState = .failed }
    }

    static func sample() -> AppModel {
        let m = AppModel(shows: SampleData.shows, episodes: SampleData.episodeMap,
                 history: [PlayRecord(episodeID: "phonebook-7", showID: "phonebook", playedAt: Date().addingTimeInterval(-86400))],
                 favorites: ["phonebook", "plant", "train"], currentShowID: "phonebook",
                 lastNight: LastNight(showID: "phonebook", episodeID: "phonebook-7", minutes: 18),
                 genreStreakNights: 3, pendingMorning: true)
        m.analyses = SampleData.analyses
        m.sleepPoints = SampleData.sleepPoints
        return m
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
        guard let s = playStartedAt, let ep = playEpisodeID, let show = playShowID else {
            pendingMorning = false; savePendingNight(); return
        }
        let listenNo = history.filter { $0.episodeID == ep }.count
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = SleepLog(id: UUID().uuidString, episodeID: ep, showID: show, startedAt: s, sleepOnsetAt: onsetAt,
                           source: onsetAt == nil ? .selfReport : .watch, interestVote: interest?.rawValue, calmVote: calm,
                           note: trimmed.isEmpty ? nil : trimmed, listenNo: max(1, listenNo))
        logs.append(log)
        if let m = log.latencyMinutes { lastNight = LastNight(showID: show, episodeID: ep, minutes: m) }
        pendingMorning = false
        playStartedAt = nil; onsetAt = nil
        savePendingNight()
        LogStore.save(logs)
        Task { try? await SupabaseClient.shared.upload(log) }
    }

    /// 記録のメモをあとから直す(空にすると消す)。
    func updateNote(logID: String, note: String) {
        guard let i = logs.firstIndex(where: { $0.id == logID }) else { return }
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: String? = t.isEmpty ? nil : t
        guard logs[i].note != new else { return }
        logs[i].note = new
        LogStore.save(logs)
        let log = logs[i]
        Task { try? await SupabaseClient.shared.upload(log) }
    }

    /// 読み込みの結果(確認用)。どこで失敗したかをここに残す。
    var remoteStatus = "未接続(端末内の見本で動作)"

    /// 番組と回を読み込む。未設定や失敗のときは、いまの内容のまま(端末内だけで動く)。
    func loadRemote() async {
        guard SupabaseClient.shared.isConfigured else { return }
        #if DEBUG
        // 見本だけで画面を確かめる(起動引数 -sampleOnly)。
        if ProcessInfo.processInfo.arguments.contains("-sampleOnly") { remoteStatus = "見本のみ(-sampleOnly)"; return }
        #endif
        let fetched: [Show]
        do { fetched = try await SupabaseClient.shared.fetchShows() }
        catch { loadFailed("番組の読み込みに失敗: \(error)"); return }
        guard !fetched.isEmpty else { loadFailed("番組が0件(show が空、または読み取りの権限がない)"); return }
        let e: [String: [Episode]]
        do { e = try await SupabaseClient.shared.fetchEpisodes() }
        catch { loadFailed("回の読み込みに失敗: \(error)"); return }
        var s = fetched
        var notes: [String] = []
        var list: [EpisodeAnalysis] = []
        do { list = try await SupabaseClient.shared.fetchAnalyses() } catch { notes.append("解析の読み込みに失敗: \(error)") }
        var stats: [String: ShowStats] = [:]
        do { stats = try await SupabaseClient.shared.fetchStats() } catch { notes.append("実績の読み込みに失敗: \(error)") }
        var points: [String: [SleepPoint]] = [:]
        do { points = try await SupabaseClient.shared.fetchSleepPoints() } catch { notes.append("実績の点の読み込みに失敗: \(error)") }
        let showOf = Dictionary(uniqueKeysWithValues: e.flatMap { $0.value }.map { ($0.id, $0.showID) })
        for i in s.indices {
            let mine = list.filter { showOf[$0.episodeID] == s[i].id }
            if !mine.isEmpty { s[i].aspects = EpisodeAnalysis.aspects(mine); s[i].oneLiner = mine.first?.reason }
            if let st = stats[s[i].id] { s[i].stats = st; s[i].avgMinutes = st.avgMinutes }
        }
        analyses = Dictionary(list.map { ($0.episodeID, $0) }, uniquingKeysWith: { a, _ in a })
        shows = s; episodes = e; sleepPoints = points
        loadState = .ready
        remoteStatus = "番組\(s.count)・回\(e.values.reduce(0) { $0 + $1.count })・解析\(list.count)・実績\(stats.count)" + (notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n"))
        // 見本の状態は、実データには存在しない番組を指すので外す。
        let r = SessionState(history: history, favorites: favorites, queue: queue, currentShowID: currentShowID,
                             lastNight: lastNight, genreStreakNights: genreStreakNights, pendingMorning: pendingMorning,
                             reservedShowIDs: [:])
            .reconciled(toShowIDs: Set(s.map(\.id)))
        history = r.history; favorites = r.favorites; queue = r.queue; currentShowID = r.currentShowID
        lastNight = r.lastNight; genreStreakNights = r.genreStreakNights; pendingMorning = r.pendingMorning
        reservations = reservations.filter { entry in s.contains(where: { $0.id == entry.value.show.id }) }
    }

    func slate(night: Int) -> [Candidate] { TonightEngine.slate(night: night, ctx: context) }

    /// 操作の結果を、画面の下に短く出す(約2秒)。
    var toast: Toast?
    struct Toast: Equatable, Identifiable { let id = UUID(); let text: String }
    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = Toast(text: text)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { toast = nil }
        }
    }

    func toggleFavorite(_ show: Show) {
        if favorites.contains(show.id) {
            favorites.remove(show.id)
        } else {
            favorites.insert(show.id); showToast("お気に入りに追加しました")
        }
    }

    func toggleQueue(_ show: Show) {
        if let i = queue.firstIndex(of: show.id) {
            queue.remove(at: i)
        } else {
            queue.append(show.id); showToast("「次に聴く」に入れました")
        }
    }

    /// night(0 = 今夜、1 = 明日)の晩の日付。午前4時までは、まだ前の日の晩とみなす。
    func nightDay(_ night: Int) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: now().addingTimeInterval(-4 * 3600))
        return cal.date(byAdding: .day, value: night, to: base) ?? base
    }

    /// 朝の振り返りを出してよいか。聴いた晩が明けてから(午前4時を過ぎてから)。同じ日のうちは出さない。
    var morningDue: Bool {
        guard pendingMorning else { return false }
        guard let s = playStartedAt else { return true }   // 前回の起動から残った分
        let cal = Calendar.current
        let startNight = cal.startOfDay(for: s.addingTimeInterval(-4 * 3600))
        return nightDay(0) > startNight
    }

    func reservation(night: Int) -> Candidate? { reservations[nightDay(night)] }

    func reserve(night: Int, _ candidate: Candidate) {
        let today = nightDay(0)
        reservations = reservations.filter { $0.key >= today }   // 過ぎた晩の予約は捨てる
        reservations[nightDay(night)] = candidate
        showToast(night == 0 ? "今夜聴くに決めました" : "明日聴くに決めました")
    }
    /// 今夜の予約が、この番組か。
    func isReservedTonight(_ show: Show) -> Bool { reservation(night: 0)?.show.id == show.id }

    /// 番組を指定して、今夜聴くを予約する。予約済みなら取り消す。候補にない番組でも、その番組自体を予約する。
    func toggleTonight(_ show: Show) {
        if isReservedTonight(show) { cancelReservation(night: 0); return }
        if let c = slate(night: 0).first(where: { $0.show.id == show.id }) ?? TonightEngine.listenNow(show: show, ctx: context) {
            reserve(night: 0, c)
        }
    }

    func cancelReservation(night: Int) {
        reservations[nightDay(night)] = nil
        showToast("予約を取り消しました")
    }

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
        savePendingNight()
        playing = candidate
        if let ep = candidate.episode {
            player.start(url: ep.audioURL, title: ep.title, subtitle: candidate.show.title)
        } else {
            player.start(url: nil, title: candidate.show.title)
        }
        if nightScreen == nil { nightScreen = .playing }
    }
}
