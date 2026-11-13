import SwiftUI
import NeochiCore

/// 初回に一度だけ聞く、ふだんの就寝時刻。記録が貯まるまでの、夜の画面を出す時間帯に使う。
struct BedtimeSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 記録タブから開いた変更のとき。初回の質問と違い、夜の画面は開かず、「あとで」は「閉じる」。
    var editing = false
    @State private var minute: Int

    init(editing: Bool = false, initial: Int? = nil) {
        self.editing = editing
        _minute = State(initialValue: BedtimeWindow.snapped(initial ?? 23 * 60))
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
            Text(editing ? "ふだんの就寝時刻" : "ふだん、何時ごろ寝ますか?").ncText(NCText.title)
            Text("この時刻の前後にアプリを開くと、夜の画面を出します。聴いた記録が貯まると、自動で合わせます。")
                .ncText(NCText.body, .textSub)
                .fixedSize(horizontal: false, vertical: true)
            Picker("就寝時刻", selection: $minute) {
                ForEach(BedtimeWindow.pickerMinutes, id: \.self) { Text(BedtimeWindow.label(minute: $0)).tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
            Button { model.saveBedtime(Calendar.current.date(from: DateComponents(hour: minute / 60, minute: minute % 60)), openNight: !editing); if editing { dismiss() } } label: {
                Text("決める").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            Button { if editing { dismiss() } else { model.saveBedtime(nil) } } label: {
                Text(editing ? "閉じる" : "あとで").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
            }
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top) }
        .frame(maxHeight: .infinity)
        .background(Color.nc(.bgBase).ignoresSafeArea())
        // 親指が届くよう、画面の下半分に収める。
        .presentationDetents([.medium])
        .presentationDragIndicator(editing ? .visible : .hidden)
    }
}
