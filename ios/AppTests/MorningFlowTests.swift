import XCTest
import NeochiCore
@testable import Neochi

/// 朝の振り返りを出すか・捨てるかの流れ(アプリを開く → 確かめる → 出す / 捨てる)を、画面を出さずに確かめる。
/// 端末にヘルスケアの睡眠データがない人(シミュレーターも同じ)の場合。
@MainActor
final class MorningFlowTests: XCTestCase {
    private let cal = Calendar.current

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    override func setUp() {
        for k in ["pendingNight", "morningAutoShownDay", "bedtimeFallback", "bedtimeAsked"] { UserDefaults.standard.removeObject(forKey: k) }
    }

    /// 24日の23:00に聴き始めて、25日の朝8:00にアプリを開いた状態。
    private func morningModel(ending: PlaybackEnding?) -> AppModel {
        let m = AppModel(shows: [], episodes: [:], pendingMorning: true)
        m.playStartedAt = date(24, 23)
        m.playLastAudibleAt = date(24, 23, 40)
        m.playEnding = ending
        m.now = { self.date(25, 8) }
        return m
    }

    private func openApp(_ m: AppModel) async {
        m.refreshForNewDay()
        try? await Task.sleep(for: .milliseconds(1500))   // 確かめて、出すまで待つ
    }

    func testManualStopWithoutHealthData_dropsTheNight() async {
        let m = morningModel(ending: .manual)
        await openApp(m)
        XCTAssertFalse(m.morningOpen, "自分で止めた晩は、振り返りを出さない")
        XCTAssertFalse(m.pendingMorning)
    }

    func testNaturalEnd_showsMorning() async {
        let m = morningModel(ending: .natural)
        await openApp(m)
        XCTAssertTrue(m.morningOpen, "最後まで流れた晩は、振り返りを出す")
    }

    func testUnknownEnding_showsMorning() async {
        let m = morningModel(ending: nil)
        await openApp(m)
        XCTAssertTrue(m.morningOpen, "終わり方が不明(アプリが落ちた)の晩は、捨てない")
    }

    /// 開いたあとの「今夜」タブの確かめ(settleMorning)でも、同じ結果になる。
    func testManualStop_settleMorningDrops() async {
        let m = morningModel(ending: .manual)
        await m.settleMorning()
        XCTAssertFalse(m.pendingMorning)
    }
}
