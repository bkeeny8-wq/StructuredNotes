import XCTest
@testable import StructuredNotesDesk

/// Hand-check identities from the v22 evaluation (§7). Deterministic notes
/// use a single path: full protection + guaranteed cash flows do not depend
/// on the Brownian draws.
final class EngineGoldenTests: XCTestCase {

    private let paths = 1

    private func fundingDF(_ s: Instrument, _ t: Double) -> Double {
        exp(-Engine.fundingZero(s, t) * t)
    }

    /// Closed-form coupon strip: calendar month-ends from issue, no stub cash.
    private func guaranteedCouponLeg(_ s: Instrument) -> (leg: Double, q: Double, n: Int) {
        let termMonths = max(1, Int((s.termYears * 12.0).rounded()))
        let period = s.couponObs.monthsPerPeriod
        guard s.coupon == .guaranteed, period > 0 else { return (0, 0, 0) }
        let yearFrac = 1.0 / Double(s.couponObs.perYear)
        var q = 0.0
        var n = 0
        var m = period
        while m <= termMonths {
            let t = Double(m) / 12.0
            q += yearFrac * fundingDF(s, t)
            n += 1
            m += period
        }
        return (s.couponRate * q, q, n)
    }

    private func guaranteedNote(termYears: Double = 3,
                                rate: Double = 0.105,
                                obs: CouponObs = .quarterly) -> Instrument {
        var s = Instrument.initial
        s.coupon = .guaranteed
        s.couponRate = rate
        s.couponObs = obs
        s.termYears = termYears
        return s
    }

    func testInitialIsFundingZero() {
        let s = Instrument.initial
        let r = Engine.price(s, paths: paths)
        let expected = fundingDF(s, s.termYears)
        XCTAssertEqual(r.value, expected, accuracy: 1e-12)
        XCTAssertEqual(r.parLeg, expected, accuracy: 1e-12)
        XCTAssertEqual(r.couponLeg, 0, accuracy: 1e-12)
    }

    func testGuaranteedQuarterly3yClosedForm() {
        let s = guaranteedNote()
        let r = Engine.price(s, paths: paths)
        let par = fundingDF(s, 3)
        let cpn = guaranteedCouponLeg(s)
        XCTAssertEqual(r.parLeg, par, accuracy: 1e-10)
        XCTAssertEqual(r.couponLeg, cpn.leg, accuracy: 1e-10)
        XCTAssertEqual(r.value, par + cpn.leg, accuracy: 1e-10)
        XCTAssertEqual(Double(cpn.n), 12, accuracy: 1e-12)
        // Lesson-2 anchors against the Jul-2026 curve baked into Instrument.initial.
        XCTAssertEqual(r.parLeg, 0.8657, accuracy: 5e-5)
        XCTAssertEqual(r.couponLeg, 0.2921, accuracy: 5e-5)
        XCTAssertEqual(r.qFactor, 2.782, accuracy: 5e-4)
    }

    func testNoDailyCouponCase() {
        XCTAssertFalse(CouponObs.allCases.contains { $0.rawValue.lowercased().contains("daily") })
        XCTAssertEqual(CouponObs.allCases.count, 5)
        let monthly = Engine.price(guaranteedNote(rate: 0.10, obs: .monthly), paths: paths)
        let quarterly = Engine.price(guaranteedNote(rate: 0.10, obs: .quarterly), paths: paths)
        XCTAssertGreaterThan(monthly.couponLeg, quarterly.couponLeg)
    }

    func testOneMonthQuarterlyPaysNoCoupon() {
        let s = guaranteedNote(termYears: 1.0 / 12.0, rate: 0.10)
        let r = Engine.price(s, paths: paths)
        let df = fundingDF(s, s.termYears)
        XCTAssertEqual(r.couponLeg, 0, accuracy: 1e-12)
        XCTAssertEqual(r.avgCoupons, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(0.025 * df, 0.02)
        XCTAssertLessThan(r.couponLeg, 0.001)
    }

    func testCouponLegEqualsRateTimesQ() {
        let s = guaranteedNote()
        let r = Engine.price(s, paths: paths)
        XCTAssertEqual(r.couponLeg, s.couponRate * r.qFactor, accuracy: 1e-12)
    }

    func testLinearCapBindsAtFortyPercentIndex() {
        var s = Instrument.initial
        s.upside = .linear
        s.participation = 1.5
        s.cap = 1.30
        let (up, loss) = Engine.components(perf: 1.40, knocked: false, s: s)
        XCTAssertEqual(up, 0.30, accuracy: 1e-12)
        XCTAssertEqual(loss, 0, accuracy: 1e-12)
    }

    func testSnowballIgnoresCouponRateAndUsesSnowballRate() {
        var s = Instrument.initial
        s.coupon = .guaranteed
        s.couponRate = 0.10
        s.snowball = true
        s.snowballRate = 0.08
        s.call = .none
        let v0 = Engine.price(s, paths: paths).value
        s.couponRate = 0.20
        let v1 = Engine.price(s, paths: paths).value
        XCTAssertEqual(v0, v1, accuracy: 1e-12)
        s.snowballRate = 0.12
        let v2 = Engine.price(s, paths: paths).value
        XCTAssertGreaterThan(v2, v1)
    }

    func testLockInClearsWhenCallTurnsOff() {
        var s = Instrument.initial
        s.call = .autocall
        s.lockIn = true
        s.applyBuilderRules()
        XCTAssertTrue(s.lockIn)
        s.call = .none
        s.applyBuilderRules()
        XCTAssertFalse(s.lockIn)
        XCTAssertFalse(s.snowball)
    }

    func testFiveMonthQuarterlyPaysOneCouponAtThreeMonths() {
        let s = guaranteedNote(termYears: 5.0 / 12.0, rate: 0.10)
        let r = Engine.price(s, paths: paths)
        let onePay = 0.025 * fundingDF(s, 0.25)
        XCTAssertEqual(r.avgCoupons, 1, accuracy: 1e-12)
        XCTAssertEqual(r.couponLeg, onePay, accuracy: 1e-10)
        XCTAssertEqual(guaranteedCouponLeg(s).n, 1)
    }

    func testThirteenMonthAnnualPaysAtOneYearNotMaturity() {
        let s = guaranteedNote(termYears: 13.0 / 12.0, rate: 0.10, obs: .annual)
        let r = Engine.price(s, paths: paths)
        let atOneYear = 0.10 * fundingDF(s, 1.0)
        XCTAssertEqual(r.avgCoupons, 1, accuracy: 1e-12)
        XCTAssertEqual(r.couponLeg, atOneYear, accuracy: 1e-10)
        let wrongMaturityPay = 0.10 * fundingDF(s, s.termYears)
        XCTAssertGreaterThan(abs(wrongMaturityPay - r.couponLeg), 1e-4)
    }

    func testInstrumentCodableRoundTrip() throws {
        var s = Instrument.initial
        s.coupon = .guaranteed
        s.couponRate = 0.105
        s.cap = 1.30
        s.upside = .linear
        s.participation = 1.5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Instrument.self, from: data)
        XCTAssertEqual(back.members, s.members)
        XCTAssertEqual(back.coupon, .guaranteed)
        XCTAssertEqual(back.couponRate, s.couponRate, accuracy: 1e-12)
        XCTAssertEqual(back.cap ?? 0, 1.30, accuracy: 1e-12)
        XCTAssertEqual(back.upside, .linear)
        XCTAssertEqual(Instrument.fromJSON(s.jsonString() ?? "")?.termYears ?? 0, 3, accuracy: 1e-12)
    }

    func testDailyKIWithAsianTailKnocksAtLeastAsOftenAsEuropean() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.80
        s.averaging = .lastMonth
        s.protObs = .european
        let eu = Engine.price(s, paths: Engine.fastPaths)
        s.protObs = .daily
        let daily = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertGreaterThanOrEqual(daily.probLoss + 0.03, eu.probLoss)
    }

    func testLumpedCallBarIsLabeledLater() {
        var s = Instrument.initial
        s.termYears = 7
        s.call = .autocall
        s.callObs = .monthly
        s.callTrigger = 1.0
        s.nonCallMonths = 0
        let r = Engine.price(s, paths: 400)
        if r.callDist.count == 5 {
            XCTAssertTrue(r.callDist.last?.lumped == true)
        }
    }

    func testParBondHasZeroProbLoss() {
        let r = Engine.price(Instrument.initial, paths: paths)
        XCTAssertEqual(r.probLoss, 0, accuracy: 1e-12)
    }

    func testProbLossIsPrincipalShortfallNotKnock() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        // Knocked but recovered through par: no principal shortfall.
        let (_, recovered) = Engine.components(perf: 1.05, knocked: true, s: s)
        XCTAssertEqual(recovered, 0, accuracy: 1e-12)
        // Knocked and below par: loss from par, not from the barrier.
        let (_, shortfall) = Engine.components(perf: 0.80, knocked: true, s: s)
        XCTAssertEqual(shortfall, 0.20, accuracy: 1e-12)
        // Clean finish below par but above the barrier: European KI does not knock.
        let (_, clean) = Engine.components(perf: 0.90, knocked: false, s: s)
        XCTAssertEqual(clean, 0, accuracy: 1e-12)
    }

    func testEuropeanCouponPaysRateTimesTenorAtMaturity() {
        var s = guaranteedNote(termYears: 3, rate: 0.10, obs: .european)
        let r = Engine.price(s, paths: paths)
        let expected = 0.10 * 3 * fundingDF(s, 3)
        XCTAssertEqual(r.couponLeg, expected, accuracy: 1e-10)
        XCTAssertEqual(r.avgCoupons, 1, accuracy: 1e-12)
        XCTAssertEqual(r.qFactor, 3 * fundingDF(s, 3), accuracy: 1e-10)
    }

    func testOneMonthThetaIsNotANoOp() {
        var s = Instrument.initial
        s.termYears = 1.0 / 12.0
        let mark = Engine.price(s, paths: paths).value
        let g = Engine.sensitivities(s, mark: mark)
        XCTAssertGreaterThan(abs(g.theta1m), 1e-8)
        // Pull to par: a shorter remaining life raises the zero.
        XCTAssertGreaterThan(g.theta1m, 0)
    }

    func testFirstCallEventRedeemsAtParAboveTrigger() {
        var s = Instrument.initial
        s.call = .autocall
        s.callTrigger = 1.0
        s.callObs = .quarterly
        s.nonCallMonths = 0
        s.termYears = 3
        XCTAssertEqual(Engine.firstCallMonth(s), 3)
        let ev = Engine.eventScenarios(s)
        let first = ev.first { $0.title.contains("first call") }
        XCTAssertNotNil(first)
        let above = first?.rows.first { abs($0.spot - 1.04) < 1e-9 }
        XCTAssertEqual(above?.mark ?? 0, 1.0, accuracy: 1e-8)
        let below = first?.rows.first { abs($0.spot - 0.96) < 1e-9 }
        XCTAssertNotEqual(below?.mark ?? 1.0, 1.0, accuracy: 1e-4)
    }

    func testCouponForParPrintsGuaranteedNoteAtPar() {
        var s = guaranteedNote(rate: 0.105)
        s.chargesOn = false
        guard let c = Engine.couponForPar(s, paths: 1) else {
            return XCTFail("solver returned nil")
        }
        s.couponRate = c
        let r = Engine.price(s, paths: 1)
        XCTAssertEqual(r.value, 1.0, accuracy: 1e-8)
        XCTAssertGreaterThan(c, 0.03)
        XCTAssertLessThan(c, 0.07)
        XCTAssertNil(Engine.couponForPar(Instrument.initial, paths: 1))
    }

    func testCouponDailyMonitorKillsAtLeastAsOftenAsPaymentDate() {
        var s = Instrument.initial
        s.coupon = .contingent
        s.couponRate = 0.10
        s.couponBarrier = 0.90
        s.couponObs = .monthly
        s.couponBarrierObs = .onPaymentDate
        s.chargesOn = false
        let pay = Engine.price(s, paths: Engine.fastPaths)
        s.couponBarrierObs = .dailyMonitored
        let daily = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertLessThanOrEqual(daily.couponLeg, pay.couponLeg + 0.005)
        XCTAssertEqual(BarrierObsStyle.dailyMonitored.deskLabel, "Monthly closes + bridge")
    }

    func testCatalogDisplayNamesAndHonestEstVols() {
        XCTAssertEqual(Market.asset("IBIT").name, "iShares Bitcoin Trust")
        XCTAssertGreaterThan(Market.asset("IBIT").vol, 0.40)
        XCTAssertTrue(Market.asset("TLT").name.contains("Treasury"))
        XCTAssertLessThan(Market.asset("TLT").vol, 0.22)
        XCTAssertNotEqual(Market.asset("XLP").name, "XLP")
        XCTAssertLessThan(Market.asset("XLP").vol, 0.20)
        XCTAssertNotEqual(Market.asset("XLF").name, "XLF")
    }
}
