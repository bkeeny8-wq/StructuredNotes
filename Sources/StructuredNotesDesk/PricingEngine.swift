//  PricingEngine.swift
//  Structured Notes
//
//  Always-price engine: every dial is an input; output is the note's model
//  value per $1 of par. Funding-rate discounting; risk-neutral GBM with a
//  fixed normal array (common random numbers), so leg arithmetic printed in
//  the work-through ties exactly. Coupon and call run on independent
//  schedules; protection has its own observation with a sticky knock-in; the
//  final valuation can average daily fixings over the last week or month.
//  Issuer call is rule-based — investor value shown is an upper bound
//  (optimal LSMC exercise is worth less to the holder).

import Foundation

public struct PricingResult: Equatable, Sendable {
    public var value: Double         // per $1 of par
    public var parLeg: Double
    public var couponLeg: Double     // = couponRate × qFactor
    public var upsideLeg: Double     // = participation × upUnit for linear/absolute
    public var downsideLeg: Double
    public var qFactor: Double
    public var upUnit: Double
    public var probCalled: Double
    public var probLoss: Double
    public var expectedLife: Double
    public var avgCoupons: Double

    public init(value: Double, parLeg: Double, couponLeg: Double, upsideLeg: Double, downsideLeg: Double, qFactor: Double, upUnit: Double, probCalled: Double, probLoss: Double, expectedLife: Double, avgCoupons: Double) {
        self.value = value; self.parLeg = parLeg; self.couponLeg = couponLeg
        self.upsideLeg = upsideLeg; self.downsideLeg = downsideLeg
        self.qFactor = qFactor; self.upUnit = upUnit
        self.probCalled = probCalled; self.probLoss = probLoss
        self.expectedLife = expectedLife; self.avgCoupons = avgCoupons
    }
}

public struct Sensitivities: Equatable, Sendable {
    public var mark: Double
    public var delta: Double
    public var gamma: Double
    public var vega: Double
    public var corr: Double
    public var fundingDV: Double
    public var theta1m: Double

    public init(mark: Double, delta: Double, gamma: Double, vega: Double, corr: Double, fundingDV: Double, theta1m: Double) {
        self.mark = mark; self.delta = delta; self.gamma = gamma; self.vega = vega
        self.corr = corr; self.fundingDV = fundingDV; self.theta1m = theta1m
    }
}

public struct LadderRow: Equatable, Identifiable, Sendable {
    public var id: Double { spot }
    public var spot: Double
    public var mark: Double
    public var delta: Double

    public init(spot: Double, mark: Double, delta: Double) {
        self.spot = spot; self.mark = mark; self.delta = delta
    }
}

public struct LedgerRow: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public var label: String
    public var value: Double         // % of par at this stage

    public init(label: String, value: Double) {
        self.label = label; self.value = value
    }
}

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

public enum Engine {

    public static let fullPaths = 4000
    public static let fastPaths = 1600
    public static let maxAssets = 4
    static let maxSlotsPerPath = 108   // 84 monthly steps + 21 daily fixings + slack
    static let seed: UInt64 = 20260720

    static let normals: [Double] = {
        let need = fullPaths * maxSlotsPerPath * maxAssets
        var rng = SplitMix64(state: seed)
        var out = [Double](); out.reserveCapacity(need + 2)
        while out.count < need {
            let u1 = max(rng.uniform(), 1e-12), u2 = rng.uniform()
            let m = (-2 * log(u1)).squareRoot(), a = 2 * Double.pi * u2
            out.append(m * cos(a)); out.append(m * sin(a))
        }
        return out
    }()

    static func cholesky(rho: Double, n: Int) -> [[Double]] {
        if n == 1 { return [[1]] }
        var L = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0...i {
                var s = (i == j) ? 1.0 : rho
                for k in 0..<j { s -= L[i][k] * L[j][k] }
                L[i][j] = (i == j) ? max(s, 1e-10).squareRoot() : s / L[j][j]
            }
        }
        return L
    }

    @inline(__always)
    static func perf(_ x: [Double], _ s: Instrument) -> Double {
        let n = x.count
        if n == 1 { return x[0] }
        if s.basket == .worstOf {
            var w = x[0]
            for j in 1..<n where x[j] < w { w = x[j] }
            return w
        }
        var num = 0.0, den = 0.0
        for j in 0..<n { let wj = max(s.weights[j], 1e-6); num += wj * x[j]; den += wj }
        return num / den
    }

    /// Maturity payoff on the final performance z, split into upside and loss.
    public static func components(perf z: Double, knocked: Bool, locked: Bool = false, s: Instrument) -> (up: Double, loss: Double) {
        let capV = s.cap ?? 1e9
        let alive = locked ? true
            : (s.downside == .kiPut ? !knocked : (s.downside == .par || z >= s.protection))
        var up = 0.0
        switch s.upside {
        case .none: up = 0
        case .linear: up = min(s.participation * max(z - 1, 0), max(capV - 1, 0))
        case .digital, .digitalPlus:
            let strike = s.downside == .par ? 1.0 : s.protection
            if z >= strike { up = s.upside == .digitalPlus ? max(s.digital, z - 1) : s.digital }
        case .absolute:
            if z >= 1 { up = min(s.participation * (z - 1), max(capV - 1, 0)) }
            else if alive { up = s.participation * (1 - z) }
        }
        var loss = 0.0
        switch locked ? DownsideKind.par : s.downside {
        case .par: loss = 0
        case .buffer:
            let gear = s.gearedBuffer ? 1.0 / s.protection : 1.0
            loss = min(gear * max(s.protection - z, 0), 1)
        case .kiPut:
            loss = knocked ? max(1 - z, 0) : 0
        }
        if s.minRedemption > 0 {
            loss = min(loss, max(1 + up - s.minRedemption, 0))
        }
        return (up, loss)
    }

    struct SimOut {
        var pv = 0.0, parPV = 0.0, cpnPV = 0.0, upPV = 0.0, lossPV = 0.0
        var q = 0.0, uUnit = 0.0
        var called = 0.0, loss = 0.0, life = 0.0, coupons = 0.0
    }

    static func simulate(_ s: Instrument,
                         spotScale: Double = 1, volBump: Double = 0,
                         paths: Int = fullPaths) -> SimOut {
        let assets = Market.assets(for: s.members)
        let nA = min(assets.count, maxAssets)
        let r = Market.ust
        let rf = Market.ust + s.fundingSpread
        let c = s.coupon == .none ? 0 : s.couponRate

        let couponActive = s.coupon != .none
        let callActive = s.call != .none
        let cpnPerYear = s.couponObs.perYear                 // daily→12 (grid proxy), european→0
        let callPerYear = callActive ? s.callObs.perYear : 0
        let protPerYear = s.protObs.perYear
        let fixings = s.averaging.fixings
        let dailyBarrier = s.coupon == .contingent && s.couponBarrierObs == .dailyMonitored
            && s.couponObs != .daily && s.couponObs != .european
        let stepsPerYear = max(couponActive ? cpnPerYear : 0, callPerYear, protPerYear,
                               fixings > 0 ? 12 : 0, dailyBarrier ? 12 : 0, 1)
        let nSteps = max(1, Int((s.termYears * Double(stepsPerYear)).rounded()))
        let dt = s.termYears / Double(nSteps)
        let sqdt = dt.squareRoot()
        let couponEvery = (couponActive && cpnPerYear > 0) ? max(1, stepsPerYear / cpnPerYear) : nSteps + 1
        let callEvery = callPerYear > 0 ? max(1, stepsPerYear / callPerYear) : nSteps + 1
        let protEvery = protPerYear > 0 ? max(1, stepsPerYear / protPerYear) : nSteps + 1
        let perEventAmt = s.couponObs == .daily ? c * dt : (cpnPerYear > 0 ? c / Double(cpnPerYear) : 0)
        let perEventQ = s.couponObs == .daily ? dt : (cpnPerYear > 0 ? 1.0 / Double(cpnPerYear) : 0)
        let nSubs = fixings > 0 ? 21 : 0
        let dtSub = nSubs > 0 ? dt / Double(nSubs) : 0
        let sqdtSub = dtSub > 0 ? dtSub.squareRoot() : 0

        var vols = [Double](), drifts = [Double](), driftsSub = [Double]()
        for a in assets.prefix(nA) {
            let v = max(0.01, a.vol + s.volShift + volBump)
            vols.append(v)
            drifts.append((r - a.div - v * v / 2) * dt)
            driftsSub.append((r - a.div - v * v / 2) * dtSub)
        }
        let L = cholesky(rho: min(0.99, max(-0.45, s.correlation)), n: nA)
        let z = normals

        var out = SimOut()
        var closes = [Double](repeating: 0, count: 21 * nA)
        for pth in 0..<paths {
            var x = [Double](repeating: spotScale, count: nA)
            var missed = 0
            var knocked = false
            var periodClean = true
            var locked = false
            var cpv = 0.0, parpv = 0.0, uppv = 0.0, losspv = 0.0
            var qacc = 0.0, uacc = 0.0
            let base = pth * maxSlotsPerPath * nA
            for i in 1...nSteps {
                let t = Double(i) * dt
                let isFinal = (i == nSteps)

                if isFinal && nSubs > 0 {
                    for sub in 0..<nSubs {
                        let slot = base + (nSteps - 1 + sub) * nA
                        for j in 0..<nA {
                            var e = 0.0
                            for k in 0...j { e += L[j][k] * z[slot + k] }
                            x[j] *= exp(driftsSub[j] + vols[j] * sqdtSub * e)
                            closes[sub * nA + j] = x[j]
                        }
                    }
                } else {
                    let slot = base + (i - 1) * nA
                    for j in 0..<nA {
                        var e = 0.0
                        for k in 0...j { e += L[j][k] * z[slot + k] }
                        x[j] *= exp(drifts[j] + vols[j] * sqdt * e)
                    }
                }

                var zNow = perf(x, s)
                if isFinal && nSubs > 0 {
                    var acc = [Double](repeating: 0, count: nA)
                    for f in (nSubs - fixings)..<nSubs {
                        for j in 0..<nA { acc[j] += closes[f * nA + j] }
                    }
                    for j in 0..<nA { acc[j] /= Double(fixings) }
                    zNow = perf(acc, s)
                }

                let isCouponDate = couponActive && (i % couponEvery == 0)
                let isProtDate = s.downside == .kiPut &&
                    (s.protObs == .european ? isFinal : (i % protEvery == 0 || isFinal))
                let df = exp(-rf * t)

                if isProtDate && zNow < s.protection { knocked = true }
                if dailyBarrier && zNow < s.couponBarrier { periodClean = false }
                if s.lockIn && zNow >= s.lockLevel {
                    let lockObs = (callActive && i % callEvery == 0)
                        || (couponActive && i % couponEvery == 0)
                        || (!callActive && !couponActive) || isFinal
                    if lockObs { locked = true }
                }

                if isCouponDate && !s.snowball {
                    let condition = dailyBarrier ? (periodClean && zNow >= s.couponBarrier)
                                                 : (zNow >= s.couponBarrier)
                    if s.coupon == .guaranteed {
                        cpv += perEventAmt * df; qacc += perEventQ * df; out.coupons += 1
                    } else if condition {
                        let canMemory = s.memory && s.couponObs != .daily && s.couponObs != .european
                        let n = 1 + (canMemory ? missed : 0)
                        cpv += Double(n) * perEventAmt * df
                        qacc += Double(n) * perEventQ * df
                        out.coupons += Double(n); missed = 0
                    } else { missed += 1 }
                    periodClean = true
                }
                if isFinal, couponActive, s.couponObs == .european, !s.snowball {
                    let pays = s.coupon == .guaranteed || zNow >= s.couponBarrier
                    if pays { cpv += c * s.termYears * df; qacc += s.termYears * df; out.coupons += 1 }
                }

                if !isFinal, callActive, i % callEvery == 0, t >= s.nonCallYears - 1e-9 {
                    let trig = s.callTrigger - s.triggerStep * max(0, t - s.nonCallYears)
                    if zNow >= trig {
                        parpv += df
                        if couponActive && s.snowball {
                            cpv += s.snowballRate * t * df; qacc += t * df; out.coupons += 1
                        }
                        out.called += 1; out.life += t
                        break
                    }
                }

                if isFinal {
                    if couponActive && s.snowball {
                        let pays = s.coupon == .guaranteed || zNow >= s.couponBarrier
                        if pays { cpv += s.snowballRate * t * df; qacc += t * df; out.coupons += 1 }
                    }
                    if s.downside == .kiPut, knocked, s.secondChance, zNow >= s.secondChanceLevel {
                        knocked = false
                    }
                    let (up, loss) = components(perf: zNow, knocked: knocked, locked: locked, s: s)
                    parpv += df; uppv += up * df; losspv += loss * df
                    if (s.upside == .linear || s.upside == .absolute), s.participation > 1e-9 {
                        uacc += up * df / s.participation
                    }
                    out.life += t
                    let lost = !locked && (s.downside == .buffer ? zNow < s.protection : (s.downside == .kiPut && knocked))
                    if lost { out.loss += 1 }
                }
            }
            out.cpnPV += cpv; out.parPV += parpv; out.upPV += uppv; out.lossPV += losspv
            out.q += qacc; out.uUnit += uacc
            out.pv += cpv + parpv + uppv - losspv
        }
        let n = Double(paths)
        out.pv /= n; out.parPV /= n; out.cpnPV /= n; out.upPV /= n; out.lossPV /= n
        out.q /= n; out.uUnit /= n
        out.called /= n; out.loss /= n; out.life /= n; out.coupons /= n
        return out
    }

    public static func price(_ s: Instrument, paths: Int = fullPaths) -> PricingResult {
        let o = simulate(s, paths: paths)
        return PricingResult(value: o.pv,
                             parLeg: o.parPV, couponLeg: o.cpnPV,
                             upsideLeg: o.upPV, downsideLeg: o.lossPV,
                             qFactor: o.q, upUnit: o.uUnit,
                             probCalled: o.called, probLoss: o.loss,
                             expectedLife: o.life, avgCoupons: o.coupons)
    }

    public static func sensitivities(_ s: Instrument) -> Sensitivities {
        let f: (Double, Double) -> Double = { simulate(s, spotScale: $0, volBump: $1).pv }
        let base = f(1, 0)
        let up = f(1.01, 0), dn = f(0.99, 0)
        var corr = 0.0
        if s.members.count > 1 {
            var s2 = s; s2.correlation = min(0.99, s.correlation + 0.05)
            corr = simulate(s2).pv - base
        }
        var s3 = s; s3.fundingSpread += 0.001
        let fdv = simulate(s3).pv - base
        var s4 = s; s4.termYears = max(1.0 / 12.0, s.termYears - 1.0 / 12.0)
        let theta = simulate(s4).pv - base
        return Sensitivities(mark: base, delta: (up - dn) / 0.02, gamma: up + dn - 2 * base,
                             vega: (f(1, 0.01) - f(1, -0.01)) / 2,
                             corr: corr, fundingDV: fdv, theta1m: theta)
    }

    public static func spotLadder(_ s: Instrument) -> [LadderRow] {
        [0.55, 0.65, 0.75, 0.85, 0.95, 1.0, 1.1, 1.2].map { lvl in
            let up = simulate(s, spotScale: lvl * 1.01, paths: fastPaths).pv
            let dn = simulate(s, spotScale: lvl * 0.99, paths: fastPaths).pv
            let mk = simulate(s, spotScale: lvl, paths: fastPaths).pv
            return LadderRow(spot: lvl, mark: mk, delta: (up - dn) / 0.02)
        }
    }

    /// Rebuild the instrument one feature at a time and price each stage.
    /// Deltas between rows are each feature's price in points of par.
    public static func featureLedger(_ s: Instrument) -> [LedgerRow] {
        var stages: [(String, Instrument)] = []
        var b = s
        b.members = [s.members.first ?? "SPX"]
        b.basket = .worstOf
        b.downside = .par; b.gearedBuffer = false; b.minRedemption = 0
        b.protObs = .european; b.averaging = .none
        b.call = .none; b.memory = false; b.snowball = false; b.triggerStep = 0
        b.couponBarrierObs = .onPaymentDate
        b.secondChance = false; b.lockIn = false
        b.upside = .none
        if b.coupon == .contingent { b.coupon = .guaranteed }
        let baseName = s.coupon == .none
            ? "Par bond at funding"
            : "Funding + guaranteed \(Int(round(s.couponRate * 1000)) % 10 == 0 ? String(format: "%.0f", s.couponRate * 100) : String(format: "%.1f", s.couponRate * 100))% coupon"
        stages.append((baseName, b))

        func add(_ label: String, _ mutate: (inout Instrument) -> Void) {
            var n = stages.last!.1
            mutate(&n)
            stages.append((label, n))
        }

        if s.downside != .par {
            let name = s.downside == .buffer ? (s.gearedBuffer ? "geared buffer" : "buffer") : "KI"
            add("+ downside sold (\(name) \(Int(s.protection * 100))%)") {
                $0.downside = s.downside; $0.protection = s.protection; $0.gearedBuffer = s.gearedBuffer
            }
        }
        if s.minRedemption > 0 {
            add("+ min redemption floor \(Int(s.minRedemption * 100))%") { $0.minRedemption = s.minRedemption }
        }
        if s.downside == .kiPut && s.protObs != .european {
            add("+ monitored barrier (\(s.protObs == .monthly ? "monthly" : "quarterly"))") { $0.protObs = s.protObs }
        }
        if s.downside == .kiPut && s.secondChance {
            add("+ second chance ≥\(Int(s.secondChanceLevel * 100))% (Elite)") {
                $0.secondChance = true; $0.secondChanceLevel = s.secondChanceLevel
            }
        }
        if s.members.count > 1 {
            add("+ \(s.basket == .worstOf ? "worst-of" : "weighted") basket ×\(s.members.count) (ρ \(String(format: "%.2f", s.correlation)))") {
                $0.members = s.members; $0.basket = s.basket; $0.weights = s.weights
            }
        }
        if s.averaging != .none {
            add("+ Asian tail (\(s.averaging.fixings) daily fixings)") { $0.averaging = s.averaging }
        }
        if s.upside != .none {
            add("+ \(s.upside.rawValue.lowercased()) leg") {
                $0.upside = s.upside; $0.participation = s.participation
                $0.cap = s.cap; $0.digital = s.digital
            }
        }
        if s.coupon == .contingent {
            add("+ contingent barrier \(Int(s.couponBarrier * 100))%") {
                $0.coupon = .contingent; $0.couponBarrier = s.couponBarrier
            }
        }
        if s.coupon == .contingent && s.couponBarrierObs == .dailyMonitored {
            add("+ daily-observed barrier") { $0.couponBarrierObs = .dailyMonitored }
        }
        if s.memory {
            add("+ memory") { $0.memory = true }
        }
        if s.call != .none {
            add("+ \(s.call == .autocall ? "autocall" : "issuer call (bound)")") {
                $0.call = s.call; $0.callObs = s.callObs
                $0.callTrigger = s.callTrigger; $0.nonCallMonths = s.nonCallMonths
            }
        }
        if s.call != .none && s.triggerStep > 0 {
            add("+ step-down trigger (−\(Int(s.triggerStep * 100))%/yr)") { $0.triggerStep = s.triggerStep }
        }
        if s.snowball && s.coupon != .none && s.call != .none {
            add("+ snowball \(String(format: "%.1f", s.snowballRate * 100))% accrual (pay at call)") {
                $0.snowball = true; $0.snowballRate = s.snowballRate
            }
        }
        if s.lockIn {
            add("+ lock-in ≥\(Int(s.lockLevel * 100))% (Memorizer)") {
                $0.lockIn = true; $0.lockLevel = s.lockLevel
            }
        }
        return stages.map { (label, st) in
            LedgerRow(label: label, value: simulate(st, paths: fastPaths).pv)
        }
    }
}
