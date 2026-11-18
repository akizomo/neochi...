import XCTest
@testable import NeochiCore

final class PremiumTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    func testNoPurchasesIsFree() {
        let e = Entitlement.resolve([], now: now)
        XCTAssertEqual(e, .free)
        XCTAssertFalse(e.isActive)
        for f in PremiumFeature.allCases { XCTAssertFalse(e.allows(f)) }
    }

    func testTrialIsActiveUntilExpiry() {
        let f = PurchaseFact(plan: .yearly, expiresAt: day(14), isTrial: true)
        let e = Entitlement.resolve([f], now: now)
        XCTAssertEqual(e, .trial(.yearly, until: day(14)))
        XCTAssertTrue(e.allows(.startAtContent))
    }

    func testSubscribedAndExpired() {
        let f = PurchaseFact(plan: .monthly, expiresAt: day(10))
        XCTAssertEqual(Entitlement.resolve([f], now: now), .subscribed(.monthly, until: day(10)))
        let later = Entitlement.resolve([f], now: day(11))
        XCTAssertEqual(later, .expired(since: day(10)))
        XCTAssertFalse(later.isActive)
    }

    func testRevokedIsIgnored() {
        let f = PurchaseFact(plan: .yearly, expiresAt: day(300), isRevoked: true)
        let e = Entitlement.resolve([f], now: now)
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e, .expired(since: nil))
    }

    func testLongestLiveWinsAndTrialYieldsToPaid() {
        let trial = PurchaseFact(plan: .yearly, expiresAt: day(14), isTrial: true)
        let paid = PurchaseFact(plan: .yearly, expiresAt: day(365))
        XCTAssertEqual(Entitlement.resolve([trial, paid], now: now), .subscribed(.yearly, until: day(365)))
    }

    func testNoExpiryCountsAsActive() {
        XCTAssertEqual(Entitlement.resolve([PurchaseFact(plan: .yearly, expiresAt: nil)], now: now), .subscribed(.yearly, until: nil))
    }

    func testProductIDsRoundTrip() {
        for p in PremiumPlan.allCases { XCTAssertEqual(PremiumPlan(productID: p.productID), p) }
        XCTAssertNil(PremiumPlan(productID: "other"))
    }
}
