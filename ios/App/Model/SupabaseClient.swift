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

    // MARK: REST

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let base else { throw ClientError.notConfigured }
        let s = try await validSession()
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!); req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
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

    /// 掲載中(listed)の番組。ランクは掲載中だけ付く。
    func fetchShows() async throws -> [Show] {
        let data = try await request("show", query: [URLQueryItem(name: "select", value: "id,title,genre,show_star,z_rank,listing_status,artwork_url,link_url,apple_url")])
        return try Self.decoder.decode([ShowRow].self, from: data).map {
            Show(id: $0.id, title: $0.title, genre: $0.genre ?? "",
                 artworkURL: $0.artwork_url.flatMap(URL.init(string:)), linkURL: $0.link_url.flatMap(URL.init(string:)),
                 appleURL: $0.apple_url.flatMap(URL.init(string:)), star: $0.show_star,
                 rank: $0.listing_status == "listed" ? $0.z_rank.flatMap(ZRank.init(rawValue:)) : nil)
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
        let episode_id: String; let calm_star: Double?; let ear_star: Double?
        let interest_level: String?; let final_reason: String?
    }

    /// 解析結果を番組ごとにまとめる(★は各回の平均、一行は最新の回の理由)。
    func fetchAspects(episodes: [String: [Episode]]) async throws -> [String: (ShowAspects, String?)] {
        let data = try await request("analysis", query: [
            URLQueryItem(name: "select", value: "episode_id,calm_star,ear_star,interest_level,final_reason"),
            URLQueryItem(name: "order", value: "analyzed_at.desc")])
        let rows = try Self.decoder.decode([AnalysisRow].self, from: data)
        var showOf: [String: String] = [:]
        for (sid, eps) in episodes { for e in eps { showOf[e.id] = sid } }
        var out: [String: (ShowAspects, String?)] = [:]
        for (sid, group) in Dictionary(grouping: rows.filter { showOf[$0.episode_id] != nil }, by: { showOf[$0.episode_id]! }) {
            func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
            let levels = group.compactMap { $0.interest_level.flatMap(InterestLevel.init(rawValue:)) }
            out[sid] = (ShowAspects(calmStar: avg(group.compactMap(\.calm_star)), earStar: avg(group.compactMap(\.ear_star)),
                                    interest: levels.first), group.first?.final_reason)
        }
        return out
    }

    private struct LogUpload: Encodable {
        let id: String; let episode_id: String; let started_at: Date; let sleep_onset_at: Date?
        let latency_min: Int?; let source: String; let interest_vote: Int?; let calm_vote: Int?
        let note: String?; let listen_no: Int
    }

    /// 記録の送信。同じ id は上書き(再送しても重ならない)。
    func upload(_ log: SleepLog) async throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let row = LogUpload(id: log.id, episode_id: log.episodeID, started_at: log.startedAt, sleep_onset_at: log.sleepOnsetAt,
                            latency_min: log.latencyMinutes, source: log.source.rawValue, interest_vote: log.interestVote,
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
    static func save(_ s: SupabaseClient.Session) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query; q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
