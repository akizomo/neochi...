import SwiftUI
import NeochiCore

/// 初回に一度だけ聞く、ふだんの就寝時刻。記録が貯まるまでの、夜の画面を出す時間帯に使う。
struct BedtimeSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var time = Calendar.current.date(from: DateComponents(hour: 23, minute: 0)) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s4) {
            Text("ふだん、何時ごろ寝ますか?").ncText(NCText.title)
            Text("この時刻の前後にアプリを開くと、夜の画面を出します。聴いた記録が貯まると、自動で合わせます。")
                .ncText(NCText.body, .textSub)
            DatePicker("就寝時刻", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
            Button { model.saveBedtime(time) } label: {
                Text("決める").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            Button { model.saveBedtime(nil) } label: {
                Text("あとで").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
            }
        }
        .padding(NCSpace.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.nc(.bgBase).ignoresSafeArea())
    }
}
