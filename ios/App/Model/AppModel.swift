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
    /// ヘルスケアに入眠はあったが、音が止まってから30分より後だった(聴きながらの寝落ちではない)。
    var onsetAfterPlayback = false
    var playStartedAt: Date?
    /// 音が最後に鳴っていた時刻。入眠を寝落ちとみなすかに使う(`SleepAttribution`)。
    var playLastAudibleAt: Date?
    private var lastAudibleSavedAt: Date?
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

    /// 最初に聞いた、好みのジャンル。記録がないうちの、最初の番組と並びに使う。聞いたかどうかも覚える。
    var preferredGenres: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "preferredGenres") ?? [])
    var genresAsked = UserDefaults.standard.bool(forKey: "genresAsked")

    /// 初回のオンボーディング(OnboardingView)が済んだか。前の版でジャンルを答えた人は、済んだものとする。
    var onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone") || UserDefaults.standard.bool(forKey: "genresAsked")
    /// 番組が読み込めたら、オンボーディングを出す(1度だけ)。
    var needsOnboarding: Bool { loadState == .ready && !shows.isEmpty && !onboardingDone && healthChecked }
    var onboardingOpen = false

    func finishOnboarding() {
        onboardingDone = true; UserDefaults.standard.set(true, forKey: "onboardingDone")
        if !genresAsked { savePreferredGenres(preferredGenres) }
        onboardingOpen = false
        openNightIfBedtime()
    }

    func savePreferredGenres(_ genres: Set<String>) {
        preferredGenres = genres; genresAsked = true
        UserDefaults.standard.set(Array(genres).sorted(), forKey: "preferredGenres")
        UserDefaults.standard.set(true, forKey: "genresAsked")
    }

    /// 表示中のタブ。空の状態から「見つける」へ案内するために、画面の外から切り替える。
    enum AppTab: Hashable { case tonight, discover, log, settings }
    var selectedTab: AppTab = .tonight

    /// ヘルスケアの履歴から読んだ、晩ごとの就寝時刻。確認が済んだら healthChecked。
    var healthStarts: [Date] = []
    var healthChecked = false

    /// 起動時。許可は求めない(求めるのは、オンボーディングの説明のあとと、設定から)。許可を聞いたあとなら、履歴を読む。
    /// 就寝時刻は聞かない。ヘルスケアの履歴か、聴いた記録がたまると自動で決まり、設定から手でも決められる。
    func loadHealthBedtimes() async {
        let access = await health.access()
        healthAccess = access
        if access == .asked {
            do {
                let raw = try await health.sleepStarts()
                healthStarts = BedtimeWindow.nightlyStarts(from: raw, calendar: .current)
            } catch { healthStarts = [] }
        } else { healthStarts = [] }
        healthChecked = true
        if onboardingDone { openNightIfBedtime() }
    }

    /// 設定に出す、ふだんの就寝時刻。履歴が十分なら自動(中央値)、足りなければ手で決めたもの。
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
        guard nightScreen == nil, !morningOpen, inBedtimeWindow else { return }
        nightScreenNight = nightDay(0)
        nightScreenAuto = playing == nil
        nightScreen = playing == nil ? .ready : .playing
    }

    enum NightScreen: String, Identifiable { case ready, playing; var id: String { rawValue } }

    /// 就寝の時間帯に開いたので、夜の画面を自動で出したか。夜の画面に、なぜ切り替わったかを書くために使う。
    var nightScreenAuto = false

    /// ふだんの就寝時刻の言い方(「23:00ごろ」)。分からなければ nil。
    var bedtimeText: String? { bedtimeMinute.map { String(format: "%d:%02dごろ", $0 / 60, $0 % 60) } }

    /// 夜の画面を出した晩(`nightDay(0)`)。朝になって、その晩が明けたかを見る。
    private var nightScreenNight: Date?

    /// アプリを開いたとき(起動・前に戻したとき)に、晩が明けていたら切り替える。
    /// - 夜の画面が出たままなら閉じて、再生を止める(夜のうちに眠って、そのままになっていた分)
    /// - 聴いた晩の振り返りが残っていれば、朝の振り返りを自動で出す
    /// - 過ぎた晩の予約を捨てる
    func refreshForNewDay() {
        let tonight = nightDay(0)
        if reservations.keys.contains(where: { $0 < tonight }) {
            reservations = reservations.filter { $0.key >= tonight }
            persistSession()
        }
        let nightOver = nightScreenNight.map { $0 < tonight } ?? false
        if nightScreen != nil && nightOver && !inBedtimeWindow { endPlayback() }
        // 朝の振り返りを自動で出すのは、1日1回まで(「あとで」で閉じたら、その日はもう出さない。今夜タブの「昨夜の結果」からは開ける)。
        // 就寝の時間帯(また夜になった)には出さない。夜の画面を優先する。
        let autoShown = UserDefaults.standard.object(forKey: Self.morningAutoKey) as? Date
        if morningDue && !morningOpen && !onboardingOpen && !inBedtimeWindow && autoShown != tonight {
            let wasOpen = nightScreen != nil
            if wasOpen { endPlayback() }
            UserDefaults.standard.set(tonight, forKey: Self.morningAutoKey)
            // 全画面の画面は、同時に2つ出せない。夜の画面が閉じてから出す。
            Task { @MainActor in
                if wasOpen { try? await Task.sleep(for: .milliseconds(600)) }
                if morningDue && !morningOpen && nightScreen == nil { morningOpen = true }
            }
        }
    }
    private static let morningAutoKey = "morningAutoShownDay"

    init(shows: [Show], episodes: [String: [Episode]], history: [PlayRecord] = [], favorites: Set<String> = [],
         queue: [String] = [], currentShowID: String? = nil, lastNight: LastNight? = nil,
         genreStreakNights: Int = 0, pendingMorning: Bool = false) {
        self.shows = shows; self.episodes = episodes; self.history = history; self.favorites = favorites
        self.queue = queue; self.currentShowID = currentShowID; self.lastNight = lastNight
        self.genreStreakNights = genreStreakNights; self.pendingMorning = pendingMorning
        restorePendingNight()
        player.onAudible = { [weak self] t in self?.noteAudible(t) }
    }

    /// 音が鳴っている。端末への保存は1分ごと(夜のうちにアプリが終了されても、朝に分かるように)。
    private func noteAudible(_ t: Date) {
        guard playStartedAt != nil else { return }
        playLastAudibleAt = t
        if lastAudibleSavedAt.map({ t.timeIntervalSince($0) >= 60 }) ?? true {
            lastAudibleSavedAt = t
            savePendingNight()
        }
    }

    /// 再生した晩のこと。夜のうちにアプリが終了されても、朝に振り返りを出せるよう、端末に残す。
    private struct PendingNight: Codable {
        var startedAt: Date; var episodeID: String?; var showID: String?
        /// 前の版で残った晩には無い(nil)。
        var lastAudibleAt: Date?
    }
    private static let pendingNightKey = "pendingNight"

    private func savePendingNight() {
        guard pendingMorning, let s = playStartedAt else {
            UserDefaults.standard.removeObject(forKey: Self.pendingNightKey); return
        }
        let v = PendingNight(startedAt: s, episodeID: playEpisodeID, showID: playShowID, lastAudibleAt: playLastAudibleAt)
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: Self.pendingNightKey)
    }

    private func restorePendingNight() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingNightKey),
              let v = try? JSONDecoder().decode(PendingNight.self, from: data) else { return }
        playStartedAt = v.startedAt; playEpisodeID = v.episodeID; playShowID = v.showID
        playLastAudibleAt = v.lastAudibleAt
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
        m.restoreSession()
        m.persistsSession = true
        m.loadState = .loading
        return m
        #endif
    }

    /// 読み込みをやり直す(読み込めなかったとき)。
    func reload() async {
        if loadState == .failed { loadState = .loading }
        await loadRemote()
    }

    /// 引っぱって更新。番組・話・解析を読み直す。朝の結果が「確認中」なら、ヘルスケアの記録も読み直す。
    /// 読み込めなかったときは、いまの内容のまま(画面は変えない)。
    func refresh() async {
        await loadRemote()
        if pendingMorning { await refreshOnset(); dropNightIfNotWhileListening() }
        await backfillOnsets()
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
        #if DEBUG
        // 見本: 起動引数 -noMeasure で、ヘルスケアに入眠が入っていない朝にする(自己申告の画面を確かめる用)
        if ProcessInfo.processInfo.arguments.contains("-noMeasure") { m.lastNight = nil }
        // 見本: 最近の夜の記録(寝落ちまでの分のグラフを確かめる用)。端末には保存しない。
        if m.logs.isEmpty {
            for (i, mins) in [34, 22, 14, 41, 9].enumerated() {
                let start = Date().addingTimeInterval(-Double(6 - i) * 86400)
                m.logs.append(SleepLog(id: "sample-\(i)", episodeID: "phonebook-\(7 - i)", showID: "phonebook", startedAt: start,
                                      sleepOnsetAt: start.addingTimeInterval(Double(mins) * 60), source: .watch,
                                      interestRating: 6, calmVote: 4))
            }
        }
        #endif
        return m
    }

    var context: TonightContext {
        TonightContext(shows: shows, episodes: episodes, history: history, favorites: favorites, queue: queue,
                       currentShowID: currentShowID, lastNight: lastNight, genreStreakNights: genreStreakNights,
                       preferredGenres: preferredGenres)
    }

    /// 朝の振り返りに出す寝落ちまでの分。ヘルスケアから確認できなければ nil(前の晩の分数は出さない)。
    var pendingLatency: Int? {
        guard let s = playStartedAt else { return lastNight?.minutes }   // 見本
        guard let o = onsetAt else { return nil }
        return max(0, Int((o.timeIntervalSince(s) / 60).rounded()))
    }

    /// ヘルスケアの許可の状態(設定で案内に使う)。
    var healthAccess: HealthService.Access = .asked
    /// 過去30日に睡眠データを受け取れたか(nil = 確認前)。許可の「あるか」は分からないので、実際に読めたかで連携の状態とする。
    var healthHasData: Bool?
    func refreshHealthAccess() async {
        healthAccess = await health.access()
        if healthAccess == .asked {
            healthHasData = ((try? await health.sleepStarts(days: 30)) ?? []).isEmpty == false
        } else { healthHasData = nil }
    }

    /// 「許可する」。まだ聞いていないときだけ、システムの許可画面が出る。聞いたあとは、ヘルスケアの設定でしか変えられない。
    func requestHealth() async {
        try? await health.requestAuthorization()
        await refreshHealthAccess()
        await loadHealthBedtimes()
    }

    /// ヘルスケアの睡眠データが入る人か(過去30日に受け取れた)。朝に入眠が出ないときの案内の出し分けに使う。
    var hasHealthSleepData: Bool { healthHasData == true }

    /// 入眠がまだ分からないまま保存した晩を、ヘルスケアに反映された分から埋める(最大3日前まで)。
    /// 朝すぐはまだ入っていないことが多いので、アプリを開くたびに確かめる。埋まったら、実測の記録に変えてサーバーにも反映する。
    func backfillOnsets() async {
        guard healthAccess == .asked else { return }
        let from = now().addingTimeInterval(-3 * 86400)
        var changed = false
        for i in logs.indices where logs[i].source == .selfReport && logs[i].sleepOnsetAt == nil && logs[i].startedAt > from {
            let raw = try? await health.sleepOnset(after: logs[i].startedAt)
            guard case .onset(let onset) = SleepAttribution.judge(onset: raw, lastAudible: logs[i].lastAudibleAt) else { continue }
            logs[i].sleepOnsetAt = onset
            logs[i].source = .watch
            logs[i].selfReport = nil
            if let m = logs[i].latencyMinutes { lastNight = LastNight(showID: logs[i].showID, episodeID: logs[i].episodeID, minutes: m) }
            let log = logs[i]
            Task { try? await SupabaseClient.shared.upload(log) }
            changed = true
        }
        if changed { LogStore.save(logs); persistSession() }
    }

    /// 朝、振り返りを出す前に、ヘルスケアで確かめる。聴きながら眠った晩でなければ(夕方に試しで聴いただけ、など)、
    /// 振り返りは出さずに、その晩を捨てる。入眠がまだ分からないときは、そのまま(あとで、もう一度確かめる)。
    func settleMorning() async {
        guard morningDue, !morningOpen else { return }
        await refreshOnset()
        dropNightIfNotWhileListening()
    }

    private func dropNightIfNotWhileListening() {
        guard onsetAfterPlayback, !morningOpen else { return }
        pendingMorning = false
        playStartedAt = nil; onsetAt = nil; onsetAfterPlayback = false; playLastAudibleAt = nil
        savePendingNight()
        persistSession()
    }

    func refreshOnset() async {
        guard let s = playStartedAt else { return }
        let raw = try? await health.sleepOnset(after: s)
        switch SleepAttribution.judge(onset: raw, lastAudible: playLastAudibleAt) {
        case .onset(let d): onsetAt = d; onsetAfterPlayback = false
        case .afterPlayback: onsetAt = nil; onsetAfterPlayback = true
        case .unknown: onsetAt = nil; onsetAfterPlayback = false
        }
    }

    /// 「記録する」で保存。入力は任意。
    func saveLog(interest: Int?, calm: Int?, note: String, selfReport: SelfReportLatency? = nil) {
        guard let s = playStartedAt, let ep = playEpisodeID, let show = playShowID else {
            pendingMorning = false; savePendingNight(); return
        }
        let listenNo = history.filter { $0.episodeID == ep }.count
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = SleepLog(id: UUID().uuidString, episodeID: ep, showID: show, startedAt: s, sleepOnsetAt: onsetAt,
                           source: onsetAt == nil ? .selfReport : .watch, interestRating: interest, calmVote: calm,
                           note: trimmed.isEmpty ? nil : trimmed, listenNo: max(1, listenNo),
                           selfReport: onsetAt == nil ? selfReport : nil, lastAudibleAt: playLastAudibleAt)
        logs.append(log)
        if let m = log.latencyMinutes { lastNight = LastNight(showID: show, episodeID: ep, minutes: m) }
        pendingMorning = false
        playStartedAt = nil; onsetAt = nil; onsetAfterPlayback = false; playLastAudibleAt = nil
        savePendingNight()
        LogStore.save(logs)
        persistSession()
        Task { try? await SupabaseClient.shared.upload(log) }
    }

    /// 記録をすべて削除する。サーバーの記録を先に消し、消せたら端末の記録も消す(サーバーで失敗したときは、何も消さない)。
    func deleteAllRecords() async throws {
        if SupabaseClient.shared.isConfigured { try await SupabaseClient.shared.deleteMyRecords() }
        logs = []
        LogStore.save(logs)
        lastNight = nil
        persistSession()
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

    /// 評価(引き込み力・起伏)をあとから直す。空にもできる。サーバーにも反映する。
    func updateRatings(logID: String, interest: Int?, calm: Int?) {
        guard let i = logs.firstIndex(where: { $0.id == logID }) else { return }
        guard logs[i].interestRating != interest || logs[i].calmVote != calm else { return }
        logs[i].interestRating = interest
        logs[i].interestVote = nil          // 古い3択は、10段階に置き換わる
        logs[i].calmVote = calm
        LogStore.save(logs)
        let log = logs[i]
        Task { try? await SupabaseClient.shared.upload(log) }
    }

    /// 最近の夜の、寝落ちまでの分数(実測だけ。古い順)。`including` は、まだ保存していない今夜の分。
    func recentNights(upTo date: Date? = nil, limit: Int = 7, including current: (date: Date, minutes: Int)? = nil,
                      currentLogID: String? = nil) -> [RecentNightsChart.Night] {
        var out: [RecentNightsChart.Night] = logs.compactMap { l in
            guard l.source == .watch, let m = l.latencyMinutes, date.map({ l.startedAt <= $0 }) ?? true else { return nil }
            return .init(id: l.id, date: l.startedAt, minutes: m, current: l.id == currentLogID)
        }
        if let c = current { out.append(.init(id: "current", date: c.date, minutes: c.minutes, current: true)) }
        out.sort { $0.date < $1.date }
        // 同じ日に何本かあるときは、日ごとに最後の1本にする(棒が重ならないように)
        var byDay: [Date: RecentNightsChart.Night] = [:]
        for n in out { byDay[Calendar.current.startOfDay(for: n.date)] = n }
        return Array(byDay.values.sorted { $0.date < $1.date }.suffix(limit))
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
        catch { loadFailed("話の読み込みに失敗: \(error)"); return }
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
        remoteStatus = "番組\(s.count)・話\(e.values.reduce(0) { $0 + $1.count })・解析\(list.count)・実績\(stats.count)" + (notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n"))
        // 見本の状態は、実データには存在しない番組を指すので外す。
        let r = SessionState(history: history, favorites: favorites, queue: queue, currentShowID: currentShowID,
                             lastNight: lastNight, genreStreakNights: genreStreakNights, pendingMorning: pendingMorning,
                             reservedShowIDs: [:])
            .reconciled(toShowIDs: Set(s.map(\.id)))
        history = r.history; favorites = r.favorites; queue = r.queue; currentShowID = r.currentShowID
        lastNight = r.lastNight; genreStreakNights = r.genreStreakNights; pendingMorning = r.pendingMorning
        reservations = reservations.filter { entry in s.contains(where: { $0.id == entry.value.show.id }) }
        restoreReservations()
        persistSession()
    }

    /// 端末に保存した状態(お気に入り・次に聴く・再生の記録)。実データで動くときだけ保存する(見本の状態は保存しない)。
    var persistsSession = false

    func restoreSession() {
        guard let r = SessionStore.load() else { return }
        history = r.history; favorites = r.favorites; queue = r.queue; currentShowID = r.currentShowID
        lastNight = r.lastNight; genreStreakNights = r.genreStreakNights
        savedReservations = r.reservations ?? []
    }

    /// 保存した予約。番組が読み込めてから、予約に戻す(restoreReservations)。
    private var savedReservations: [SavedReservation] = []

    func restoreReservations() {
        let today = nightDay(0)
        for r in savedReservations where r.night >= today {
            guard let show = shows.first(where: { $0.id == r.showID }) else { continue }
            if let eid = r.episodeID {
                guard let ep = episodes[show.id]?.first(where: { $0.id == eid }) else { continue }
                reservations[r.night] = TonightEngine.candidate(show: show, episode: ep, ctx: context)
            } else {
                reservations[r.night] = Candidate(show: show, episode: nil, playCount: 1, reason: .continuation)
            }
        }
        savedReservations = []
    }

    func persistSession() {
        guard persistsSession else { return }
        SessionStore.save(SessionState(history: history, favorites: favorites, queue: queue, currentShowID: currentShowID,
                                       lastNight: lastNight, genreStreakNights: genreStreakNights, pendingMorning: pendingMorning,
                                       reservations: reservations.filter { $0.key >= nightDay(0) }.map {
                                           SavedReservation(night: $0.key, showID: $0.value.show.id, episodeID: $0.value.episode?.id) }))
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
        persistSession()
    }

    func toggleQueue(_ show: Show) {
        if let i = queue.firstIndex(of: show.id) {
            queue.remove(at: i)
        } else {
            queue.append(show.id); showToast("「次に聴く」に入れました")
        }
        persistSession()
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
        let replaced = reservations[nightDay(night)].map { $0 != candidate } ?? false
        reservations[nightDay(night)] = candidate
        // 前の予約があったときは、置き換わったことを伝える(予約は、その晩に1本だけ)。
        showToast(night == 0 ? (replaced ? "今夜聴く話を変えました" : "今夜聴くに決めました")
                             : (replaced ? "明日聴く話を変えました" : "明日聴くに決めました"))
        persistSession()
    }
    /// 今夜の予約が、この番組か。
    func isReservedTonight(_ show: Show) -> Bool { reservation(night: 0)?.show.id == show.id }
    /// 今夜の予約が、この話か。
    func isReservedTonight(episode: Episode) -> Bool { reservation(night: 0)?.episode?.id == episode.id }

    /// 番組の「次に聴く話」。今夜の候補にあればそれ、なければ、番組の中で次に聴く話。
    func nextCandidate(for show: Show) -> Candidate? {
        slate(night: 0).first(where: { $0.show.id == show.id && $0.episode != nil })
            ?? TonightEngine.listenNow(show: show, ctx: context)
    }

    /// その晩(0 = 今夜、1 = 明日)の予約が、この番組 / この話か。
    func isReserved(_ show: Show, night: Int) -> Bool { reservation(night: night)?.show.id == show.id }
    func isReserved(episode: Episode, night: Int) -> Bool { reservation(night: night)?.episode?.id == episode.id }

    /// 番組を指定して、その晩に聴くを予約する。予約済みなら取り消す。
    func toggleReserve(_ show: Show, night: Int) {
        if isReserved(show, night: night) { cancelReservation(night: night); return }
        let c = night == 0 ? nextCandidate(for: show)
            : (slate(night: night).first(where: { $0.show.id == show.id }) ?? nextCandidate(for: show))
        if let c { reserve(night: night, c) }
    }

    /// 話を指定して、その晩に聴くを予約する。この話が予約済みなら取り消す。
    func toggleReserve(episode: Episode, of show: Show, night: Int) {
        if isReserved(episode: episode, night: night) { cancelReservation(night: night); return }
        reserve(night: night, TonightEngine.candidate(show: show, episode: episode, ctx: context))
    }

    /// 予約したあと、次に何が起きるか(今夜タブと詳細で同じ言葉)。
    func reservationNote(night: Int) -> String {
        night == 0 ? "\(bedtimeText ?? "寝る前に")アプリを開くと、この話をすぐ再生できます"
                   : "明日の夜、今夜タブにこの話が出ます"
    }

    /// 番組を指定して、今夜聴くを予約する。予約済みなら取り消す。候補にない番組でも、その番組自体を予約する。
    func toggleTonight(_ show: Show) {
        if isReservedTonight(show) { cancelReservation(night: 0); return }
        if let c = nextCandidate(for: show) { reserve(night: 0, c) }
    }

    /// 話を指定して、今夜聴くを予約する。この話が予約済みなら取り消す(ほかの話が予約済みなら、この話に変える)。
    func toggleTonight(episode: Episode, of show: Show) {
        if isReservedTonight(episode: episode) { cancelReservation(night: 0); return }
        reserve(night: 0, TonightEngine.candidate(show: show, episode: episode, ctx: context))
    }

    /// 話を指定して、いま聴く。
    func playNow(episode: Episode, of show: Show) {
        play(TonightEngine.candidate(show: show, episode: episode, ctx: context))
    }

    /// その話を聴いた回数(再生した履歴から)。
    func listenCount(_ episode: Episode) -> Int { history.filter { $0.episodeID == episode.id }.count }

    func episode(id: String) -> (show: Show, episode: Episode)? {
        for (showID, list) in episodes {
            if let e = list.first(where: { $0.id == id }), let s = shows.first(where: { $0.id == showID }) { return (s, e) }
        }
        return nil
    }

    func cancelReservation(night: Int) {
        reservations[nightDay(night)] = nil
        showToast("予約を取り消しました")
        persistSession()
    }

    /// 夜の画面を閉じて、再生を止める。朝の振り返りは、そのまま残る。
    func endPlayback() {
        player.stop()
        playing = nil
        nightScreen = nil
        nightScreenAuto = false
    }

    /// 再生を始める。再生した番組が、次の「いまの番組」になる。
    func play(_ candidate: Candidate) {
        if let ep = candidate.episode {
            history.append(PlayRecord(episodeID: ep.id, showID: candidate.show.id, playedAt: Date()))
        }
        currentShowID = candidate.show.id
        playStartedAt = Date(); onsetAt = nil; onsetAfterPlayback = false
        playLastAudibleAt = playStartedAt; lastAudibleSavedAt = nil
        playEpisodeID = candidate.episode?.id; playShowID = candidate.show.id
        pendingMorning = true
        savePendingNight()
        persistSession()
        playing = candidate
        if let ep = candidate.episode {
            player.start(url: ep.audioURL, title: ep.title, subtitle: candidate.show.title)
        } else {
            player.start(url: nil, title: candidate.show.title)
        }
        if nightScreen == nil { nightScreenNight = nightDay(0); nightScreen = .playing }
    }
}
