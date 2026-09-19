//  Models.swift
//  Structured Notes
//
//  Always-price philosophy: every dial is an input; the output is the note's
//  model value as a percentage of par. Build a custom basket by adding
//  underliers one at a time (worst-of or weighted). Coupon and call schedules
//  are set in their own blocks; protection and final-valuation averaging are
//  set separately.

import Foundation

public enum BasketStyle: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case worstOf = "Worst-of"
    case weighted = "Weighted basket"
    public var id: String { rawValue }
}

/// Asian tail on the final valuation: average of daily closes over the last
/// week (5 fixings) or the last month (21 fixings).
public enum FinalAveraging: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case none = "Final close"
    case lastWeek = "Avg last week (5d)"
    case lastMonth = "Avg last month (21d)"
    public var id: String { rawValue }
    public var fixings: Int { self == .none ? 0 : (self == .lastWeek ? 5 : 21) }
}

public enum CouponStyle: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case none = "No coupon"
    case guaranteed = "Guaranteed"
    case contingent = "Contingent"
    public var id: String { rawValue }
}

/// Coupon observation schedule. Dates are calendar month-ends from issue
/// (quarterly = 3, 6, 9, … months). An incomplete leftover stub at maturity
/// does not pay. European pays the full rate × tenor once at maturity.
public enum CouponObs: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case monthly = "Monthly", quarterly = "Quarterly", semiannual = "Semi-annual", annual = "Annual"
    case european = "European (at maturity)"
    public var id: String { rawValue }
    public var perYear: Int {
        switch self {
        case .monthly: return 12
        case .quarterly: return 4
        case .semiannual: return 2
        case .annual: return 1
        case .european: return 0
        }
    }
    /// Months between coupon dates on the calendar schedule. 0 = European.
    public var monthsPerPeriod: Int { perYear > 0 ? 12 / perYear : 0 }
}

/// Contingent-coupon barrier observation: payment-date close only, or monthly
/// closes plus a Brownian-bridge one-touch during the coupon period — the same
/// interpolation KI daily monitoring uses.
public enum BarrierObsStyle: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case onPaymentDate = "On payment date"
    case dailyMonitored = "Any monthly close"   // persisted label; UI shows deskLabel
    public var id: String { rawValue }
    public var deskLabel: String {
        switch self {
        case .onPaymentDate: return "On payment date"
        case .dailyMonitored: return "Monthly closes + bridge"
        }
    }
}

public enum CallObs: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case monthly = "Monthly", quarterly = "Quarterly", semiannual = "Semi-annual", annual = "Annual"
    public var id: String { rawValue }
    public var perYear: Int {
        switch self {
        case .monthly: return 12
        case .quarterly: return 4
        case .semiannual: return 2
        case .annual: return 1
        }
    }
    public var monthsPerPeriod: Int { 12 / perYear }
}

public enum CallFeature: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case none = "No call"
    case autocall = "Autocall"
    case issuerCall = "Issuer call"
    public var id: String { rawValue }
}

public enum ProtectionObs: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case european = "European (final only)"
    case quarterly = "Quarterly monitored"
    case monthly = "Monthly monitored"
    case daily = "Monthly closes + bridge"
    public var id: String { rawValue }
    public var perYear: Int {
        switch self {
        case .european: return 0
        case .quarterly: return 4
        default: return 12
        }
    }
    public var monthsPerPeriod: Int { perYear > 0 ? 12 / perYear : 0 }
}

public enum DownsideKind: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case par = "Full protection"
    case buffer = "Buffer (vanilla put)"
    case kiPut = "Knock-in put"
    public var id: String { rawValue }
}

public enum UpsideKind: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case none = "None"
    case linear = "Linear participation"
    case digital = "Digital"
    case digitalPlus = "Digi-plus"
    case absolute = "Absolute (dual directional)"
    public var id: String { rawValue }
}

public struct Instrument: Hashable, Sendable, Codable {
    // underlying: build the basket by adding members (1–4)
    public var members: [String]     // catalog tickers
    public var basket: BasketStyle
    public var weights: [Double]            // parallel to members; normalized in the engine
    public var correlation: Double
    // tenor & final valuation
    public var termYears: Double            // monthly increments, 1m–7y
    public var averaging: FinalAveraging
    // coupon block
    public var coupon: CouponStyle
    public var couponRate: Double           // an input, like everything else
    public var couponObs: CouponObs
    public var couponBarrier: Double
    public var couponBarrierObs: BarrierObsStyle
    public var memory: Bool
    // callability block
    public var call: CallFeature
    public var callObs: CallObs
    public var callTrigger: Double
    public var triggerStep: Double          // step-down per year after the non-call period
    public var callPremium: Double          // p.a., paid at call on top of par; nothing at maturity
    public var nonCallMonths: Double        // monthly slider
    public var snowball: Bool               // coupons accrue and pay at call
    public var snowballRate: Double         // the accrual rate is its own input
    public var lockIn: Bool                 // Memorizer: touch the lock level → par locks
    public var lockLevel: Double
    // upside block
    public var upside: UpsideKind
    public var participation: Double
    public var cap: Double?                 // nil = uncapped
    public var digital: Double
    public var digitalStrike: Double        // digital pays when final ≥ this; < 100% = in-the-money
    public var digiPlusLeverage: Double     // digi-plus: max(digital, leverage × gain), leverage ≥ 1
    public var absoluteKO: Double           // absolute-return zone dies below this level
    public var absParticipation: Double     // participation on the absolute (down) side
    // downside block
    public var downside: DownsideKind
    public var protection: Double
    public var gearedBuffer: Bool
    public var minRedemption: Double        // 0 = off
    public var secondChance: Bool           // Elite: a monitored knock is forgiven if the
    public var secondChanceLevel: Double    // final level recovers to at least this
    public var protObs: ProtectionObs
    // rates & funding: editable UST pillars + a two-point funding spread curve
    public var ust3m: Double
    public var ust1y: Double
    public var ust2y: Double
    public var ust3y: Double
    public var ust5y: Double
    public var ust7y: Double
    public var spreadShort: Double      // funding spread over UST at 1y
    public var spreadLong: Double       // funding spread over UST at 7y (interpolated between)
    public var volShift: Double
    /// Per-ticker ATM vol override. Empty → catalog. Typed on Underlying and
    /// persisted with the spec. *Your* snapshot, not a live implied.
    public var markVol: [String: Double]
    /// Per-ticker spot override for display. Paths run in return space, so
    /// this does not change the mark. Empty → catalog.
    public var markSpot: [String: Double]
    /// Teaching local-vol: σ(x) = σ_ATM + slope × max(1−x, 0) × 10.
    /// Default off so lessons still run on flat vol + a skew charge.
    public var localVolOn: Bool
    public var localVolSlope: Double    // vol pts per 10% below spot; same units as skewSlope
    /// Teaching crash corr: ρ(z) = ρ + slope × max(1−z, 0) × 10, capped at 0.99.
    /// Default off so lessons still run on one equicorrelation.
    public var crashCorrOn: Bool
    public var crashCorrSlope: Double   // extra ρ per 10% basket drop below spot
    // charges & reserves: bridge model mid to the dealer offer
    public var chargesOn: Bool
    public var skewSlope: Double        // vol pts per 10% moneyness on the downside wing
    public var barrierShift: Double     // client-adverse overhedge shift on discontinuities
    public var corrBA: Double           // correlation bid-ask half-width
    public var volBA: Double            // vol bid-ask, charged on |vega|
    public var reserveBps: Double       // flat model/rebalancing reserve
    public var ufFee: Double            // underwriting fee: advisor + wholesaler, % of principal

    public var nonCallYears: Double { nonCallMonths / 12.0 }

    public init(
        members: [String], basket: BasketStyle, weights: [Double], correlation: Double,
        termYears: Double, averaging: FinalAveraging,
        coupon: CouponStyle, couponRate: Double, couponObs: CouponObs,
        couponBarrier: Double, couponBarrierObs: BarrierObsStyle, memory: Bool,
        call: CallFeature, callObs: CallObs, callTrigger: Double, triggerStep: Double,
        callPremium: Double,
        nonCallMonths: Double, snowball: Bool, snowballRate: Double,
        lockIn: Bool, lockLevel: Double,
        upside: UpsideKind, participation: Double, cap: Double?, digital: Double,
        digitalStrike: Double, digiPlusLeverage: Double,
        absoluteKO: Double, absParticipation: Double,
        downside: DownsideKind, protection: Double, gearedBuffer: Bool,
        minRedemption: Double, secondChance: Bool, secondChanceLevel: Double,
        protObs: ProtectionObs,
        ust3m: Double, ust1y: Double, ust2y: Double, ust3y: Double, ust5y: Double, ust7y: Double,
        spreadShort: Double, spreadLong: Double, volShift: Double,
        markVol: [String: Double] = [:], markSpot: [String: Double] = [:],
        localVolOn: Bool, localVolSlope: Double,
        crashCorrOn: Bool, crashCorrSlope: Double,
        chargesOn: Bool, skewSlope: Double, barrierShift: Double,
        corrBA: Double, volBA: Double, reserveBps: Double, ufFee: Double
    ) {
        self.members = members; self.basket = basket; self.weights = weights; self.correlation = correlation
        self.termYears = termYears; self.averaging = averaging
        self.coupon = coupon; self.couponRate = couponRate; self.couponObs = couponObs
        self.couponBarrier = couponBarrier; self.couponBarrierObs = couponBarrierObs; self.memory = memory
        self.call = call; self.callObs = callObs; self.callTrigger = callTrigger; self.triggerStep = triggerStep
        self.callPremium = callPremium
        self.nonCallMonths = nonCallMonths; self.snowball = snowball; self.snowballRate = snowballRate
        self.lockIn = lockIn; self.lockLevel = lockLevel
        self.upside = upside; self.participation = participation; self.cap = cap; self.digital = digital
        self.digitalStrike = digitalStrike; self.digiPlusLeverage = digiPlusLeverage
        self.absoluteKO = absoluteKO; self.absParticipation = absParticipation
        self.downside = downside; self.protection = protection; self.gearedBuffer = gearedBuffer
        self.minRedemption = minRedemption; self.secondChance = secondChance; self.secondChanceLevel = secondChanceLevel
        self.protObs = protObs
        self.ust3m = ust3m; self.ust1y = ust1y; self.ust2y = ust2y
        self.ust3y = ust3y; self.ust5y = ust5y; self.ust7y = ust7y
        self.spreadShort = spreadShort; self.spreadLong = spreadLong; self.volShift = volShift
        self.markVol = markVol; self.markSpot = markSpot
        self.localVolOn = localVolOn; self.localVolSlope = localVolSlope
        self.crashCorrOn = crashCorrOn; self.crashCorrSlope = crashCorrSlope
        self.chargesOn = chargesOn; self.skewSlope = skewSlope; self.barrierShift = barrierShift
        self.corrBA = corrBA; self.volBA = volBA; self.reserveBps = reserveBps; self.ufFee = ufFee
    }

}

extension Instrument {
    /// From-scratch start: a bare funding note — single underlier, no coupon,
    /// no call, no upside, full protection. Every section is a toggle; the
    /// values below are the defaults each section reveals when switched on.
    public static let initial = Instrument(
        members: ["SPX"], basket: .worstOf,
        weights: [1, 1, 1, 1], correlation: 0.75,
        termYears: 3, averaging: .none,
        coupon: .none, couponRate: 0.10, couponObs: .quarterly,
        couponBarrier: 0.70, couponBarrierObs: .onPaymentDate, memory: false,
        call: .none, callObs: .quarterly, callTrigger: 1.0,
        triggerStep: 0, callPremium: 0, nonCallMonths: 6, snowball: false, snowballRate: 0.08,
        lockIn: false, lockLevel: 0.90,
        upside: .none, participation: 1.0, cap: nil, digital: 0.30,
        digitalStrike: 1.0, digiPlusLeverage: 1.0,
        absoluteKO: 0.80, absParticipation: 1.0,
        downside: .par, protection: 0.60, gearedBuffer: false,
        minRedemption: 0, secondChance: false, secondChanceLevel: 0.60,
        protObs: .european,
        ust3m: 0.0389, ust1y: 0.0411, ust2y: 0.0431,
        ust3y: 0.0434, ust5y: 0.0441, ust7y: 0.0453,
        spreadShort: 0.004, spreadLong: 0.006, volShift: 0,
        markVol: [:], markSpot: [:],
        localVolOn: false, localVolSlope: 0.010,
        crashCorrOn: false, crashCorrSlope: 0.05,
        chargesOn: true, skewSlope: 0.010, barrierShift: 0.01,
        corrBA: 0.03, volBA: 0.005, reserveBps: 10, ufFee: 0.025)

    /// Builder invariants: drop features the UI hides so a live lever cannot
    /// keep pricing after its control disappears.
    public mutating func applyBuilderRules() {
        if members.isEmpty { members = ["SPX"] }
        if members.count < 2 { crashCorrOn = false }
        if coupon == .none { memory = false; snowball = false }
        if call == .none { snowball = false; lockIn = false }
        if snowball { memory = false }
        if couponObs == .european { memory = false }
        let keep = Set(members)
        markVol = markVol.filter { keep.contains($0.key) }
        markSpot = markSpot.filter { keep.contains($0.key) }
    }

    /// ATM used by the Monte Carlo: typed snapshot, else catalog.
    public func atmVol(for ticker: String) -> Double {
        markVol[ticker] ?? Market.asset(ticker).vol
    }

    /// Display spot: typed snapshot, else catalog. Does not enter the SDE.
    public func displaySpot(for ticker: String) -> Double {
        markSpot[ticker] ?? Market.asset(ticker).spot
    }

    public func jsonString() -> String? {
        let enc = JSONEncoder()
        guard let data = try? enc.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func fromJSON(_ raw: String) -> Instrument? {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        guard var s = decodeInstrument(data) else { return nil }
        s.applyBuilderRules()
        return s
    }

    /// Synthesized Codable requires every key. Saved specs from before local vol
    /// / crash corr / user marks are patched with the off / empty defaults.
    static func decodeInstrument(_ data: Data) -> Instrument? {
        let dec = JSONDecoder()
        if let s = try? dec.decode(Instrument.self, from: data) { return s }
        guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var patched = false
        if obj["localVolOn"] == nil { obj["localVolOn"] = false; patched = true }
        if obj["localVolSlope"] == nil { obj["localVolSlope"] = 0.01; patched = true }
        if obj["crashCorrOn"] == nil { obj["crashCorrOn"] = false; patched = true }
        if obj["crashCorrSlope"] == nil { obj["crashCorrSlope"] = 0.05; patched = true }
        if obj["markVol"] == nil { obj["markVol"] = [:] as [String: Any]; patched = true }
        if obj["markSpot"] == nil { obj["markSpot"] = [:] as [String: Any]; patched = true }
        guard patched,
              let d2 = try? JSONSerialization.data(withJSONObject: obj),
              let s = try? dec.decode(Instrument.self, from: d2) else { return nil }
        return s
    }
}
