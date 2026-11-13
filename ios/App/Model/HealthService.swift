import Foundation
import HealthKit

/// ヘルスケアの睡眠データ(読み取りだけ)。入眠の時刻の推定にだけ使い、広告や外部への提供には使わない。
/// 睡眠の評価(点数、睡眠段階、質)はしない。
@MainActor
final class HealthService {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
    }

    /// 再生を始めた時刻 `start` 以降で、最初に「眠っている」と記録された時刻。なければ nil(確認中)。
    /// ウォッチの推定は数分ずれることがある。分単位までにとどめる。
    func sleepOnset(after start: Date, withinHours hours: Double = 6) async throws -> Date? {
        guard isAvailable else { return nil }
        let type = HKCategoryType(.sleepAnalysis)
        let window = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-15 * 60),
                                                 end: start.addingTimeInterval(hours * 3600), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: window, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, result, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: result ?? []) }
            }
            store.execute(q)
        }
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let asleep = samples.compactMap { $0 as? HKCategorySample }.filter { asleepValues.contains($0.value) && $0.endDate > start }
        guard let first = asleep.first else { return nil }
        return max(first.startDate, start)
    }
}
