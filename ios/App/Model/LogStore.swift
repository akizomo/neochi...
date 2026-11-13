import Foundation
import NeochiCore

/// 記録の端末内保存(JSON)。
enum LogStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sleep_logs.json")
    }

    static func load() -> [SleepLog] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([SleepLog].self, from: data)) ?? []
    }

    static func save(_ logs: [SleepLog]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(logs) { try? data.write(to: url, options: .atomic) }
    }
}
