//  Models.swift
//  Structured Notes
//
//  Always-price philosophy: every dial is an input; the output is the note's
//  model value as a percentage of par. Build a custom basket by adding
//  underliers one at a time (worst-of or weighted). Coupon and call schedules
//  are set in their own blocks; protection and final-valuation averaging are
//  set separately.

import Foundation

public enum BasketStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case worstOf = "Worst-of"
    case weighted = "Weighted basket"
    public var id: String { rawValue }
}

/// Asian tail on the final valuation: average of daily closes over the last
/// week (5 fixings) or the last month (21 fixings).
public enum FinalAveraging: String, CaseIterable, Identifiable, Hashable, Sendable {
    case none = "Final close"
    case lastWeek = "Avg last week (5d)"
    case lastMonth = "Avg last month (21d)"
    public var id: String { rawValue }
    public var fixings: Int { self == .none ? 0 : (self == .lastWeek ? 5 : 21) }
}

public enum CouponStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case none = "No coupon"
    case guaranteed = "Guaranteed"
    case contingent = "Contingent"
    public var id: String { rawValue }
}

/// Coupon observation schedule. Daily accrues on every simulation step
/// (grid-frequency approximation of daily). European pays once at maturity.
public enum CouponObs: String, CaseIterable, Identifiable, Hashable, Sendable {
    case daily = "Daily accrual"
    case monthly = "Monthly", quarterly = "Quarterly", semiannual = "Semi-annual", annual = "Annual"
    case european = "European (at maturity)"
    public var id: String { rawValue }
    public var perYear: Int {
        switch self {
        case .daily: return 12          // accrues on the grid; documented approximation
        case .monthly: return 12
        case .quarterly: return 4
        case .semiannual: return 2
        case .annual: return 1
        case .european: return 0
        }
    }
}

/// Contingent-coupon barrier observation: standard payment-date check, or
/// daily monitoring where any breach during the period kills that coupon
/// (approximated at the simulation grid).
public enum BarrierObsStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case onPaymentDate = "On payment date"
    case dailyMonitored = "Daily (approx.)"
    public var id: String { rawValue }
}

public enum CallObs: String, CaseIterable, Identifiable, Hashable, Sendable {
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
}

public enum CallFeature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case none = "No call"
    case autocall = "Autocall"
    case issuerCall = "Issuer call"
    public var id: String { rawValue }
}

public enum ProtectionObs: String, CaseIterable, Identifiable, Hashable, Sendable {
    case european = "European (final only)"
    case quarterly = "Quarterly monitored"
    case monthly = "Monthly monitored"
    public var id: String { rawValue }
    public var perYear: Int { self == .european ? 0 : (self == .quarterly ? 4 : 12) }
}

public enum DownsideKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case par = "Full protection"
    case buffer = "Buffer (vanilla put)"
    case kiPut = "Knock-in put"
    public var id: String { rawValue }
}

public enum UpsideKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case none = "None"
    case linear = "Linear participation"
    case digital = "Digital"
    case digitalPlus = "Digi-plus"
    case absolute = "Absolute (dual directional)"
    public var id: String { rawValue }
}

public struct Instrument: Hashable, Sendable {
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
    // downside block
    public var downside: DownsideKind
    public var protection: Double
    public var gearedBuffer: Bool
    public var minRedemption: Double        // 0 = off
    public var secondChance: Bool           // Elite: a monitored knock is forgiven if the
    public var secondChanceLevel: Double    // final level recovers to at least this
    public var protObs: ProtectionObs
    // economics
    public var fundingSpread: Double
    public var volShift: Double
    // charges & reserves: bridge model mid to the dealer offer
    public var chargesOn: Bool
    public var skewSlope: Double        // vol pts per 10% moneyness on the downside wing
    public var barrierShift: Double     // client-adverse overhedge shift on discontinuities
    public var corrBA: Double           // correlation bid-ask half-width
    public var volBA: Double            // vol bid-ask, charged on |vega|
    public var reserveBps: Double       // flat model/rebalancing reserve

    public var nonCallYears: Double { nonCallMonths / 12.0 }

    public init(
        members: [String], basket: BasketStyle, weights: [Double], correlation: Double,
        termYears: Double, averaging: FinalAveraging,
        coupon: CouponStyle, couponRate: Double, couponObs: CouponObs,
        couponBarrier: Double, couponBarrierObs: BarrierObsStyle, memory: Bool,
        call: CallFeature, callObs: CallObs, callTrigger: Double, triggerStep: Double,
        nonCallMonths: Double, snowball: Bool, snowballRate: Double,
        lockIn: Bool, lockLevel: Double,
        upside: UpsideKind, participation: Double, cap: Double?, digital: Double,
        downside: DownsideKind, protection: Double, gearedBuffer: Bool,
        minRedemption: Double, secondChance: Bool, secondChanceLevel: Double,
        protObs: ProtectionObs, fundingSpread: Double, volShift: Double,
        chargesOn: Bool, skewSlope: Double, barrierShift: Double,
        corrBA: Double, volBA: Double, reserveBps: Double
    ) {
        self.members = members; self.basket = basket; self.weights = weights; self.correlation = correlation
        self.termYears = termYears; self.averaging = averaging
        self.coupon = coupon; self.couponRate = couponRate; self.couponObs = couponObs
        self.couponBarrier = couponBarrier; self.couponBarrierObs = couponBarrierObs; self.memory = memory
        self.call = call; self.callObs = callObs; self.callTrigger = callTrigger; self.triggerStep = triggerStep
        self.nonCallMonths = nonCallMonths; self.snowball = snowball; self.snowballRate = snowballRate
        self.lockIn = lockIn; self.lockLevel = lockLevel
        self.upside = upside; self.participation = participation; self.cap = cap; self.digital = digital
        self.downside = downside; self.protection = protection; self.gearedBuffer = gearedBuffer
        self.minRedemption = minRedemption; self.secondChance = secondChance; self.secondChanceLevel = secondChanceLevel
        self.protObs = protObs; self.fundingSpread = fundingSpread; self.volShift = volShift
        self.chargesOn = chargesOn; self.skewSlope = skewSlope; self.barrierShift = barrierShift
        self.corrBA = corrBA; self.volBA = volBA; self.reserveBps = reserveBps
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
        triggerStep: 0, nonCallMonths: 6, snowball: false, snowballRate: 0.08,
        lockIn: false, lockLevel: 0.90,
        upside: .none, participation: 1.0, cap: nil, digital: 0.30,
        downside: .par, protection: 0.60, gearedBuffer: false,
        minRedemption: 0, secondChance: false, secondChanceLevel: 0.60,
        protObs: .european,
        fundingSpread: 0.005, volShift: 0,
        chargesOn: true, skewSlope: 0.010, barrierShift: 0.01,
        corrBA: 0.03, volBA: 0.005, reserveBps: 10)
}
