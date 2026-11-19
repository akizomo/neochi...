import Foundation

/// プレミアムの契約(docs/PREMIUM.md)。商品の名前と、「いま何が使えるか」の判断だけを持つ。
/// StoreKit には依存しない。アプリ側が購入の事実(`PurchaseFact`)を渡し、ここで状態に直す。
public enum PremiumPlan: String, Codable, CaseIterable, Sendable {
    case yearly, monthly

    /// App Store Connect に作る商品の ID。同じグループ(プレミアム)に2つ置く。
    public var productID: String {
        switch self { case .yearly: "com.example.neochi.premium.yearly"; case .monthly: "com.example.neochi.premium.monthly" }
    }
    public init?(productID: String) {
        guard let p = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = p
    }
    /// 表示用の名前。
    public var label: String { self == .yearly ? "年額" : "月額" }
}

/// プレミアムで使える機能。無料で使えるものはここに入れない(記録・再生・評点は無料)。
public enum PremiumFeature: String, CaseIterable, Sendable {
    /// 本編から始める(広告やオープニングを飛ばして再生を始める)。
    case startAtContent
    /// Player の寝落ちグラフ。
    case sleepGraph
    /// あなた向けの並び。
    case personalOrder
    /// 全期間の傾向と書き出し。
    case fullHistory
}

/// 購入の事実。StoreKit の取引から、アプリが作る。
public struct PurchaseFact: Equatable, Sendable {
    public var plan: PremiumPlan
    /// 期限。nil は期限なし(買い切りの扱い)。
    public var expiresAt: Date?
    /// 無料トライアルの期間か。
    public var isTrial: Bool
    /// 返金などで取り消されたか。
    public var isRevoked: Bool

    public init(plan: PremiumPlan, expiresAt: Date?, isTrial: Bool = false, isRevoked: Bool = false) {
        self.plan = plan; self.expiresAt = expiresAt; self.isTrial = isTrial; self.isRevoked = isRevoked
    }
}

/// いまの契約の状態。
public enum Entitlement: Equatable, Sendable {
    /// 一度も契約していない。
    case free
    /// 無料トライアル中。`until` まで。
    case trial(PremiumPlan, until: Date)
    /// 契約中。`until` は次の更新(または期限)の時刻。nil は期限なし。
    case subscribed(PremiumPlan, until: Date?)
    /// 契約が切れた(解約・期限切れ・取り消し)。`since` は切れた時刻。
    case expired(since: Date?)

    /// 有料の機能を使えるか。
    public var isActive: Bool {
        switch self { case .trial, .subscribed: true; case .free, .expired: false }
    }

    public func allows(_ feature: PremiumFeature) -> Bool { isActive }

    /// 購入の事実の一覧と、いまの時刻から、状態を決める。
    /// 取り消されたものは無視し、期限が先にあるものを優先する。複数あれば、期限がいちばん遠いものを採る。
    public static func resolve(_ facts: [PurchaseFact], now: Date) -> Entitlement {
        let valid = facts.filter { !$0.isRevoked }
        let live = valid.filter { ($0.expiresAt ?? .distantFuture) > now }
        if let best = live.max(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            if best.isTrial, let until = best.expiresAt { return .trial(best.plan, until: until) }
            return .subscribed(best.plan, until: best.expiresAt)
        }
        if facts.isEmpty { return .free }
        return .expired(since: valid.compactMap(\.expiresAt).max())
    }
}
