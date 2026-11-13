import Foundation

/// 就寝の時間帯。この時間帯にアプリを開いたら、昼の画面ではなく夜の画面を出す。
/// 再生開始の記録から決める: 早い側(下位1割)の60分前から、遅い側(上位1割)の90分後まで。
/// 平日の晩と週末の晩は分ける。記録が足りないうちは、初回に聞いた就寝時刻の前後。
public struct BedtimeWindow: Hashable, Sendable {
    /// 正午からの分(0..<1440)。夜をまたぐので、日の境目を正午に置く。
    public let lower: Int
    public let upper: Int

    public static let leadMinutes = 60
    public static let tailMinutes = 90
    public static let minimumSamples = 5
    /// 週末の晩: 金曜と土曜(Calendar の weekday: 日曜=1)。
    public static let weekendWeekdays: Set<Int> = [6, 7]

    public init(lower: Int, upper: Int) { self.lower = lower; self.upper = upper }

    /// 正午を起点にした分。22:40 → 640、01:10 → 790。
    public static func minuteSinceNoon(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return ((c.hour ?? 0) * 60 + (c.minute ?? 0) - 720 + 1440) % 1440
    }

    /// 晩の日付。午前中に始めた再生は、前の日の晩に数える(0:30 の土曜 → 金曜の晩)。
    public static func isWeekendNight(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour], from: date)
        let evening = (c.hour ?? 12) < 12 ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date) : date
        return weekendWeekdays.contains(calendar.component(.weekday, from: evening))
    }

    public static func make(starts: [Date], weekendNight: Bool, calendar: Calendar, fallback: Date? = nil) -> BedtimeWindow? {
        let mins = starts.filter { isWeekendNight($0, calendar: calendar) == weekendNight }
            .map { minuteSinceNoon($0, calendar: calendar) }.sorted()
        if mins.count >= minimumSamples {
            let low = mins[Int((Double(mins.count - 1) * 0.1).rounded(.down))]
            let high = mins[Int((Double(mins.count - 1) * 0.9).rounded(.up))]
            return BedtimeWindow(lower: max(0, low - leadMinutes), upper: min(1439, high + tailMinutes))
        }
        guard let fallback else { return nil }
        let t = minuteSinceNoon(fallback, calendar: calendar)
        return BedtimeWindow(lower: max(0, t - leadMinutes), upper: min(1439, t + tailMinutes))
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        (lower...upper).contains(Self.minuteSinceNoon(date, calendar: calendar))
    }
}
