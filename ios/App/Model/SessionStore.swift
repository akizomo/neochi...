import Foundation
import NeochiCore

/// お気に入り・次に聴く・再生の記録などの端末内保存(JSON)。記録(LogStore)とは別のファイル。
enum SessionStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func load() -> SessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(SessionState.self, from: data)
    }

    static func save(_ state: SessionState) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(state) { try? data.write(to: url, options: .atomic) }
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
