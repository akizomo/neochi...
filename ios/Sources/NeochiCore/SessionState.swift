import Foundation

/// お気に入り・次に聴く・再生の記録など、アプリを閉じても残す状態(端末に保存する)。
/// 番組の一覧が差し替わったとき(見本 → 実データ)に、存在しない番組を指す状態を外すためにも使う。
public struct SessionState: Equatable, Sendable, Codable {
    public var history: [PlayRecord]
    public var favorites: Set<String>
    public var queue: [String]
    public var currentShowID: String?
    public var lastNight: LastNight?
    public var genreStreakNights: Int
    public var pendingMorning: Bool
    /// 晩ごとの予約(番組ID)。
    public var reservedShowIDs: [Int: String]

    public init(history: [PlayRecord] = [], favorites: Set<String> = [], queue: [String] = [],
                currentShowID: String? = nil, lastNight: LastNight? = nil, genreStreakNights: Int = 0,
                pendingMorning: Bool = false, reservedShowIDs: [Int: String] = [:]) {
        self.history = history; self.favorites = favorites; self.queue = queue
        self.currentShowID = currentShowID; self.lastNight = lastNight
        self.genreStreakNights = genreStreakNights; self.pendingMorning = pendingMorning
        self.reservedShowIDs = reservedShowIDs
    }

    /// `showIDs` に無い番組を指すものを外す。いまの番組が消えたら、連続の晩数も 0 に戻す。
    public func reconciled(toShowIDs showIDs: Set<String>) -> SessionState {
        var s = self
        s.history = history.filter { showIDs.contains($0.showID) }
        s.favorites = favorites.intersection(showIDs)
        s.queue = queue.filter(showIDs.contains)
        s.reservedShowIDs = reservedShowIDs.filter { showIDs.contains($0.value) }
        if let c = currentShowID, !showIDs.contains(c) { s.currentShowID = nil; s.genreStreakNights = 0 }
        if let l = lastNight, !showIDs.contains(l.showID) { s.lastNight = nil; s.pendingMorning = false }
        return s
    }
}
