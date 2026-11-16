import Foundation
import Security
import NeochiCore

/// Supabase の最小クライアント(匿名ログイン + REST)。依存パッケージは足さない。
/// 接続先は Info.plist の SupabaseHost(例: abcd.supabase.co)と SupabaseAnonKey。空なら未設定で、端末内だけで動く。
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let base: URL?
    private let anonKey: String
    private var session: Session?

    struct Session: Codable { var accessToken: String; var refreshToken: String; var expiresAt: Date }

    init() {
        let host = (Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String) ?? ""
        anonKey = (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String) ?? ""
        base = host.isEmpty || anonKey.isEmpty ? nil : URL(string: "https://\(host)")
        session = Keychain.load()
    }

    nonisolated var isConfigured: Bool {
        let host = (Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String) ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String) ?? ""
        return !host.isEmpty && !key.isEmpty
    }

    enum ClientError: Error { case notConfigured, http(Int) }

    // MARK: 認証

    private struct TokenResponse: Decodable {
        let access_token: String; let refresh_token: String; let expires_in: Double
    }

    private func accept(_ data: Data) throws -> Session {
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        let s = Session(accessToken: r.access_token, refreshToken: r.refresh_token,
                        expiresAt: Date().addingTimeInterval(r.expires_in - 60))
        session = s; Keychain.save(s)
        return s
    }

    private func validSession() async throws -> Session {
        guard let base else { throw ClientError.notConfigured }
        if let s = session, s.expiresAt > Date() { return s }
        if let s = session {
            var comps = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            var req = URLRequest(url: comps.url!); req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["refresh_token": s.refreshToken])
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200, let ns = try? accept(data) { return ns }
        }
        // 匿名ログイン(端末ごとの ID)。
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/signup")); req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.http(code) }
        return try accept(data)
    }

    // MARK: アカウント(Sign in with Apple)

    struct AccountInfo: Equatable {
        var isAnonymous: Bool
        var email: String?
        var providers: [String]
    }

    enum LinkResult { case linked, restored }

    private struct UserResponse: Decodable {
        let is_anonymous: Bool?; let email: String?
        let identities: [Identity]?
        struct Identity: Decodable { let provider: String }
    }

    /// いまのログインの状態。匿名なら isAnonymous、Apple に連携済みなら providers に "apple" が入る。
    func account() async throws -> AccountInfo {
        guard let base else { throw ClientError.notConfigured }
        let s = try await validSession()
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/user"))
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.http(code) }
        let u = try JSONDecoder().decode(UserResponse.self, from: data)
        let providers = (u.identities ?? []).map(\.provider).filter { $0 != "anonymous" }
        return AccountInfo(isAnonymous: u.is_anonymous ?? providers.isEmpty, email: u.email, providers: providers)
    }

    private func idTokenRequest(idToken: String, nonce: String, link: Bool, bearer: String?) async throws -> (Data, Int) {
        guard let base else { throw ClientError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        var req = URLRequest(url: comps.url!); req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["provider": "apple", "id_token": idToken, "nonce": nonce]
        if link { body["link_identity"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Apple の ID トークンで、いまの匿名ユーザーに Apple を連携する(user_id は変わらず、これまでの記録が残る)。
    /// その Apple ID がすでに別のユーザーに連携済み(機種変更・入れ直し)なら、そのユーザーとしてログインし直す(.restored)。
    /// このとき、この端末の匿名のあいだの記録は、新しいユーザーには移らない。
    func linkApple(idToken: String, nonce: String) async throws -> LinkResult {
        let current = try await validSession()
        let (data, code) = try await idTokenRequest(idToken: idToken, nonce: nonce, link: true, bearer: current.accessToken)
        if code == 200 { _ = try accept(data); return .linked }
        guard (400..<500).contains(code), code != 401, code != 429 else { throw ClientError.http(code) }
        let (data2, code2) = try await idTokenRequest(idToken: idToken, nonce: nonce, link: false, bearer: nil)
        guard code2 == 200 else { throw ClientError.http(code2) }
        _ = try accept(data2)
        return .restored
    }

    /// ログアウト。端末のログインを消す。次に使うときは、新しい匿名ユーザーになる
    /// (連携していない匿名のままログアウトすると、そのあいだの記録には戻れない。画面で止める)。
    func signOut() async {
        if let base, let s = session {
            var req = URLRequest(url: base.appendingPathComponent("auth/v1/logout")); req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
        session = nil; Keychain.clear()
    }

    /// アカウントの削除。Edge Function(supabase/functions/delete-account)が、本人の記録と auth のユーザーを消す。
    func deleteAccount() async throws {
        guard let base else { throw ClientError.notConfigured }
        let s = try await validSession()
        var req = URLRequest(url: base.appendingPathComponent("functions/v1/delete-account")); req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        session = nil; Keychain.clear()
    }

    // MARK: REST

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let base else { throw ClientError.notConfigured }
        // 読み出し(GET)は、ログインできなくても公開キーだけで読める。匿名ログインが無効な環境でも、番組が見られるように。
        // 書き込みは、端末ごとの ID が要るので、ログインできなければ失敗させる。
        let session: Session? = method == "GET" ? try? await validSession() : try await validSession()
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!); req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let session { req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return data
    }

    private struct ShowRow: Decodable {
        let id: String; let title: String; let genre: String?; let show_star: Double?; let z_rank: String?
        let listing_status: String
        let artwork_url: String?; let link_url: String?; let apple_url: String?
    }
    private struct EpisodeRow: Decodable {
        let id: String; let show_id: String; let title: String?; let audio_url: String?
        let duration_sec: Int?; let published_at: Date?
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let v = f.date(from: s) ?? g.date(from: s) { return v }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s))
        }
        return d
    }

    /// 掲載中(listed)の番組だけ。基準未満の番組は返さない。
    func fetchShows() async throws -> [Show] {
        let data = try await request("show", query: [URLQueryItem(name: "select", value: "id,title,genre,show_star,z_rank,listing_status,artwork_url,link_url,apple_url")])
        return try Self.decoder.decode([ShowRow].self, from: data).filter { $0.listing_status == "listed" && $0.z_rank != nil }.map {
            Show(id: $0.id, title: $0.title, genre: GenreLabel.display($0.genre ?? "") ?? "",  // 古い分類名は、いまの系統に読み替える
                 artworkURL: $0.artwork_url.flatMap(URL.init(string:)), linkURL: $0.link_url.flatMap(URL.init(string:)),
                 appleURL: $0.apple_url.flatMap(URL.init(string:)), star: $0.show_star,
                 rank: $0.z_rank.flatMap(ZRank.init(rawValue:)))
        }
    }

    func fetchEpisodes() async throws -> [String: [Episode]] {
        let data = try await request("episode", query: [
            URLQueryItem(name: "select", value: "id,show_id,title,audio_url,duration_sec,published_at"),
            URLQueryItem(name: "order", value: "published_at.desc")])
        let rows = try Self.decoder.decode([EpisodeRow].self, from: data)
        return Dictionary(grouping: rows.map {
            Episode(id: $0.id, showID: $0.show_id, title: $0.title ?? "", publishedAt: $0.published_at,
                    durationSec: $0.duration_sec, audioURL: $0.audio_url.flatMap(URL.init(string:)))
        }, by: \.showID)
    }

    private struct AnalysisRow: Decodable {
        let episode_id: String; let calm_star: Double?; let ear_star: Double?; let final_star: Double?
        let interest_level: String?; let interest_score: Int?; let input_depth: String?
        let reasons: Reasons?; let features: Features?
        let calm_per_min: [Double]?; let content_summary: String?
        struct Reasons: Decodable {
            let llm: String?; let moments: [M]?; let items: Items?
            struct M: Decodable { let min: Int; let note: String; let level: Int? }
            struct Item: Decodable { let score: Int; let min: Int? }
            struct Items: Decodable { let interest: [String: Item]?; let calm: [String: Item]? }
        }
        struct Features: Decodable {
            let duration_sec: Double?; let speech_rate: Double?; let speech_rate_cv: Double?; let volume_std_db: Double?; let sudden_per_10min: Double?
            let ear_parts: Parts?; let timeline: Timeline?
            struct Parts: Decodable { let rate: Double?; let rate_cv: Double?; let volume: Double?; let sudden: Double? }
            struct Timeline: Decodable { let rate_per_min: [Double?]?; let volume_db: [Double?]?; let sudden_at_sec: [Int]? }
        }
    }

    private static func items(_ d: [String: AnalysisRow.Reasons.Item]?) -> [ScoredItem] {
        (d ?? [:]).map { ScoredItem(key: $0.key, score: $0.value.score, minute: $0.value.min) }.sorted { $0.key < $1.key }
    }

    private static let analysisColumns = "episode_id,calm_star,ear_star,final_star,interest_level,interest_score,input_depth,reasons,features"

    /// 各回の解析。★と、根拠のデータ(古い解析にない項目は nil)。
    /// 1分ごとの起伏と要約の列(migration 0007)がまだ無い環境では、その列を除いて読み直す。
    func fetchAnalyses() async throws -> [EpisodeAnalysis] {
        func fetch(_ select: String) async throws -> Data {
            try await request("analysis", query: [URLQueryItem(name: "select", value: select),
                                                  URLQueryItem(name: "order", value: "analyzed_at.desc")])
        }
        let data: Data
        do { data = try await fetch(Self.analysisColumns + ",calm_per_min,content_summary") }
        catch ClientError.http(400) { data = try await fetch(Self.analysisColumns) }
        return try Self.decoder.decode([AnalysisRow].self, from: data).map { r in
            let f = r.features
            var a = EpisodeAnalysis(
                episodeID: r.episode_id, finalStar: r.final_star, calmStar: r.calm_star, earStar: r.ear_star,
                interest: r.interest_level.flatMap(InterestLevel.init(rawValue:)), interestScore: r.interest_score,
                reason: r.reasons?.llm, inputDepth: r.input_depth, durationSec: f?.duration_sec,
                earParts: f?.ear_parts.map { EarParts(rate: $0.rate, rateCV: $0.rate_cv, volume: $0.volume, sudden: $0.sudden) },
                speechRate: f?.speech_rate, volumeStdDB: f?.volume_std_db, suddenPer10Min: f?.sudden_per_10min)
            a.speechRateCV = f?.speech_rate_cv
            a.interestItems = Self.items(r.reasons?.items?.interest)
            a.calmItems = Self.items(r.reasons?.items?.calm)
            a.ratePerMin = f?.timeline?.rate_per_min ?? []
            a.volumePerMin = f?.timeline?.volume_db ?? []
            a.suddenAtSec = f?.timeline?.sudden_at_sec ?? []
            a.moments = (r.reasons?.moments ?? []).map { Moment(minute: $0.min, note: $0.note, level: $0.level) }
            a.calmPerMin = r.calm_per_min ?? []
            a.contentSummary = r.content_summary
            return a
        }
    }

    private struct StatsRow: Decodable { let show_id: String; let n: Int; let avg_min: Int; let min_min: Int; let max_min: Int; let under30: Int }

    /// 番組ごとの実績(view `show_stats`。未作成・失敗のときは呼び出し側で無視する)。
    func fetchStats() async throws -> [String: ShowStats] {
        let data = try await request("show_stats", query: [URLQueryItem(name: "select", value: "*")])
        let rows = try Self.decoder.decode([StatsRow].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.show_id, ShowStats(count: $0.n, avgMinutes: $0.avg_min, minMinutes: $0.min_min, maxMinutes: $0.max_min, under30: $0.under30))
        })
    }

    private struct PointRow: Decodable { let show_id: String; let night: String; let latency_min: Int }

    /// 番組ごとの実績の点(view `show_sleep_points`。古い順)。未作成・失敗のときは呼び出し側で無視する。
    func fetchSleepPoints() async throws -> [String: [SleepPoint]] {
        let data = try await request("show_sleep_points", query: [URLQueryItem(name: "select", value: "show_id,night,latency_min"),
                                                                  URLQueryItem(name: "order", value: "night.asc")])
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "yyyy-MM-dd"
        let rows = try Self.decoder.decode([PointRow].self, from: data)
        return Dictionary(grouping: rows.compactMap { r in
            f.date(from: r.night).map { (r.show_id, SleepPoint(night: $0, minutes: r.latency_min)) }
        }, by: \.0).mapValues { $0.map(\.1) }
    }

    private struct LogUpload: Encodable {
        let id: String; let episode_id: String; let started_at: Date; let sleep_onset_at: Date?
        let latency_min: Int?; let source: String; let interest_rating: Int?; let calm_vote: Int?
        let note: String?; let listen_no: Int
    }

    /// 自分の記録をすべて削除する(RLS により、本人の行だけが消える。migration 0010)。
    func deleteMyRecords() async throws {
        _ = try await request("sleep_log", query: [URLQueryItem(name: "id", value: "not.is.null")], method: "DELETE")
    }

    /// 記録の送信。同じ id は上書き(再送しても重ならない)。
    func upload(_ log: SleepLog) async throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let row = LogUpload(id: log.id, episode_id: log.episodeID, started_at: log.startedAt, sleep_onset_at: log.sleepOnsetAt,
                            latency_min: log.latencyMinutes, source: log.source.rawValue, interest_rating: log.interestRating,
                            calm_vote: log.calmVote, note: log.note, listen_no: log.listenNo)
        _ = try await request("sleep_log", query: [URLQueryItem(name: "on_conflict", value: "id")], method: "POST",
                              body: try e.encode(row))
    }
}

private enum Keychain {
    private static let account = "supabase.session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "neochi", kSecAttrAccount as String: account]
    }
    static func load() -> SupabaseClient.Session? {
        var q = query; q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseClient.Session.self, from: data)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
    static func save(_ s: SupabaseClient.Session) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query; q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
