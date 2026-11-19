import Foundation
import Observation
import StoreKit
import NeochiCore

/// プレミアムを出すか。1.0 は出さない(無料で、課金なし)。課金を出す版(1.1 以降)で true にする。
/// App Store Connect の契約・商品の用意(docs/PREMIUM.md §7 の段階1)が済んでから。
enum PremiumFeatureFlag { static let enabled = false }

/// 契約の状態と購入(StoreKit 2)。権利は端末内で、StoreKit の購入情報から決める(サーバーでは確かめない)。
/// 状態の判断は NeochiCore の `Entitlement.resolve`(テストあり)。ここは StoreKit とのやり取りだけ。
@MainActor
@Observable
final class PremiumStore {
    static let shared = PremiumStore()

    private(set) var entitlement: Entitlement = .free
    private(set) var products: [PremiumPlan: Product] = [:]
    /// 無料トライアルを使えるか(まだ使っていない)。
    private(set) var trialEligible = false
    private(set) var busy = false
    var message: String?

    private var updates: Task<Void, Never>?

    var isPremium: Bool { debugForced || entitlement.isActive }
    func allows(_ f: PremiumFeature) -> Bool { debugForced || entitlement.allows(f) }

    /// デバッグ時だけ、環境変数 NEOCHI_PREMIUM=1 でプレミアムの機能を出して、画面を確かめられる(購入なし)。
    private var debugForced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NEOCHI_PREMIUM"] == "1"
        #else
        return false
        #endif
    }

    /// 起動時に1回。購入情報の変化(別の端末での購入、更新、返金)を受け取り続ける。
    func start() {
        guard PremiumFeatureFlag.enabled, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh(); await loadProducts() }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: PremiumPlan.allCases.map(\.productID))
            var map: [PremiumPlan: Product] = [:]
            for p in list { if let plan = PremiumPlan(productID: p.id) { map[plan] = p } }
            products = map
            if let y = map[.yearly]?.subscription { trialEligible = await y.isEligibleForIntroOffer }
        } catch {
            message = "価格を読み込めませんでした。通信を確かめて、もう一度お試しください。"
        }
    }

    /// 購入の情報から、いまの状態を決め直す。
    func refresh() async {
        var facts: [PurchaseFact] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, let plan = PremiumPlan(productID: t.productID) else { continue }
            facts.append(PurchaseFact(plan: plan, expiresAt: t.expirationDate, isTrial: Self.isTrial(t), isRevoked: t.revocationDate != nil))
        }
        entitlement = Entitlement.resolve(facts, now: Date())
    }

    private static func isTrial(_ t: Transaction) -> Bool {
        if #available(iOS 17.2, *) { return t.offer?.type == .introductory && t.offer?.paymentMode == .freeTrial }
        return t.offerType == .introductory
    }

    func purchase(_ plan: PremiumPlan) async {
        guard let product = products[plan] else { await loadProducts(); return }
        busy = true; message = nil
        defer { busy = false }
        // 購入に、ユーザー ID を付ける(あとで、サーバーで契約と結びつけるため)。
        var options: Set<Product.PurchaseOption> = []
        if let id = await SupabaseClient.shared.currentUserUUID() { options.insert(.appAccountToken(id)) }
        do {
            switch try await product.purchase(options: options) {
            case .success(let result):
                if case .verified(let t) = result { await t.finish(); await refresh() }
                else { message = "購入を確認できませんでした。" }
            case .pending: message = "購入の承認を待っています。承認されると、自動で使えるようになります。"
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = "購入できませんでした。もう一度お試しください。"
        }
    }

    /// 購入の復元(機種変更のあとなど)。
    func restore() async {
        busy = true; message = nil
        defer { busy = false }
        do { try await AppStore.sync() } catch { message = "復元できませんでした。通信を確かめて、もう一度お試しください。" }
        await refresh()
        if !entitlement.isActive, message == nil { message = "復元できる購入が見つかりませんでした。" }
    }
}
