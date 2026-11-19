import SwiftUI
import StoreKit
import NeochiCore

/// プレミアムの案内と購入。無料の機能は減らさず、「再生が便利になる」ことを伝える(docs/PREMIUM.md §3)。
/// 効能の言葉は使わない(「眠れる」「改善」など。docs/VOICE.md)。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = PremiumStore.shared
    @State private var selected: PremiumPlan = .yearly

    private static let termsURL = URL(string: "https://neochipickzz.vercel.app/terms.html")!
    private static let privacyURL = URL(string: "https://neochipickzz.vercel.app/privacy.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NCSpace.s5) {
                Text("プレミアム").ncText(NCText.title)
                Text("聴き始めのストレスを減らし、自分の眠りに合わせます。").ncText(NCText.body, .textSub)
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    feature("本編から始める", "広告やオープニングを飛ばして、話の本編から再生します。")
                    feature("寝落ちグラフ", "再生中に、話の起伏と、眠りやすい区間を見られます。")
                    feature("あなた向けの並び", "自分の記録から、今夜の1本を並べ直します。")
                }
                if store.isPremium { active } else { purchase }
                if let m = store.message { Text(m).ncText(NCText.footnote, .textSub) }
                legal
            }
            .padding(.horizontal, NCSpace.s5)
            .padding(.bottom, NCSpace.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.nc(.bgBase))
        .navigationTitle("プレミアム")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts(); await store.refresh() }
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            Text(title).ncText(NCText.headline)
            Text(detail).ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NCSpace.s4)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }

    @ViewBuilder private var active: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text(statusText).ncText(NCText.headline)
            Text("解約や変更は、iPhone の設定の「サブスクリプション」から。").ncText(NCText.footnote, .textSub)
        }
    }

    private var statusText: String {
        switch store.entitlement {
        case .trial(_, let until): "無料トライアル中(\(until.formatted(.dateTime.month().day()))まで)"
        case .subscribed(let plan, _): "契約中(\(plan.label))"
        default: ""
        }
    }

    @ViewBuilder private var purchase: some View {
        VStack(spacing: NCSpace.s3) {
            ForEach(PremiumPlan.allCases, id: \.self) { plan in planRow(plan) }
            NCButton(title: store.trialEligible && selected == .yearly ? "14日間、無料で試す" : "購入する", kind: .primary, size: .large) {
                Task { await store.purchase(selected) }
            }
            .disabled(store.busy || store.products[selected] == nil)
            NCButton(title: "購入を復元", kind: .text, size: .medium) { Task { await store.restore() } }
                .disabled(store.busy)
        }
    }

    private func planRow(_ plan: PremiumPlan) -> some View {
        let price = store.products[plan]?.displayPrice ?? "-"
        let on = selected == plan
        return Button { selected = plan } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(plan.label).ncText(NCText.headline)
                    Text(plan == .yearly ? "月あたり約125円" : "いつでも解約できます").ncText(NCText.footnote, .textSub)
                }
                Spacer()
                Text(price + (plan == .yearly ? " / 年" : " / 月")).ncText(NCText.body)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            .overlay(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).stroke(Color.nc(on ? .textMain : .surface), lineWidth: 1.5))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 自動更新の説明(App Store の審査で必要)。
    private var legal: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text("年額は、14日間の無料トライアルのあと、自動で更新されます。期間の終了の24時間前までに解約しないかぎり、更新されます。支払いは、購入の確定時に Apple ID に請求されます。更新の停止は、iPhone の設定の「サブスクリプション」から行えます。")
                .ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NCSpace.s4) {
                Link("利用規約", destination: Self.termsURL)
                Link("プライバシーポリシー", destination: Self.privacyURL)
            }
            .ncText(NCText.footnote, .textSub)
        }
    }
}

/// 設定の「プレミアム」の行。契約の状態を出し、押すと購入の画面へ進む。
struct PremiumRow: View {
    @State private var store = PremiumStore.shared

    private var status: String {
        switch store.entitlement {
        case .trial(_, let until): "無料トライアル中(\(until.formatted(.dateTime.month().day()))まで)"
        case .subscribed(let plan, _): "契約中(\(plan.label))"
        case .expired: "期限が切れています"
        case .free: "本編から始める・寝落ちグラフ・あなた向けの並び"
        }
    }

    var body: some View {
        NavigationLink { PaywallView() } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("プレミアム").ncText(NCText.body)
                    Text(status).ncText(NCText.footnote, .textSub).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").ncText(NCText.footnote, .textSub)
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable)
        .task { await store.refresh() }
    }
}
