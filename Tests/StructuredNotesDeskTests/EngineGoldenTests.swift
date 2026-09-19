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
        XCTAssertEqual(back.localVolOn, false)
        XCTAssertEqual(back.crashCorrOn, false)
        XCTAssertTrue(back.markVol.isEmpty)
        XCTAssertTrue(back.markSpot.isEmpty)
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

    func testFromJSONEmptyAndGarbageAreNil() {
        XCTAssertNil(Instrument.fromJSON(""))
        XCTAssertNil(Instrument.fromJSON("   "))
        XCTAssertNil(Instrument.fromJSON("{not json}"))
        XCTAssertEqual(BarrierObsStyle.dailyMonitored.rawValue, "Any monthly close")
        XCTAssertEqual(BarrierObsStyle.dailyMonitored.deskLabel, "Monthly closes + bridge")
    }

    func testRichIssuerCallRedeemsAtFirstDateNotAutocallTrigger() {
        var s = guaranteedNote(rate: 0.105)
        s.call = .issuerCall
        s.callObs = .quarterly
        s.callTrigger = 2.0          // unreachable autocall; issuer LS must ignore it
        s.nonCallMonths = 6
        s.chargesOn = false
        let r = Engine.price(s, paths: 1)
        XCTAssertEqual(r.probCalled, 1, accuracy: 1e-12)
        XCTAssertEqual(r.expectedLife, 0.5, accuracy: 1e-12)
        let cpn = 0.105 / 4.0
        let expected = cpn * fundingDF(s, 0.25) + cpn * fundingDF(s, 0.5) + fundingDF(s, 0.5)
        XCTAssertEqual(r.value, expected, accuracy: 1e-10)
        XCTAssertEqual(r.parLeg, fundingDF(s, 0.5), accuracy: 1e-10)
        XCTAssertEqual(r.couponLeg, 0.105 * r.qFactor, accuracy: 1e-12)
        var bullet = s
        bullet.call = .none
        let never = Engine.price(bullet, paths: 1)
        XCTAssertGreaterThan(never.value, r.value + 0.05)
    }

    func testCheapIssuerCallNeverRedeemsWhileAutocallMight() {
        var s = Instrument.initial
        s.coupon = .none
        s.call = .issuerCall
        s.callObs = .quarterly
        s.callTrigger = 1.0
        s.nonCallMonths = 0
        s.chargesOn = false
        let issuer = Engine.price(s, paths: 1)
        XCTAssertEqual(issuer.probCalled, 0, accuracy: 1e-12)
        XCTAssertEqual(issuer.value, fundingDF(s, s.termYears), accuracy: 1e-10)
        var ac = s
        ac.call = .autocall
        ac.callTrigger = 1.0
        let auto = Engine.price(ac, paths: Engine.fastPaths)
        XCTAssertGreaterThan(auto.probCalled, 0.05)
        XCTAssertGreaterThan(auto.value, issuer.value + 0.005)
    }

    func testIssuerCallCheaperThanAutocallOnRichCoupon() {
        var s = guaranteedNote(rate: 0.105)
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        let issuer = Engine.price(s, paths: 1)
        var ac = s
        ac.call = .autocall
        ac.callTrigger = 1.0
        let auto = Engine.price(ac, paths: Engine.fastPaths)
        XCTAssertGreaterThan(auto.value, issuer.value + 0.01)
        XCTAssertGreaterThan(auto.expectedLife, issuer.expectedLife + 0.2)
    }

    func testIssuerEventIsMinContinuationNotForcedPar() {
        var cheap = Instrument.initial
        cheap.call = .issuerCall
        cheap.callObs = .quarterly
        cheap.nonCallMonths = 0
        cheap.chargesOn = false
        let cheapEv = Engine.eventScenarios(cheap).first { $0.title.contains("issuer") }
        XCTAssertNotNil(cheapEv)
        let cheapAbove = cheapEv?.rows.first { abs($0.spot - 1.04) < 1e-9 }
        XCTAssertNotEqual(cheapAbove?.mark ?? 1.0, 1.0, accuracy: 1e-3)

        var rich = guaranteedNote(rate: 0.105)
        rich.call = .issuerCall
        rich.callObs = .quarterly
        rich.nonCallMonths = 6
        rich.chargesOn = false
        let richEv = Engine.eventScenarios(rich).first { $0.title.contains("issuer") }
        XCTAssertNotNil(richEv)
        for row in richEv?.rows ?? [] {
            XCTAssertEqual(row.mark, 1.0, accuracy: 1e-3)
        }
    }

    func testCouponForParWithIssuerCallPrintsPar() {
        var s = guaranteedNote(rate: 0.105)
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        XCTAssertGreaterThan(Engine.price(s, paths: 1).value, 1)
        guard let c = Engine.couponForPar(s, paths: 1) else {
            return XCTFail("solver returned nil")
        }
        s.couponRate = c
        let r = Engine.price(s, paths: 1)
        XCTAssertEqual(r.value, 1.0, accuracy: 1e-6)
        XCTAssertGreaterThan(c, 0.02)
        XCTAssertLessThan(c, 0.12)
    }

    func testCouponForParRichAndCheapIssuerCallMeetAtPar() {
        func spec(_ rate: Double) -> Instrument {
            var s = guaranteedNote(rate: rate)
            s.call = .issuerCall
            s.callObs = .quarterly
            s.nonCallMonths = 6
            s.chargesOn = false
            return s
        }
        let rich = spec(0.105)
        let cheap = spec(0.02)
        XCTAssertGreaterThan(Engine.price(rich, paths: 1).value, 1 + 1e-4)
        XCTAssertLessThan(Engine.price(cheap, paths: 1).value, 1 - 1e-4)
        guard let cRich = Engine.couponForPar(rich, paths: 1),
              let cCheap = Engine.couponForPar(cheap, paths: 1) else {
            return XCTFail("solver returned nil")
        }
        var sRich = rich; sRich.couponRate = cRich
        var sCheap = cheap; sCheap.couponRate = cCheap
        XCTAssertEqual(Engine.price(sRich, paths: 1).value, 1.0, accuracy: 1e-6)
        XCTAssertEqual(Engine.price(sCheap, paths: 1).value, 1.0, accuracy: 1e-6)
        XCTAssertEqual(cRich, cCheap, accuracy: 1e-5)
        XCTAssertGreaterThan(cRich, 0.02)
        XCTAssertLessThan(cRich, 0.10)
    }

    func testFeatureLedgerLastRowMatchesHeadlineOnDeterministicNote() {
        var s = guaranteedNote()
        s.chargesOn = false
        let led = Engine.featureLedger(s, paths: 1)
        let r = Engine.price(s, paths: 1)
        XCTAssertFalse(led.isEmpty)
        XCTAssertEqual(led.last!.value, r.value, accuracy: 1e-12)
    }

    func testFeatureLedgerLastRowMatchesHeadlineOnKI() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        let led = Engine.featureLedger(s, paths: Engine.fastPaths)
        let r = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertFalse(led.isEmpty)
        XCTAssertEqual(led.last!.value, r.value, accuracy: 1e-12)
    }

    func testFeatureLedgerLastRowMatchesHeadlineOnIssuerCall() {
        var s = guaranteedNote(rate: 0.105)
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        let led = Engine.featureLedger(s, paths: 1)
        let r = Engine.price(s, paths: 1)
        XCTAssertEqual(led.last!.value, r.value, accuracy: 1e-12)
        XCTAssertTrue(led.contains { $0.label.contains("issuer") })
    }

    func testLeverageVolAtSpotIsATMAndRisesBelow() {
        XCTAssertEqual(Engine.leverageVol(atm: 0.20, spot: 1.0, slope: 0.01), 0.20, accuracy: 1e-12)
        XCTAssertEqual(Engine.leverageVol(atm: 0.20, spot: 1.10, slope: 0.01), 0.20, accuracy: 1e-12)
        XCTAssertEqual(Engine.leverageVol(atm: 0.20, spot: 0.60, slope: 0.01), 0.24, accuracy: 1e-12)
        XCTAssertEqual(Engine.leverageVol(atm: 0.20, spot: 0.60, slope: 0), 0.20, accuracy: 1e-12)
    }

    func testLocalVolDoesNotMoveGuaranteedNote() {
        var s = guaranteedNote()
        s.chargesOn = false
        let flat = Engine.price(s, paths: 1)
        s.localVolOn = true
        s.localVolSlope = 0.025
        let loc = Engine.price(s, paths: 1)
        XCTAssertEqual(flat.value, loc.value, accuracy: 1e-12)
        XCTAssertEqual(flat.couponLeg, loc.couponLeg, accuracy: 1e-12)
    }

    func testLocalVolDoesNotChangeRichIssuerCallDecision() {
        var s = guaranteedNote(rate: 0.105)
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        s.localVolOn = true
        s.localVolSlope = 0.010
        let r = Engine.price(s, paths: 1)
        XCTAssertEqual(r.probCalled, 1, accuracy: 1e-12)
        XCTAssertEqual(r.expectedLife, 0.5, accuracy: 1e-12)
    }

    func testLocalVolZeroSlopeMatchesFlatOnKI() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        let flat = Engine.price(s, paths: Engine.fastPaths)
        s.localVolOn = true
        s.localVolSlope = 0
        let loc = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertEqual(flat.value, loc.value, accuracy: 1e-12)
        XCTAssertEqual(flat.downsideLeg, loc.downsideLeg, accuracy: 1e-12)
    }

    func testLocalVolMakesKIMoreExpensiveThanFlat() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        let flat = Engine.price(s, paths: Engine.fastPaths)
        s.localVolOn = true
        s.localVolSlope = 0.010
        let loc = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertGreaterThan(loc.downsideLeg, flat.downsideLeg + 0.001)
        XCTAssertLessThan(loc.value, flat.value - 0.001)
    }

    func testLocalVolZeroesSkewCharge() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = true
        s.localVolOn = true
        let ch = Engine.charges(s, vega: 0)
        XCTAssertEqual(ch.skew, 0, accuracy: 1e-12)
    }

    func testLegacyJSONWithoutLocalVolStillDecodes() throws {
        var s = Instrument.initial
        s.coupon = .guaranteed
        let data = try JSONEncoder().encode(s)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("not a dictionary")
        }
        obj.removeValue(forKey: "localVolOn")
        obj.removeValue(forKey: "localVolSlope")
        obj.removeValue(forKey: "crashCorrOn")
        obj.removeValue(forKey: "crashCorrSlope")
        obj.removeValue(forKey: "markVol")
        obj.removeValue(forKey: "markSpot")
        let raw = String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8) ?? ""
        let back = Instrument.fromJSON(raw)
        XCTAssertNotNil(back)
        XCTAssertEqual(back?.localVolOn, false)
        XCTAssertEqual(back?.crashCorrOn, false)
        XCTAssertTrue(back?.markVol.isEmpty ?? false)
        XCTAssertTrue(back?.markSpot.isEmpty ?? false)
        XCTAssertEqual(back?.coupon, .guaranteed)
        XCTAssertEqual(back?.termYears ?? 0, 3, accuracy: 1e-12)
    }

    func testCrashRhoAtSpotIsBaseAndRisesBelow() {
        XCTAssertEqual(Engine.crashRho(base: 0.75, basketZ: 1.0, slope: 0.05), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Engine.crashRho(base: 0.75, basketZ: 1.10, slope: 0.05), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Engine.crashRho(base: 0.75, basketZ: 0.60, slope: 0.05), 0.95, accuracy: 1e-12)
        XCTAssertEqual(Engine.crashRho(base: 0.75, basketZ: 0.60, slope: 0), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Engine.crashRho(base: 0.90, basketZ: 0.50, slope: 0.05), 0.99, accuracy: 1e-12)
    }

    func testCrashCorrDoesNotMoveGuaranteedBasket() {
        var s = guaranteedNote()
        s.members = ["SPX", "NDX"]
        s.basket = .worstOf
        s.correlation = 0.50
        s.chargesOn = false
        let flat = Engine.price(s, paths: 1)
        s.crashCorrOn = true
        s.crashCorrSlope = 0.15
        let crash = Engine.price(s, paths: 1)
        XCTAssertEqual(flat.value, crash.value, accuracy: 1e-12)
    }

    func testCrashCorrIgnoredOnSingleName() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        s.crashCorrOn = true
        s.crashCorrSlope = 0.15
        let withFlag = Engine.price(s, paths: Engine.fastPaths)
        s.crashCorrOn = false
        let off = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertEqual(withFlag.value, off.value, accuracy: 1e-12)
    }

    func testCrashCorrZeroSlopeMatchesFlatOnWeightedKI() {
        var s = Instrument.initial
        s.members = ["SPX", "NDX"]
        s.basket = .weighted
        s.weights = [0.5, 0.5, 1, 1]
        s.correlation = 0.40
        s.downside = .kiPut
        s.protection = 0.70
        s.chargesOn = false
        let flat = Engine.price(s, paths: Engine.fastPaths)
        s.crashCorrOn = true
        s.crashCorrSlope = 0
        let crash = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertEqual(flat.value, crash.value, accuracy: 1e-12)
        XCTAssertEqual(flat.downsideLeg, crash.downsideLeg, accuracy: 1e-12)
    }

    func testCrashCorrRaisesWeightedBasketKIDownside() {
        var s = Instrument.initial
        s.members = ["SPX", "NDX"]
        s.basket = .weighted
        s.weights = [0.5, 0.5, 1, 1]
        s.correlation = 0.40
        s.downside = .kiPut
        s.protection = 0.70
        s.chargesOn = false
        let flat = Engine.price(s, paths: Engine.fastPaths)
        s.crashCorrOn = true
        s.crashCorrSlope = 0.10
        let crash = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertGreaterThan(crash.downsideLeg, flat.downsideLeg + 0.0005)
        XCTAssertLessThan(crash.value, flat.value - 0.0005)
    }

    func testCrashCorrClearsWhenBasketShrinksToOne() {
        var s = Instrument.initial
        s.members = ["SPX", "NDX"]
        s.crashCorrOn = true
        s.applyBuilderRules()
        XCTAssertTrue(s.crashCorrOn)
        s.members = ["SPX"]
        s.applyBuilderRules()
        XCTAssertFalse(s.crashCorrOn)
    }

    func testCurriculumHasFourteenLessonsAndKeepsTheFirstEleven() {
        XCTAssertEqual(Teach.lessons.count, 14)
        XCTAssertEqual(Teach.lessons.map(\.number), Array(1...14))
        XCTAssertEqual(Teach.lessons[0].title, "What a note is before any features")
        XCTAssertEqual(Teach.lessons[10].title, "Where the risk actually sits")
        XCTAssertEqual(Teach.lessons[11].title, "Issuer call is not autocall at 100%")
        XCTAssertEqual(Teach.lessons[12].title, "A smile in the paths, not only a charge")
        XCTAssertEqual(Teach.lessons[13].title, "Crash corr is two-sided: worst-of vs weighted")
        for lesson in Teach.lessons where lesson.number <= 11 {
            XCTAssertFalse(lesson.spec.localVolOn, "lesson \(lesson.number) should stay on flat vol")
            XCTAssertFalse(lesson.spec.crashCorrOn, "lesson \(lesson.number) should stay on one ρ")
            XCTAssertTrue(lesson.spec.markVol.isEmpty)
            XCTAssertTrue(lesson.spec.markSpot.isEmpty)
        }
        XCTAssertEqual(Teach.lessons[11].spec.call, .issuerCall)
        XCTAssertFalse(Teach.lessons[12].spec.localVolOn)
        XCTAssertTrue(Teach.lessons[12].spec.chargesOn)
        XCTAssertFalse(Teach.lessons[13].spec.crashCorrOn)
        XCTAssertEqual(Teach.lessons[13].spec.basket, .worstOf)
    }

    func testEmptyMarkVolMatchesCatalogATM() {
        var s = Instrument.initial
        s.members = ["NVDA"]
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        XCTAssertTrue(s.markVol.isEmpty)
        XCTAssertEqual(s.atmVol(for: "NVDA"), Market.asset("NVDA").vol, accuracy: 1e-12)
        let catalog = Engine.price(s, paths: Engine.fastPaths)
        s.markVol["NVDA"] = Market.asset("NVDA").vol
        let typedSame = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertEqual(catalog.value, typedSame.value, accuracy: 1e-12)
        XCTAssertEqual(catalog.downsideLeg, typedSame.downsideLeg, accuracy: 1e-12)
    }

    func testVolShiftStacksOnMarkVol() {
        var a = Instrument.initial
        a.members = ["NVDA"]
        a.downside = .kiPut
        a.protection = 0.60
        a.chargesOn = false
        a.markVol["NVDA"] = 0.50
        a.volShift = 0.05
        var b = a
        b.markVol["NVDA"] = 0.55
        b.volShift = 0
        let pa = Engine.price(a, paths: Engine.fastPaths)
        let pb = Engine.price(b, paths: Engine.fastPaths)
        XCTAssertEqual(pa.value, pb.value, accuracy: 1e-12)
        XCTAssertEqual(pa.downsideLeg, pb.downsideLeg, accuracy: 1e-12)
    }

    func testMarkVolOverrideRaisesKIDownside() {
        var s = Instrument.initial
        s.members = ["NVDA"]
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        let base = Engine.price(s, paths: Engine.fastPaths)
        s.markVol["NVDA"] = 0.70
        let fat = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertGreaterThan(fat.downsideLeg, base.downsideLeg + 0.002)
        XCTAssertLessThan(fat.value, base.value - 0.002)
    }

    func testMarkSpotDoesNotChangePrice() {
        var s = Instrument.initial
        s.members = ["SPX"]
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = false
        let base = Engine.price(s, paths: 200)
        s.markSpot["SPX"] = 12_000
        let moved = Engine.price(s, paths: 200)
        XCTAssertEqual(base.value, moved.value, accuracy: 1e-12)
        XCTAssertEqual(s.displaySpot(for: "SPX"), 12_000, accuracy: 1e-12)
    }

    func testApplyBuilderRulesPrunesStaleMarks() {
        var s = Instrument.initial
        s.members = ["NVDA", "MSFT"]
        s.markVol = ["NVDA": 0.50, "MSFT": 0.30, "TSLA": 0.80]
        s.markSpot = ["NVDA": 200, "TSLA": 400]
        s.applyBuilderRules()
        XCTAssertEqual(s.markVol["NVDA"] ?? 0, 0.50, accuracy: 1e-12)
        XCTAssertEqual(s.markVol["MSFT"] ?? 0, 0.30, accuracy: 1e-12)
        XCTAssertNil(s.markVol["TSLA"])
        XCTAssertNil(s.markSpot["TSLA"])
        XCTAssertEqual(s.markSpot["NVDA"] ?? 0, 200, accuracy: 1e-12)
        s.members = ["SPX"]
        s.applyBuilderRules()
        XCTAssertTrue(s.markVol.isEmpty)
        XCTAssertTrue(s.markSpot.isEmpty)
    }

    func testMarkVolRoundTripsInJSON() throws {
        var s = Instrument.initial
        s.members = ["NVDA"]
        s.markVol = ["NVDA": 0.55]
        s.markSpot = ["NVDA": 210]
        let raw = s.jsonString() ?? ""
        let back = Instrument.fromJSON(raw)
        XCTAssertEqual(back?.markVol["NVDA"] ?? 0, 0.55, accuracy: 1e-12)
        XCTAssertEqual(back?.markSpot["NVDA"] ?? 0, 210, accuracy: 1e-12)
        XCTAssertEqual(back?.atmVol(for: "NVDA") ?? 0, 0.55, accuracy: 1e-12)
    }

    func testCrashCorrWorstOfAndWeightedMoveOppositeOnKI() {
        var wo = Instrument.initial
        wo.members = ["SPX", "NDX", "RTY"]
        wo.basket = .worstOf
        wo.correlation = 0.40
        wo.downside = .kiPut
        wo.protection = 0.70
        wo.chargesOn = false
        let woFlat = Engine.price(wo, paths: Engine.fastPaths)
        wo.crashCorrOn = true
        wo.crashCorrSlope = 0.10
        let woCrash = Engine.price(wo, paths: Engine.fastPaths)

        var wt = wo
        wt.crashCorrOn = false
        wt.basket = .weighted
        wt.weights = [1.0 / 3, 1.0 / 3, 1.0 / 3, 1]
        let wtFlat = Engine.price(wt, paths: Engine.fastPaths)
        wt.crashCorrOn = true
        wt.crashCorrSlope = 0.10
        let wtCrash = Engine.price(wt, paths: Engine.fastPaths)

        // Weighted KI: spike fattens left-tail variance → more expensive put.
        XCTAssertGreaterThan(wtCrash.downsideLeg, wtFlat.downsideLeg + 0.0005)
        // Two-sided vs worst-of: holder is long corr, so the same spike cannot
        // fatten the WO put the way it fattens the weighted one.
        XCTAssertLessThan(woCrash.downsideLeg - woFlat.downsideLeg,
                          wtCrash.downsideLeg - wtFlat.downsideLeg - 0.001)
    }

    func testCrashCorrWithLocalVolStillRaisesWeightedKI() {
        var s = Instrument.initial
        s.members = ["SPX", "NDX"]
        s.basket = .weighted
        s.weights = [0.5, 0.5, 1, 1]
        s.correlation = 0.40
        s.downside = .kiPut
        s.protection = 0.70
        s.chargesOn = false
        s.localVolOn = true
        s.localVolSlope = 0.010
        let loc = Engine.price(s, paths: Engine.fastPaths)
        s.crashCorrOn = true
        s.crashCorrSlope = 0.10
        let both = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertTrue(both.value.isFinite)
        XCTAssertTrue(both.downsideLeg.isFinite)
        XCTAssertGreaterThan(both.downsideLeg, loc.downsideLeg + 0.0003)
        XCTAssertLessThan(both.value, loc.value - 0.0003)
    }

    func testMonthlyKIWithAsianDoesNotWatchTheDailyGrid() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.80
        s.averaging = .lastMonth
        s.chargesOn = false
        s.protObs = .monthly
        let monthly = Engine.price(s, paths: Engine.fastPaths)
        s.protObs = .daily
        let daily = Engine.price(s, paths: Engine.fastPaths)
        XCTAssertGreaterThanOrEqual(daily.probLoss, monthly.probLoss)
        XCTAssertLessThan(daily.value, monthly.value - 0.0002)
        XCTAssertGreaterThan(daily.downsideLeg, monthly.downsideLeg)
    }

    func testCouponRateChangeWithIssuerCallIsNotStraightLineCopy() {
        var a = Instrument.initial
        a.coupon = .guaranteed
        a.couponRate = 0.08
        a.call = .issuerCall
        a.callObs = .quarterly
        var b = a
        b.couponRate = 0.12
        let note = Teach.describeChange(from: a, to: b)
        XCTAssertNotNil(note)
        XCTAssertFalse(note?.why.contains("straight line") ?? true)
        XCTAssertTrue(note?.why.localizedCaseInsensitiveContains("issuer") ?? false)
    }

    func testIssuerFirstCallEventDoesNotForceACheapZeroToPar() {
        var s = Instrument.initial
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        let ev = Engine.eventScenarios(s)
        let issuer = ev.first { $0.title.localizedCaseInsensitiveContains("issuer") }
        XCTAssertNotNil(issuer)
        let atPar = issuer?.rows.first { abs($0.spot - 1.0) < 1e-9 }
        XCTAssertNotNil(atPar)
        XCTAssertLessThan(atPar?.mark ?? 1, 0.99)
        XCTAssertTrue(issuer?.caption.contains("not a 100% trigger") ?? false)
    }

    func testLegacyJSONPatchesEmptyMarkObjects() throws {
        var s = Instrument.initial
        s.coupon = .guaranteed
        let data = try JSONEncoder().encode(s)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("not a dictionary")
        }
        obj.removeValue(forKey: "markVol")
        obj.removeValue(forKey: "markSpot")
        let raw = String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8) ?? ""
        let back = Instrument.fromJSON(raw)
        XCTAssertNotNil(back)
        XCTAssertTrue(back?.markVol.isEmpty ?? false)
        XCTAssertTrue(back?.markSpot.isEmpty ?? false)
        XCTAssertEqual(back?.atmVol(for: "SPX") ?? 0, Market.asset("SPX").vol, accuracy: 1e-12)
    }

    func testChargesDefaultMatchesExplicitFastPaths() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = true
        let mid = Engine.price(s, paths: Engine.fastPaths).value
        let a = Engine.charges(s, vega: 0)
        let b = Engine.charges(s, vega: 0, paths: Engine.fastPaths)
        XCTAssertEqual(a.skew, b.skew, accuracy: 1e-12)
        XCTAssertEqual(a.overhedge, b.overhedge, accuracy: 1e-12)
        XCTAssertEqual(a.total, b.total, accuracy: 1e-12)
        XCTAssertEqual(a.offer, b.offer, accuracy: 1e-12)
        XCTAssertEqual(a.mid, b.mid, accuracy: 1e-12)
        XCTAssertEqual(a.mid, mid, accuracy: 1e-12)
        XCTAssertEqual(a.offer, a.mid - a.total, accuracy: 1e-12)
        XCTAssertEqual(a.paths, Engine.fastPaths)
    }

    func testSensitivitiesDefaultMatchesExplicitFastPaths() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        let mark = Engine.price(s, paths: Engine.fullPaths).value
        let a = Engine.sensitivities(s, mark: mark)
        let b = Engine.sensitivities(s, mark: mark, paths: Engine.fastPaths)
        XCTAssertEqual(a.delta, b.delta, accuracy: 1e-12)
        XCTAssertEqual(a.vega, b.vega, accuracy: 1e-12)
        XCTAssertEqual(a.mark, mark, accuracy: 1e-12)
        XCTAssertEqual(b.mark, mark, accuracy: 1e-12)
    }

    func testCouponForParPathCountPicksHeadlineWhenLinear() {
        var linear = guaranteedNote()
        linear.chargesOn = false
        linear.call = .none
        XCTAssertEqual(Engine.couponForParPathCount(linear), Engine.fullPaths)

        var charged = linear
        charged.chargesOn = true
        XCTAssertEqual(Engine.couponForParPathCount(charged), Engine.fastPaths)

        var issuer = linear
        issuer.call = .issuerCall
        XCTAssertEqual(Engine.couponForParPathCount(issuer), Engine.fastPaths)
    }

    func testCouponForParChargesOnOfferIsParAtSolverPathCount() {
        var s = guaranteedNote(rate: 0.12)
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = true
        s.call = .none
        let n = 80
        XCTAssertNotEqual(n, Engine.fastPaths)
        XCTAssertNotEqual(n, Engine.fullPaths)
        guard let c = Engine.couponForPar(s, paths: n) else {
            return XCTFail("solver returned nil")
        }
        s.couponRate = c
        let r = Engine.price(s, paths: n)
        let g = Engine.sensitivities(s, mark: r.value, paths: n)
        let ch = Engine.charges(s, vega: g.vega, paths: n)
        XCTAssertEqual(ch.mid, r.value, accuracy: 1e-12)
        XCTAssertEqual(ch.offer, ch.mid - ch.total, accuracy: 1e-12)
        XCTAssertEqual(ch.paths, n)
        XCTAssertEqual(ch.offer, 1.0, accuracy: 1e-5)
        XCTAssertGreaterThan(c, 0.01)
        XCTAssertLessThan(c, 0.25)
    }

    func testOfferUsesSamePathMidNotHeadline() {
        var s = Instrument.initial
        s.downside = .kiPut
        s.protection = 0.60
        s.chargesOn = true
        let n = 80
        let prefix = Engine.price(s, paths: n).value
        let head = Engine.price(s, paths: Engine.fullPaths).value
        let g = Engine.sensitivities(s, mark: prefix, paths: n)
        let ch = Engine.charges(s, vega: g.vega, paths: n)
        XCTAssertEqual(ch.paths, n)
        XCTAssertEqual(ch.mid, prefix, accuracy: 1e-12)
        XCTAssertEqual(ch.offer, ch.mid - ch.total, accuracy: 1e-12)
        XCTAssertNotEqual(head, prefix, accuracy: 1e-6)
        XCTAssertNotEqual(ch.offer, head - ch.total, accuracy: 1e-6)
        XCTAssertGreaterThan(ch.total, 0)
    }

    func testChargesOffStackIsZero() {
        var s = Instrument.initial
        s.chargesOn = false
        let ch = Engine.charges(s, vega: 0.01)
        XCTAssertEqual(ch.total, 0, accuracy: 1e-12)
        XCTAssertEqual(ch.offer, 0, accuracy: 1e-12)
        XCTAssertEqual(ch.mid, 0, accuracy: 1e-12)
        XCTAssertEqual(ch.paths, Engine.fastPaths)
    }

    func testMonteCarloGlossaryNamesBumpPrefix() {
        let mc = Teach.glossary.first { $0.name == "Monte Carlo" }
        XCTAssertNotNil(mc)
        XCTAssertTrue(mc?.desk.contains("1,600") ?? false)
        XCTAssertTrue(mc?.desk.localizedCaseInsensitiveContains("prefix") ?? false
                      || mc?.desk.contains("first 1,600") ?? false)
        XCTAssertTrue(mc?.desk.contains("4,000") ?? false || mc?.desk.contains("Four thousand") ?? false)
        let crn = Teach.glossary.first { $0.name == "Common random numbers" }
        XCTAssertTrue(crn?.desk.localizedCaseInsensitiveContains("prefix") ?? false)
        let ev = Teach.glossary.first { $0.name == "Estimated value" }
        XCTAssertTrue(ev?.desk.contains("1,600") ?? false)
        XCTAssertTrue(ev?.desk.contains("4,000") ?? false)
    }

    func testIssuerEventCaptionNamesCRNPrefixNotHeadline() {
        var s = Instrument.initial
        s.call = .issuerCall
        s.callObs = .quarterly
        s.nonCallMonths = 6
        s.chargesOn = false
        let ev = Engine.eventScenarios(s)
        let issuer = ev.first { $0.title.localizedCaseInsensitiveContains("issuer") }
        XCTAssertNotNil(issuer)
        XCTAssertTrue(issuer?.caption.contains("not a 100% trigger") ?? false)
        XCTAssertTrue(issuer?.caption.localizedCaseInsensitiveContains("prefix") ?? false)
        XCTAssertFalse(issuer?.caption.contains("same paths as the mark") ?? true)
    }
}
