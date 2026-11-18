import SwiftUI
import NeochiCore

/// 初回に一度だけ聞く、ふだんの就寝時刻。記録が貯まるまでの、夜の画面を出す時間帯に使う。
struct BedtimeSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 設定から開いた変更のとき。初回の質問と違い、夜の画面は開かず、「あとで」は「閉じる」。
    var editing = false
    @State private var time: Date

    init(editing: Bool = false, initial: Int? = nil) {
        self.editing = editing
        let m = initial ?? 23 * 60
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? Date())
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
            Text(editing ? "ふだんの就寝時刻" : "ふだん、何時ごろ寝ますか?").ncText(NCText.title)
            Text("この時刻の前後にアプリを開くと、夜の画面を出します。聴いた記録が貯まると、自動で合わせます。")
                .ncText(NCText.body, .textSub)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("就寝時刻", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top) }
        .frame(maxHeight: .infinity)
        // ボタンは下に固定。スクロールするのは、上の内容だけ。
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: NCSpace.s1) {
                NCButton(title: "決める") { model.saveBedtime(time, openNight: !editing); if editing { dismiss() } }
                NCButton(title: editing ? "閉じる" : "あとで", kind: .text, size: .medium) {
                    if editing { dismiss() } else { model.saveBedtime(nil) }
                }
            }
            .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s2)
            .background(Color.nc(.bgBase))
        }
        .background(Color.nc(.bgBase).ignoresSafeArea())
        // 親指が届くよう、ふつうは下半分。小さい画面(SE など)では、スクロールなしで全部見えるよう全面にする。
        .presentationDetents(UIScreen.main.bounds.height < 700 ? [.large] : [.medium, .large])
        .presentationDragIndicator(editing ? .visible : .hidden)
    }
}
