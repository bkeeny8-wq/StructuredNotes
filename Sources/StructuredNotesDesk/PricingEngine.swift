//  PricingEngine.swift
//  Structured Notes
//
//  Always-price engine: every dial is an input; output is the note's model
//  value per $1 of par. Funding-rate discounting; risk-neutral GBM with a
//  fixed normal array (common random numbers), so leg arithmetic printed in
//  the work-through ties exactly. Coupon and call run on independent
//  schedules (calendar month-ends from issue; leftover stub months do not
//  pay); protection has its own observation with a sticky knock-in; the
//  final valuation can average daily fixings over the last week or month.
//  Issuer call is a small Longstaff–Schwartz step (basis 1, z, z², knocked):
//  the bank redeems when fitted continuation exceeds redemption (par +
//  premium + snowball if on). Teaching cartoon of optimal exercise, not a
//  desk LSMC. Below 40 paths the fit falls back to pathwise continuation
//  (tests); the live mark uses the four-regressor OLS. Default paths are flat vol
//  per name; an optional one-parameter leverage function (σ rises as the
//  name trades down) puts a smile in the paths so barriers can see it
//  without going through the skew charge. Not a calibrated Dupire surface.
//  Optional crash corr (default off) raises equicorrelation as the basket
//  trades down, via a per-step Cholesky. Not a desk spot/term corr surface.

import Foundation
import Dispatch

public struct CallBucket: Equatable, Identifiable, Sendable {
    public var id: String { lumped ? "later" : String(t) }
    public var t: Double
    public var p: Double
    public var lumped: Bool

    public init(t: Double, p: Double, lumped: Bool = false) {
        self.t = t; self.p = p; self.lumped = lumped
    }
}

public struct PricingResult: Equatable, Sendable {
    public var value: Double         // per $1 of par
    public var parLeg: Double
    public var couponLeg: Double     // = couponRate × qFactor
    public var premiumLeg: Double    // call premium paid at call
    public var upsideLeg: Double     // = participation × upUnit for linear/absolute
    public var downsideLeg: Double
    public var qFactor: Double
    public var upUnit: Double
    public var probCalled: Double
    public var probLoss: Double      // P(principal shortfall at maturity), not knock frequency
    public var expectedLife: Double
    public var avgCoupons: Double
    public var callDist: [CallBucket]

    public init(value: Double, parLeg: Double, couponLeg: Double, premiumLeg: Double, upsideLeg: Double, downsideLeg: Double, qFactor: Double, upUnit: Double, probCalled: Double, probLoss: Double, expectedLife: Double, avgCoupons: Double, callDist: [CallBucket]) {
        self.value = value; self.parLeg = parLeg; self.couponLeg = couponLeg; self.premiumLeg = premiumLeg
        self.upsideLeg = upsideLeg; self.downsideLeg = downsideLeg
        self.qFactor = qFactor; self.upUnit = upUnit
        self.probCalled = probCalled; self.probLoss = probLoss
        self.expectedLife = expectedLife; self.avgCoupons = avgCoupons
        self.callDist = callDist
    }
}

public struct ChargeStack: Equatable, Sendable {
    public var skew: Double
    public var overhedge: Double
    public var corrBA: Double
    public var vegaBA: Double
    public var reserve: Double
    public var total: Double
    public var offer: Double            // model mid − total, per $1 of par

    public init(skew: Double, overhedge: Double, corrBA: Double, vegaBA: Double, reserve: Double, total: Double, offer: Double) {
        self.skew = skew; self.overhedge = overhedge; self.corrBA = corrBA; self.vegaBA = vegaBA
        self.reserve = reserve; self.total = total; self.offer = offer
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

    /// Bump-stable uniforms for Brownian-bridge barrier hits.
    static let uniforms: [Double] = {
        let need = fullPaths * maxSlotsPerPath * maxAssets
        var rng = SplitMix64(state: seed &+ 0x9E3779B97F4A7C15)
        var out = [Double](); out.reserveCapacity(need)
        for _ in 0..<need { out.append(rng.uniform()) }
        return out
    }()

    /// Brownian-bridge one-touch between two closes. `flipU` uses 1−u so a
    /// coupon barrier and a KI on the same step do not share one draw.
    static func brownianHit(barrier B: Double,
                            prevX: [Double], nowX: [Double],
                            zPrev: Double, zNow: Double,
                            nA: Int, worstOf: Bool,
                            varDt: [Double], basketVarDt: Double,
                            u: [Double], u0: Int, flipU: Bool) -> Bool {
        func draw(_ j: Int) -> Double {
            let v = u[u0 + j]
            return flipU ? 1 - v : v
        }
        if worstOf || nA == 1 {
            for j in 0..<nA where prevX[j] > B && nowX[j] > B {
                let pHit = exp(-2 * log(prevX[j] / B) * log(nowX[j] / B) / varDt[j])
                if draw(j) < pHit { return true }
            }
        } else if zPrev > B && zNow > B && basketVarDt > 0 {
            let pHit = exp(-2 * log(zPrev / B) * log(zNow / B) / basketVarDt)
            if draw(0) < pHit { return true }
        }
        return false
    }

    /// Instantaneous vol for the teaching leverage function.
    /// σ(x) = σ_ATM + slope × max(1−x, 0) × 10, floored at 1 vol pt.
    /// Same units as the skew charge. Spot at or above 1 is ATM; a desk
    /// Dupire surface is calibrated to listed options and is time-dependent.
    public static func leverageVol(atm: Double, spot: Double, slope: Double) -> Double {
        let extra = slope * max(1 - spot, 0) * 10
        return max(0.01, min(atm + extra, 1.50))
    }

    /// Instantaneous equicorrelation for the teaching crash-corr spike.
    /// ρ(z) = ρ + slope × max(1−z, 0) × 10, clipped to (−0.45, 0.99).
    /// Spot at or above 1 is the pairwise lever; a desk uses a term/spot
    /// corr surface. `z` is current basket performance (worst-of or weighted).
    public static func crashRho(base: Double, basketZ: Double, slope: Double) -> Double {
        let extra = slope * max(1 - basketZ, 0) * 10
        return min(0.99, max(-0.45, base + extra))
    }

    static func weightedBasketVol(_ vols: [Double], nA: Int, weights: [Double], rho: Double) -> Double {
        var num = 0.0, den = 0.0
        for i in 0..<nA {
            let wi = max(weights[i], 1e-6); den += wi
            for j in 0..<nA {
                let wj = max(weights[j], 1e-6)
                num += wi * wj * vols[i] * vols[j] * (i == j ? 1 : rho)
            }
        }
        return num.squareRoot() / max(den, 1e-12)
    }

    /// Period variance of a weighted basket from per-name var×dt.
    static func basketVarFromVarDt(_ varDt: [Double], offset: Int, nA: Int,
                                   weights: [Double], rho: Double) -> Double {
        var num = 0.0, den = 0.0
        for i in 0..<nA {
            let wi = max(weights[i], 1e-6); den += wi
            for j in 0..<nA {
                let wj = max(weights[j], 1e-6)
                let cov = (i == j ? 1.0 : rho) * (varDt[offset + i] * varDt[offset + j]).squareRoot()
                num += wi * wj * cov
            }
        }
        let d = max(den, 1e-12)
        return num / (d * d)
    }

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

    /// 4×4 Gaussian elimination with partial pivot. Used by the issuer-call
    /// Longstaff–Schwartz ridge fit (basis 1, z, z², knocked).
    static func ge4(_ A0: [[Double]], _ b0: [Double]) -> [Double] {
        var A = A0, b = b0
        for i in 0..<4 {
            var piv = i, mag = abs(A[i][i])
            for r in (i + 1)..<4 {
                let m = abs(A[r][i])
                if m > mag { mag = m; piv = r }
            }
            if mag < 1e-18 { continue }
            if piv != i { A.swapAt(i, piv); b.swapAt(i, piv) }
            let d = A[i][i]
            for r in (i + 1)..<4 {
                let f = A[r][i] / d
                for c in i..<4 { A[r][c] -= f * A[i][c] }
                b[r] -= f * b[i]
            }
        }
        var x = [Double](repeating: 0, count: 4)
        for i in stride(from: 3, through: 0, by: -1) {
            var s = b[i]
            for c in (i + 1)..<4 { s -= A[i][c] * x[c] }
            x[i] = abs(A[i][i]) > 1e-18 ? s / A[i][i] : 0
        }
        return x
    }

    /// Risk-free zero from the instrument's editable pillars (linear, flat ends).
    public static func zeroRF(_ s: Instrument, _ t: Double) -> Double {
        let p: [(Double, Double)] = [(0.25, s.ust3m), (1, s.ust1y), (2, s.ust2y),
                                     (3, s.ust3y), (5, s.ust5y), (7, s.ust7y)]
        if t <= p[0].0 { return p[0].1 }
        for k in 1..<p.count where t <= p[k].0 {
            let (t0, r0) = p[k - 1], (t1, r1) = p[k]
            return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
        }
        return p.last!.1
    }

    /// Funding spread curve: linear between the 1y and 7y pillars, flat ends.
    public static func spread(_ s: Instrument, _ t: Double) -> Double {
        if t <= 1 { return s.spreadShort }
        if t >= 7 { return s.spreadLong }
        return s.spreadShort + (s.spreadLong - s.spreadShort) * (t - 1) / 6
    }

    public static func fundingZero(_ s: Instrument, _ t: Double) -> Double {
        zeroRF(s, t) + spread(s, t)
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
            if z >= s.digitalStrike {
                up = s.upside == .digitalPlus
                    ? max(s.digital, s.digiPlusLeverage * max(z - 1, 0))
                    : s.digital
            }
        case .absolute:
            if z >= 1 { up = min(s.participation * (z - 1), max(capV - 1, 0)) }
            else if alive && z >= s.absoluteKO { up = s.absParticipation * (1 - z) }
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
        var callSteps: [Double] = []
        var pv = 0.0, parPV = 0.0, cpnPV = 0.0, premPV = 0.0, upPV = 0.0, lossPV = 0.0
        var q = 0.0, uUnit = 0.0
        var called = 0.0, loss = 0.0, life = 0.0, coupons = 0.0
    }

    /// Issuer Bermudan: backward Longstaff–Schwartz on tapes from a no-exercise
    /// forward pass. Holder receives min(continuation, redemption). A desk LSMC
    /// uses more basis functions, more paths, and often a funding-measure
    /// regression — this is the teaching-size version of that idea.
    static func applyIssuerLS(s: Instrument, paths: Int, nSteps: Int, dt: Double,
                              dfArr: [Double], callStep: [Int], nCall: Int,
                              z: UnsafePointer<Double>, kn: UnsafePointer<Double>,
                              pfxCpn: UnsafePointer<Double>, pfxQ: UnsafePointer<Double>,
                              pfxN: UnsafePointer<Double>,
                              termCpn: UnsafePointer<Double>, termQ: UnsafePointer<Double>,
                              termN: UnsafePointer<Double>, termPar: UnsafePointer<Double>,
                              termUp: UnsafePointer<Double>, termLoss: UnsafePointer<Double>,
                              termU: UnsafePointer<Double>) -> SimOut {
        var alive = [Double](repeating: 0, count: paths)
        var exerciseK = [Int](repeating: nCall, count: paths)
        for p in 0..<paths {
            alive[p] = termCpn[p] + termPar[p] + termUp[p] - termLoss[p]
        }
        let snowball = s.snowball && s.coupon != .none
        let pathwise = paths < 40
        for k in stride(from: nCall - 1, through: 0, by: -1) {
            let i = callStep[k]
            let t = Double(i) * dt
            let df = dfArr[i]
            let R = 1.0 + s.callPremium * t + (snowball ? s.snowballRate * t : 0)
            var y = [Double](repeating: 0, count: paths)
            var A = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
            var b = [Double](repeating: 0, count: 4)
            for p in 0..<paths {
                let kept = pfxCpn[p * nCall + k]
                let contPV = alive[p] - kept
                y[p] = df > 1e-16 ? contPV / df : contPV
                if !pathwise {
                    let zp = z[p * nCall + k]
                    let r = [1.0, zp, zp * zp, kn[p * nCall + k]]
                    let yi = y[p]
                    for a in 0..<4 {
                        b[a] += r[a] * yi
                        for c in 0..<4 { A[a][c] += r[a] * r[c] }
                    }
                }
            }
            var beta = [1.0, 0.0, 0.0, 0.0]
            if !pathwise {
                for a in 0..<4 { A[a][a] += 1e-6 }
                beta = ge4(A, b)
            }
            for p in 0..<paths {
                let chat: Double
                if pathwise {
                    chat = y[p]
                } else {
                    let zp = z[p * nCall + k]
                    let r = [1.0, zp, zp * zp, kn[p * nCall + k]]
                    chat = beta[0] * r[0] + beta[1] * r[1] + beta[2] * r[2] + beta[3] * r[3]
                }
                if chat > R {
                    exerciseK[p] = k
                    alive[p] = pfxCpn[p * nCall + k] + R * df
                }
            }
        }
        var out = SimOut()
        out.callSteps = [Double](repeating: 0, count: nSteps + 1)
        let T = Double(nSteps) * dt
        for p in 0..<paths {
            if exerciseK[p] < nCall {
                let k = exerciseK[p]
                let i = callStep[k]
                let t = Double(i) * dt
                let df = dfArr[i]
                let snow = snowball ? s.snowballRate * t * df : 0
                out.cpnPV += pfxCpn[p * nCall + k] + snow
                out.q += pfxQ[p * nCall + k] + (snowball ? t * df : 0)
                out.coupons += pfxN[p * nCall + k] + (snowball ? 1 : 0)
                out.parPV += df
                out.premPV += s.callPremium * t * df
                out.called += 1
                out.life += t
                out.callSteps[i] += 1
            } else {
                out.cpnPV += termCpn[p]
                out.q += termQ[p]
                out.coupons += termN[p]
                out.parPV += termPar[p]
                out.upPV += termUp[p]
                out.lossPV += termLoss[p]
                out.uUnit += termU[p]
                out.life += T
                if termLoss[p] > 1e-12 { out.loss += 1 }
            }
        }
        let n = Double(paths)
        out.pv = (out.cpnPV + out.parPV + out.premPV + out.upPV - out.lossPV) / n
        out.parPV /= n; out.cpnPV /= n; out.premPV /= n; out.upPV /= n; out.lossPV /= n
        out.q /= n; out.uUnit /= n
        out.called /= n; out.loss /= n; out.life /= n; out.coupons /= n
        for i in 0..<out.callSteps.count { out.callSteps[i] /= n }
        return out
    }

    static func simulate(_ s: Instrument,
                         spotScale: Double = 1, volBump: Double = 0,
                         bumpAsset: Int? = nil,
                         paths: Int = fullPaths) -> SimOut {
        let assets = Market.assets(for: s.members)
        let nA = min(assets.count, maxAssets)
        let c = s.coupon == .none ? 0 : s.couponRate

        let couponActive = s.coupon != .none
        let callActive = s.call != .none
        let cpnPerYear = s.couponObs.perYear                 // european→0
        let fixings = s.averaging.fixings
        let dailyBarrier = s.coupon == .contingent && s.couponBarrierObs == .dailyMonitored
            && s.couponObs != .european
        // Month-end calendar from issue: one step per month so coupon/call/KI
        // dates land on 3m/6m/… rather than equal-spaced fractions of tenor.
        // Incomplete leftover months are not a coupon date (no stub cash).
        let termMonths = max(1, Int((s.termYears * 12.0).rounded()))
        let cpnMonths = s.couponObs.monthsPerPeriod
        let callMonths = callActive ? s.callObs.monthsPerPeriod : 0
        let protMonths = s.protObs.monthsPerPeriod
        let nSteps = termMonths
        let dt = s.termYears / Double(nSteps)
        let sqdt = dt.squareRoot()
        let perEventAmt = cpnPerYear > 0 ? c / Double(cpnPerYear) : 0
        let perEventQ = cpnPerYear > 0 ? 1.0 / Double(cpnPerYear) : 0
        let nSubs = fixings > 0 ? 21 : 0
        let dtSub = nSubs > 0 ? dt / Double(nSubs) : 0
        let sqdtSub = dtSub > 0 ? dtSub.squareRoot() : 0

        var vols = [Double](), qv = [Double](), qvSub = [Double](), divsArr = [Double]()
        // per-asset step multipliers, hoisted out of the path/step loops
        var volSqdt = [Double](), volSqdtSub = [Double](), varDt = [Double](), varDtSub = [Double]()
        for (j, a) in assets.prefix(nA).enumerated() {
            let applies = bumpAsset == nil || bumpAsset == j
            let atm = s.atmVol(for: a.ticker)
            let v = max(0.01, atm + s.volShift + (applies ? volBump : 0))
            vols.append(v); divsArr.append(a.div)
            qv.append((a.div + v * v / 2) * dt)
            qvSub.append((a.div + v * v / 2) * dtSub)
            volSqdt.append(v * sqdt)
            volSqdtSub.append(v * sqdtSub)
            varDt.append(v * v * dt)
            varDtSub.append(v * v * dtSub)
        }
        // discount factors at step dates off the funding curve; risk-free
        // forwards between steps drive the drift
        var dfArr = [Double](repeating: 1, count: nSteps + 1)
        var fwdDt = [Double](repeating: 0, count: nSteps + 1)
        var prevZT = 0.0
        for i in 1...nSteps {
            let t = Double(i) * dt
            dfArr[i] = exp(-fundingZero(s, t) * t)
            let zT = zeroRF(s, t) * t
            fwdDt[i] = zT - prevZT
            prevZT = zT
        }
        let L = cholesky(rho: min(0.99, max(-0.45, s.correlation)), n: nA)
        let z = normals
        let u = uniforms
        let kiBridge = s.downside == .kiPut && s.protObs == .daily
        let cpnBridge = dailyBarrier
        let watchBridge = kiBridge || cpnBridge
        let worstOf = s.basket == .worstOf || nA == 1
        let localOn = s.localVolOn
        let lvSlope = s.localVolSlope
        let rhoUse = min(0.99, max(-0.45, s.correlation))
        let crashOn = s.crashCorrOn && nA > 1
        let crashSlope = s.crashCorrSlope
        var basketVol = 0.0
        if watchBridge && nA > 1 && s.basket == .weighted && !localOn && !crashOn {
            basketVol = weightedBasketVol(vols, nA: nA, weights: s.weights, rho: rhoUse)
        }

        let issuerLS = s.call == .issuerCall
        var callStepList: [Int] = []
        if issuerLS, callMonths > 0 {
            for i in 1..<nSteps {
                let t = Double(i) * dt
                if i % callMonths == 0, t >= s.nonCallYears - 1e-9 {
                    callStepList.append(i)
                }
            }
        }
        let nCall = callStepList.count
        let runLS = issuerLS && nCall > 0
        let zTape: UnsafeMutablePointer<Double>?
        let knTape: UnsafeMutablePointer<Double>?
        let pfxCpnTape: UnsafeMutablePointer<Double>?
        let pfxQTape: UnsafeMutablePointer<Double>?
        let pfxNTape: UnsafeMutablePointer<Double>?
        let termCpnTape: UnsafeMutablePointer<Double>?
        let termQTape: UnsafeMutablePointer<Double>?
        let termNTape: UnsafeMutablePointer<Double>?
        let termParTape: UnsafeMutablePointer<Double>?
        let termUpTape: UnsafeMutablePointer<Double>?
        let termLossTape: UnsafeMutablePointer<Double>?
        let termUTape: UnsafeMutablePointer<Double>?
        if runLS {
            let callCap = paths * nCall
            func zeros(_ n: Int) -> UnsafeMutablePointer<Double> {
                let p = UnsafeMutablePointer<Double>.allocate(capacity: n)
                p.initialize(repeating: 0, count: n)
                return p
            }
            zTape = zeros(callCap); knTape = zeros(callCap)
            pfxCpnTape = zeros(callCap); pfxQTape = zeros(callCap); pfxNTape = zeros(callCap)
            termCpnTape = zeros(paths); termQTape = zeros(paths); termNTape = zeros(paths)
            termParTape = zeros(paths); termUpTape = zeros(paths)
            termLossTape = zeros(paths); termUTape = zeros(paths)
        } else {
            zTape = nil; knTape = nil
            pfxCpnTape = nil; pfxQTape = nil; pfxNTape = nil
            termCpnTape = nil; termQTape = nil; termNTape = nil
            termParTape = nil; termUpTape = nil
            termLossTape = nil; termUTape = nil
        }
        defer {
            func free(_ p: UnsafeMutablePointer<Double>?, _ n: Int) {
                guard let p, n > 0 else { return }
                p.deinitialize(count: n)
                p.deallocate()
            }
            free(zTape, paths * nCall); free(knTape, paths * nCall)
            free(pfxCpnTape, paths * nCall); free(pfxQTape, paths * nCall); free(pfxNTape, paths * nCall)
            free(termCpnTape, paths); free(termQTape, paths); free(termNTape, paths)
            free(termParTape, paths); free(termUpTape, paths)
            free(termLossTape, paths); free(termUTape, paths)
        }

        var out = SimOut()
        out.callSteps = [Double](repeating: 0, count: nSteps + 1)
        let chunkCount = paths >= 512 ? 8 : 1
        var partials = [SimOut](repeating: out, count: chunkCount)
        partials.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                var out = SimOut()
                out.callSteps = [Double](repeating: 0, count: nSteps + 1)
                var closes = [Double](repeating: 0, count: 21 * nA)
                // path working buffers, allocated once per chunk and reset per path
                var x = [Double](repeating: 1, count: nA)
                var xPrev = [Double](repeating: 1, count: nA)
                var acc = [Double](repeating: 0, count: nA)
                var varDtNow = [Double](repeating: 0, count: nA)
                var subVarDt = [Double](repeating: 0, count: 21 * nA)
                var vdtSubNow = [Double](repeating: 0, count: nA)
                var subRho = [Double](repeating: rhoUse, count: 21)
                let lo = paths * chunk / chunkCount
                let hi = paths * (chunk + 1) / chunkCount
                for pth in lo..<hi {
            if let b = bumpAsset {
                for j in 0..<nA { x[j] = 1 }
                if b < nA { x[b] = spotScale }
            } else {
                for j in 0..<nA { x[j] = spotScale }
            }
            var missed = 0
            var knocked = false
            var periodClean = true
            var locked = false
            var cpv = 0.0, parpv = 0.0, prempv = 0.0, uppv = 0.0, losspv = 0.0
            var qacc = 0.0, uacc = 0.0, ncpn = 0.0
            var callK = 0
            for j in 0..<nA { xPrev[j] = x[j] }
            var zPrev = perf(x, s)
            let base = pth * maxSlotsPerPath * nA
            for i in 1...nSteps {
                let t = Double(i) * dt
                let isFinal = (i == nSteps)

                if isFinal && nSubs > 0 {
                    let fwdSub = fwdDt[i] / Double(nSubs)
                    for sub in 0..<nSubs {
                        var Lsub = L
                        var rhoSub = rhoUse
                        if crashOn {
                            rhoSub = crashRho(base: rhoUse, basketZ: perf(x, s), slope: crashSlope)
                            Lsub = cholesky(rho: rhoSub, n: nA)
                        }
                        subRho[sub] = rhoSub
                        let slot = base + (nSteps - 1 + sub) * nA
                        for j in 0..<nA {
                            var e = 0.0
                            for k in 0...j { e += Lsub[j][k] * z[slot + k] }
                            if localOn {
                                let v = leverageVol(atm: vols[j], spot: x[j], slope: lvSlope)
                                let v2 = v * v
                                x[j] *= exp(fwdSub - (divsArr[j] + v2 / 2) * dtSub + v * sqdtSub * e)
                                subVarDt[sub * nA + j] = v2 * dtSub
                            } else {
                                x[j] *= exp(fwdSub - qvSub[j] + volSqdtSub[j] * e)
                            }
                            closes[sub * nA + j] = x[j]
                        }
                    }
                } else {
                    var Lstep = L
                    var rhoStep = rhoUse
                    if crashOn {
                        rhoStep = crashRho(base: rhoUse, basketZ: perf(x, s), slope: crashSlope)
                        Lstep = cholesky(rho: rhoStep, n: nA)
                    }
                    let slot = base + (i - 1) * nA
                    for j in 0..<nA {
                        var e = 0.0
                        for k in 0...j { e += Lstep[j][k] * z[slot + k] }
                        if localOn {
                            let v = leverageVol(atm: vols[j], spot: x[j], slope: lvSlope)
                            let v2 = v * v
                            x[j] *= exp(fwdDt[i] - (divsArr[j] + v2 / 2) * dt + v * sqdt * e)
                            varDtNow[j] = v2 * dt
                        } else {
                            x[j] *= exp(fwdDt[i] - qv[j] + volSqdt[j] * e)
                        }
                    }
                    // Stash this step's ρ on index 0 so the bridge below can read it.
                    subRho[0] = rhoStep
                }

                var zNow = perf(x, s)
                if isFinal && nSubs > 0 {
                    // Asian tail averages the *final level*. Only daily KI
                    // (and coupon daily-monitor) should walk the 21 closes;
                    // monthly/quarterly still knock on the month-end close.
                    let watchDailyKI = s.downside == .kiPut && s.protObs == .daily
                    if watchDailyKI || dailyBarrier {
                        var prevX = xPrev
                        var prevZ = zPrev
                        for sub in 0..<nSubs {
                            var day = [Double](repeating: 0, count: nA)
                            for j in 0..<nA { day[j] = closes[sub * nA + j] }
                            let zDay = perf(day, s)
                            if watchDailyKI && zDay < s.protection { knocked = true }
                            let u0 = base + (nSteps - 1 + sub) * nA
                            if localOn {
                                for j in 0..<nA { vdtSubNow[j] = subVarDt[sub * nA + j] }
                            }
                            let vdtSubUse = localOn ? vdtSubNow : varDtSub
                            let rhoSub = subRho[sub]
                            let bvarSub: Double = {
                                guard nA > 1 && s.basket == .weighted else {
                                    return basketVol * basketVol * dtSub
                                }
                                if localOn {
                                    return basketVarFromVarDt(subVarDt, offset: sub * nA, nA: nA,
                                                              weights: s.weights, rho: rhoSub)
                                }
                                if crashOn {
                                    let bv = weightedBasketVol(vols, nA: nA, weights: s.weights, rho: rhoSub)
                                    return bv * bv * dtSub
                                }
                                return basketVol * basketVol * dtSub
                            }()
                            if watchDailyKI && kiBridge && !knocked {
                                if brownianHit(barrier: s.protection, prevX: prevX, nowX: day,
                                               zPrev: prevZ, zNow: zDay, nA: nA, worstOf: worstOf,
                                               varDt: vdtSubUse, basketVarDt: bvarSub,
                                               u: u, u0: u0, flipU: false) {
                                    knocked = true
                                }
                            }
                            if cpnBridge && periodClean {
                                if zDay < s.couponBarrier {
                                    periodClean = false
                                } else if brownianHit(barrier: s.couponBarrier, prevX: prevX, nowX: day,
                                                      zPrev: prevZ, zNow: zDay, nA: nA, worstOf: worstOf,
                                                      varDt: vdtSubUse, basketVarDt: bvarSub,
                                                      u: u, u0: u0, flipU: true) {
                                    periodClean = false
                                }
                            }
                            prevX = day
                            prevZ = zDay
                        }
                    }
                    for j in 0..<nA { acc[j] = 0 }
                    for f in (nSubs - fixings)..<nSubs {
                        for j in 0..<nA { acc[j] += closes[f * nA + j] }
                    }
                    for j in 0..<nA { acc[j] /= Double(fixings) }
                    zNow = perf(acc, s)
                }

                let isCouponDate = couponActive && cpnMonths > 0 && (i % cpnMonths == 0)
                let isProtDate = s.downside == .kiPut &&
                    (s.protObs == .european ? isFinal : (protMonths == 0 ? isFinal : (i % protMonths == 0 || isFinal)))
                let df = dfArr[i]

                if isFinal && nSubs > 0 {
                    if s.downside == .kiPut {
                        if s.protObs == .european {
                            if zNow < s.protection { knocked = true }
                        } else if s.protObs != .daily, isProtDate, perf(x, s) < s.protection {
                            // Month-end close of the averaging window, not the average.
                            knocked = true
                        }
                    }
                } else {
                    if isProtDate && zNow < s.protection { knocked = true }
                    let u0 = base + (i - 1) * nA
                    let vdtUse = localOn ? varDtNow : varDt
                    let rhoBridge = subRho[0]
                    let bvarUse: Double = {
                        guard nA > 1 && s.basket == .weighted else {
                            return basketVol * basketVol * dt
                        }
                        if localOn {
                            return basketVarFromVarDt(varDtNow, offset: 0, nA: nA,
                                                      weights: s.weights, rho: rhoBridge)
                        }
                        if crashOn {
                            let bv = weightedBasketVol(vols, nA: nA, weights: s.weights, rho: rhoBridge)
                            return bv * bv * dt
                        }
                        return basketVol * basketVol * dt
                    }()
                    if kiBridge && !knocked {
                        if brownianHit(barrier: s.protection, prevX: xPrev, nowX: x,
                                       zPrev: zPrev, zNow: zNow, nA: nA, worstOf: worstOf,
                                       varDt: vdtUse, basketVarDt: bvarUse,
                                       u: u, u0: u0, flipU: false) {
                            knocked = true
                        }
                    }
                    if cpnBridge && periodClean {
                        if zNow < s.couponBarrier {
                            periodClean = false
                        } else if brownianHit(barrier: s.couponBarrier, prevX: xPrev, nowX: x,
                                              zPrev: zPrev, zNow: zNow, nA: nA, worstOf: worstOf,
                                              varDt: vdtUse, basketVarDt: bvarUse,
                                              u: u, u0: u0, flipU: true) {
                            periodClean = false
                        }
                    }
                }
                if watchBridge { for j in 0..<nA { xPrev[j] = x[j] }; zPrev = zNow }
                if s.lockIn && zNow >= s.lockLevel {
                    let lockObs = (callActive && callMonths > 0 && i % callMonths == 0)
                        || (couponActive && cpnMonths > 0 && i % cpnMonths == 0)
                        || (!callActive && !couponActive) || isFinal
                    if lockObs { locked = true }
                }

                if isCouponDate && !s.snowball {
                    let condition = dailyBarrier ? (periodClean && zNow >= s.couponBarrier)
                                                 : (zNow >= s.couponBarrier)
                    if s.coupon == .guaranteed {
                        cpv += perEventAmt * df; qacc += perEventQ * df; ncpn += 1
                    } else if condition {
                        let canMemory = s.memory && s.couponObs != .european
                        let n = 1 + (canMemory ? missed : 0)
                        cpv += Double(n) * perEventAmt * df
                        qacc += Double(n) * perEventQ * df
                        ncpn += Double(n); missed = 0
                    } else { missed += 1 }
                    // Next period starts dirty if this payment-date close is
                    // already through the barrier (the close is the start of
                    // the next watch window under daily monitoring).
                    periodClean = !dailyBarrier || zNow >= s.couponBarrier
                }
                if isFinal, couponActive, s.couponObs == .european, !s.snowball {
                    let pays = s.coupon == .guaranteed || zNow >= s.couponBarrier
                    if pays { cpv += c * s.termYears * df; qacc += s.termYears * df; ncpn += 1 }
                }

                if !isFinal, callActive, callMonths > 0, i % callMonths == 0, t >= s.nonCallYears - 1e-9 {
                    if runLS {
                        if callK < nCall {
                            let o = pth * nCall + callK
                            zTape![o] = zNow
                            knTape![o] = knocked ? 1 : 0
                            pfxCpnTape![o] = cpv
                            pfxQTape![o] = qacc
                            pfxNTape![o] = ncpn
                            callK += 1
                        }
                    } else {
                        let trig = s.callTrigger - s.triggerStep * max(0, t - s.nonCallYears)
                        if zNow >= trig {
                            parpv += df
                            prempv += s.callPremium * t * df
                            if couponActive && s.snowball {
                                cpv += s.snowballRate * t * df; qacc += t * df; ncpn += 1
                            }
                            out.called += 1; out.life += t
                            out.callSteps[i] += 1
                            break
                        }
                    }
                }

                if isFinal {
                    if couponActive && s.snowball {
                        let pays = s.coupon == .guaranteed || zNow >= s.couponBarrier
                        if pays { cpv += s.snowballRate * t * df; qacc += t * df; ncpn += 1 }
                    }
                    if s.downside == .kiPut, knocked, s.secondChance, zNow >= s.secondChanceLevel {
                        knocked = false
                    }
                    let (up, loss) = components(perf: zNow, knocked: knocked, locked: locked, s: s)
                    parpv += df; uppv += up * df; losspv += loss * df
                    if (s.upside == .linear || s.upside == .absolute), s.participation > 1e-9 {
                        uacc += up * df / s.participation
                    }
                    if !runLS {
                        out.life += t
                        // Principal loss, not knock: a monitored KI that recovers through
                        // par has knocked = true but loss = 0.
                        if loss > 1e-12 { out.loss += 1 }
                    }
                }
            }
            if runLS {
                termCpnTape![pth] = cpv
                termQTape![pth] = qacc
                termNTape![pth] = ncpn
                termParTape![pth] = parpv
                termUpTape![pth] = uppv
                termLossTape![pth] = losspv
                termUTape![pth] = uacc
            } else {
                out.cpnPV += cpv; out.parPV += parpv; out.premPV += prempv
                out.upPV += uppv; out.lossPV += losspv
                out.q += qacc; out.uUnit += uacc
                out.pv += cpv + parpv + prempv + uppv - losspv
                out.coupons += ncpn
            }
        }
                buf[chunk] = out
            }
        }
        if runLS,
           let zTape, let knTape, let pfxCpnTape, let pfxQTape, let pfxNTape,
           let termCpnTape, let termQTape, let termNTape, let termParTape,
           let termUpTape, let termLossTape, let termUTape {
            return applyIssuerLS(s: s, paths: paths, nSteps: nSteps, dt: dt,
                                 dfArr: dfArr, callStep: callStepList, nCall: nCall,
                                 z: zTape, kn: knTape, pfxCpn: pfxCpnTape, pfxQ: pfxQTape,
                                 pfxN: pfxNTape, termCpn: termCpnTape, termQ: termQTape,
                                 termN: termNTape, termPar: termParTape, termUp: termUpTape,
                                 termLoss: termLossTape, termU: termUTape)
        }
        for p in partials {
            out.pv += p.pv; out.parPV += p.parPV; out.cpnPV += p.cpnPV
            out.premPV += p.premPV; out.upPV += p.upPV; out.lossPV += p.lossPV
            out.q += p.q; out.uUnit += p.uUnit
            out.called += p.called; out.loss += p.loss
            out.life += p.life; out.coupons += p.coupons
            for i in 0..<out.callSteps.count { out.callSteps[i] += p.callSteps[i] }
        }
        let n = Double(paths)
        out.pv /= n; out.parPV /= n; out.cpnPV /= n; out.premPV /= n; out.upPV /= n; out.lossPV /= n
        out.q /= n; out.uUnit /= n
        out.called /= n; out.loss /= n; out.life /= n; out.coupons /= n
        for i in 0..<out.callSteps.count { out.callSteps[i] /= n }
        return out
    }

    public static func price(_ s: Instrument, paths: Int = fullPaths) -> PricingResult {
        let o = simulate(s, paths: paths)
        return PricingResult(value: o.pv,
                             parLeg: o.parPV, couponLeg: o.cpnPV, premiumLeg: o.premPV,
                             upsideLeg: o.upPV, downsideLeg: o.lossPV,
                             qFactor: o.q, upUnit: o.uUnit,
                             probCalled: o.called, probLoss: o.loss,
                             expectedLife: o.life, avgCoupons: o.coupons,
                             callDist: {
                                 let dt = s.termYears / Double(max(o.callSteps.count - 1, 1))
                                 let raw = o.callSteps.enumerated().compactMap { (i, p) -> CallBucket? in
                                     p > 0.002 ? CallBucket(t: Double(i) * dt, p: p) : nil
                                 }
                                 if raw.count <= 5 { return raw }
                                 let head = Array(raw.prefix(4))
                                 let tail = raw.dropFirst(4).reduce(0) { $0 + $1.p }
                                 return head + [CallBucket(t: raw[4].t, p: tail, lumped: true)]
                             }())
    }

    /// Coupon (or snowball rate) that prints the displayed quote at par.
    /// Mid is linear in the rate via Q when call timing does not depend on the
    /// coupon (bullet / autocall, charges off): one shot is exact. Issuer LS
    /// exercise *does* depend on the coupon — Q changes at the call boundary —
    /// so that case (and charges-on) uses a bracketed Illinois root finder on
    /// quote(c) − 1 = 0 rather than a fixed number of Q-style iterates.
    public static func couponForPar(_ s: Instrument, paths: Int = fastPaths) -> Double? {
        guard s.coupon != .none else { return nil }

        func quoted(_ c: Double) -> Double? {
            var t = s
            let x = min(max(c, 0), 0.25)
            if t.snowball { t.snowballRate = x } else { t.couponRate = x }
            let r = price(t, paths: paths)
            guard r.qFactor > 1e-8 else { return nil }
            if t.chargesOn {
                let g = sensitivities(t, mark: r.value)
                let ch = charges(t, midValue: r.value, vega: g.vega)
                return ch.offer
            }
            return r.value
        }

        let nonlinear = s.call == .issuerCall || s.chargesOn
        if !nonlinear {
            let r = price(s, paths: paths)
            guard r.qFactor > 1e-8 else { return nil }
            let cur = s.snowball ? s.snowballRate : s.couponRate
            let other = r.value - cur * r.qFactor
            let solved = (1.0 - other) / r.qFactor
            guard solved.isFinite else { return nil }
            return min(max(solved, 0), 0.25)
        }

        guard let vLo = quoted(0), let vHi = quoted(0.25) else { return nil }
        let ftol = 1e-7
        if abs(vLo - 1) <= ftol { return 0 }
        if abs(vHi - 1) <= ftol { return 0.25 }
        if vLo > 1 { return 0 }
        if vHi < 1 { return 0.25 }
        return illinoisRoot(lo: 0, hi: 0.25, flo: vLo - 1, fhi: vHi - 1, ftol: ftol) { c in
            quoted(c).map { $0 - 1 }
        }
    }

    /// Illinois regula falsi on a sign-changing bracket. Falls back to
    /// bisection when the interpolated point leaves (lo, hi).
    static func illinoisRoot(lo: Double, hi: Double, flo: Double, fhi: Double,
                             ftol: Double, xtol: Double = 1e-8, maxIter: Int = 28,
                             f: (Double) -> Double?) -> Double? {
        var a = lo, b = hi, fa = flo, fb = fhi
        var lastSide = 0
        for _ in 0..<maxIter {
            if abs(fb - fa) < 1e-18 { break }
            var x = (a * fb - b * fa) / (fb - fa)
            if x <= a || x >= b { x = 0.5 * (a + b) }
            guard let fx = f(x) else { return nil }
            if abs(fx) <= ftol || (b - a) <= xtol { return min(max(x, 0), 0.25) }
            if fx > 0 {
                b = x; fb = fx
                if lastSide > 0 { fa *= 0.5 }
                lastSide = 1
            } else {
                a = x; fa = fx
                if lastSide < 0 { fb *= 0.5 }
                lastSide = -1
            }
        }
        return min(max(abs(fa) < abs(fb) ? a : b, 0), 0.25)
    }

    public struct AssetRisk: Equatable, Identifiable, Sendable {
        public var id: String { ticker }
        public var ticker: String
        public var delta: Double     // per 1% move in this name alone, $/par
        public var vega: Double      // per 1 vol pt in this name alone
    
        public init(ticker: String, delta: Double, vega: Double) {
            self.ticker = ticker; self.delta = delta; self.vega = vega
        }
}

    /// Bump each member alone, the others held flat — the hedge sheet.
    public static func perAssetRisk(_ s: Instrument) -> [AssetRisk] {
        s.members.enumerated().map { (j, tkr) in
            let dU = simulate(s, spotScale: 1.01, bumpAsset: j, paths: fastPaths).pv
            let dD = simulate(s, spotScale: 0.99, bumpAsset: j, paths: fastPaths).pv
            let vU = simulate(s, volBump: 0.01, bumpAsset: j, paths: fastPaths).pv
            let vD = simulate(s, volBump: -0.01, bumpAsset: j, paths: fastPaths).pv
            return AssetRisk(ticker: tkr, delta: (dU - dD) / 0.02, vega: (vU - vD) / 2)
        }
    }

    /// Greeks from fast-path CRN diffs; the headline mark (full paths) is
    /// passed in so the displayed level and the diffs never disagree.
    public static func sensitivities(_ s: Instrument, mark: Double) -> Sensitivities {
        let f: (Double, Double) -> Double = { simulate(s, spotScale: $0, volBump: $1, paths: fastPaths).pv }
        let base = f(1, 0)
        let up = f(1.01, 0), dn = f(0.99, 0)
        var corr = 0.0
        if s.members.count > 1 {
            var s2 = s; s2.correlation = min(0.99, s.correlation + 0.05)
            corr = simulate(s2, paths: fastPaths).pv - base
        }
        var s3 = s; s3.spreadShort += 0.001; s3.spreadLong += 0.001
        let fdv = simulate(s3, paths: fastPaths).pv - base
        // A 1-month note cannot roll a further month (the max(1/12, T−1/12)
        // clamp is a no-op). Age a week instead so pull-to-par still shows.
        let month = 1.0 / 12.0
        let thetaBump = s.termYears > month + 1e-9 ? month : min(s.termYears * 0.5, 7.0 / 365.0)
        var s4 = s; s4.termYears = max(1.0 / 365.0, s.termYears - thetaBump)
        let theta = simulate(s4, paths: fastPaths).pv - base
        return Sensitivities(mark: mark, delta: (up - dn) / 0.02, gamma: up + dn - 2 * base,
                             vega: (f(1, 0.01) - f(1, -0.01)) / 2,
                             corr: corr, fundingDV: fdv, theta1m: theta)
    }

    /// Trading charges: the bridge from model mid to the dealer offer.
    /// Skew is leg-isolated (the downside leg repriced at its strike vol);
    /// overhedge shifts every discontinuity against the client; correlation
    /// takes the adverse side of a ±Δρ band; vega bid-ask charges |vega|;
    /// rebalancing/gap/model risk sit in the flat reserve. All diffs use the
    /// same normal array (CRN), so they are clean of sampling noise.
    public static func charges(_ s: Instrument, midValue: Double, vega: Double) -> ChargeStack {
        guard s.chargesOn else {
            return ChargeStack(skew: 0, overhedge: 0, corrBA: 0, vegaBA: 0,
                               reserve: 0, total: 0, offer: midValue)
        }
        let baseF = simulate(s, paths: fastPaths)
        var skew = 0.0
        // Local vol already puts the smile in the paths; charging skew on top
        // would double-count. Flat-vol mids still use the strike-vol charge.
        if s.downside != .par && !s.localVolOn {
            let extra = s.skewSlope * (1 - s.protection) * 10
            let wing = simulate(s, volBump: extra, paths: fastPaths)
            skew = max(wing.lossPV - baseF.lossPV, 0)
        }
        var s2 = s
        if s2.downside != .par { s2.protection = min(0.99, s2.protection + s.barrierShift) }
        if s2.coupon == .contingent { s2.couponBarrier = min(1.1, s2.couponBarrier + s.barrierShift) }
        if s2.lockIn { s2.lockLevel += s.barrierShift }
        if s2.secondChance { s2.secondChanceLevel += s.barrierShift }
        if s2.upside == .digital || s2.upside == .digitalPlus { s2.digitalStrike += s.barrierShift }
        if s2.upside == .absolute { s2.absoluteKO += s.barrierShift }
        let over = max(baseF.pv - simulate(s2, paths: fastPaths).pv, 0)
        var corr = 0.0
        if s.members.count > 1 {
            var lo = s, hi = s
            lo.correlation = max(0.0, s.correlation - s.corrBA)
            hi.correlation = min(0.99, s.correlation + s.corrBA)
            let adverse = min(simulate(lo, paths: fastPaths).pv, simulate(hi, paths: fastPaths).pv)
            corr = max(baseF.pv - adverse, 0)
        }
        let vba = abs(vega) * s.volBA * 100
        let res = s.reserveBps / 10000
        let total = skew + over + corr + vba + res
        return ChargeStack(skew: skew, overhedge: over, corrBA: corr, vegaBA: vba,
                           reserve: res, total: total, offer: midValue - total)
    }

    public static func spotLadder(_ s: Instrument) -> [LadderRow] {
        [0.55, 0.65, 0.75, 0.85, 0.95, 1.0, 1.1, 1.2].map { lvl in
            let mk = simulate(s, spotScale: lvl, paths: fastPaths).pv
            let up = simulate(s, spotScale: lvl * 1.01, paths: fastPaths).pv
            return LadderRow(spot: lvl, mark: mk, delta: (up - mk) / 0.01)
        }
    }

    public struct ScenarioRow: Equatable, Identifiable, Sendable {
        public var id: Double { spot }
        public var spot: Double
        public var mark: Double
        public var delta: Double
    
        public init(spot: Double, mark: Double, delta: Double) {
            self.spot = spot; self.mark = mark; self.delta = delta
        }
}
    public struct EventBlock: Equatable, Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var rows: [ScenarioRow]
        public var caption: String
    
        public init(title: String, rows: [ScenarioRow], caption: String) {
            self.title = title; self.rows = rows; self.caption = caption
        }
}

    /// Roll the clock to the note's discontinuities and tabulate value and
    /// delta across spots bracketing the level — pin risk when it matters.
    public static func eventScenarios(_ s: Instrument) -> [EventBlock] {
        var out: [EventBlock] = []
        func block(_ s2: Instrument, level: Double, title: String, caption: String) {
            let rows = [level - 0.04, level - 0.015, level, level + 0.015, level + 0.04].map { lvl -> ScenarioRow in
                let mk = simulate(s2, spotScale: lvl, paths: fastPaths).pv
                let up = simulate(s2, spotScale: lvl * 1.01, paths: fastPaths).pv
                return ScenarioRow(spot: lvl, mark: mk, delta: (up - mk) / 0.01)
            }
            out.append(EventBlock(title: title, rows: rows, caption: caption))
        }
        // Do not reuse a freshly issued remaining-life note: the engine's first
        // call check is one period after t=0, so that would land the chart a
        // period late and never redeem spots already through the trigger.
        if s.call != .none, let firstM = firstCallMonth(s) {
            let tFirst = Double(firstM) / 12.0
            var s2 = s
            s2.termYears = max(1.0 / 12.0, s.termYears - tFirst)
            s2.nonCallMonths = 0
            let calledValue = 1.0
                + s.callPremium * tFirst
                + ((s.coupon != .none && s.snowball) ? s.snowballRate * tFirst : 0)
            if s.call == .issuerCall {
                func valueAt(_ lvl: Double) -> Double {
                    let cont = simulate(s2, spotScale: lvl, paths: fastPaths).pv
                    return min(cont, calledValue)
                }
                let rows = [0.96, 0.985, 1.0, 1.015, 1.04].map { lvl -> ScenarioRow in
                    let mk = valueAt(lvl)
                    let up = valueAt(lvl * 1.01)
                    return ScenarioRow(spot: lvl, mark: mk, delta: (up - mk) / 0.01)
                }
                out.append(EventBlock(
                    title: "At the first call observation · issuer exercise vs redemption",
                    rows: rows,
                    caption: "On this date the issuer compares continuation of the remaining life to redemption (par plus any call premium, plus snowball if it is on). The model calls when a small LS fit says continuation is richer — min(C, R), not a 100% trigger. Four regressors, same paths as the mark; not a desk LSMC."))
            } else {
                let trigger = s.callTrigger
                func valueAt(_ lvl: Double) -> Double {
                    if lvl >= trigger - 1e-12 { return calledValue }
                    return simulate(s2, spotScale: lvl, paths: fastPaths).pv
                }
                let rows = [trigger - 0.04, trigger - 0.015, trigger,
                            trigger + 0.015, trigger + 0.04].map { lvl -> ScenarioRow in
                    let mk = valueAt(lvl)
                    let up = valueAt(lvl * 1.01)
                    return ScenarioRow(spot: lvl, mark: mk, delta: (up - mk) / 0.01)
                }
                out.append(EventBlock(
                    title: "At the first call observation · spot around the \(Int(s.callTrigger * 100))% trigger",
                    rows: rows,
                    caption: "This is the observation date itself: at or above the trigger the note is already par (plus any call premium). Below it, the remaining life continues. Delta flips through the trigger."))
            }
        }
        if s.downside == .kiPut {
            var s3 = s
            s3.termYears = 1.0 / 12.0
            s3.nonCallMonths = 24
            s3.call = .none
            s3.coupon = .none
            s3.snowball = false
            block(s3, level: s.protection,
                  title: "One month to maturity · spot around the \(Int(s.protection * 100))% KI",
                  caption: "The cliff: delta concentrates just above the barrier and dies below it — the hardest month in the book. Coupons and calls are stripped here so the barrier is the only discontinuity.")
        }
        return out
    }

    /// First call-observation month from issue, or nil if none falls before maturity.
    /// Mirrors `simulate`: call dates are calendar month-ends, never the final step.
    public static func firstCallMonth(_ s: Instrument) -> Int? {
        guard s.call != .none else { return nil }
        let termMonths = max(1, Int((s.termYears * 12.0).rounded()))
        let step = s.callObs.monthsPerPeriod
        let lockout = Int(s.nonCallMonths.rounded())
        guard step > 0 else { return nil }
        var m = step
        while m < termMonths {
            if m >= lockout { return m }
            m += step
        }
        return nil
    }

    /// Rebuild the instrument one feature at a time and price each stage.
    /// Deltas between rows are each feature's price in points of par.
    /// Default path count matches the Note-tab headline so the last row ties.
    public static func featureLedger(_ s: Instrument, paths: Int = fullPaths) -> [LedgerRow] {
        var stages: [(String, Instrument)] = []
        var b = s
        b.members = [s.members.first ?? "SPX"]
        b.basket = .worstOf
        b.downside = .par; b.gearedBuffer = false; b.minRedemption = 0
        b.protObs = .european; b.averaging = .none
        b.call = .none; b.memory = false; b.snowball = false; b.triggerStep = 0
        b.couponBarrierObs = .onPaymentDate
        b.callPremium = 0
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
            let obsName = s.protObs == .monthly ? "monthly" : (s.protObs == .quarterly ? "quarterly" : "monthly+bridge")
            add("+ monitored barrier (\(obsName))") { $0.protObs = s.protObs }
        }
        if s.downside == .kiPut && s.secondChance {
            add("+ second chance ≥\(Int(s.secondChanceLevel * 100))% (Elite)") {
                $0.secondChance = true; $0.secondChanceLevel = s.secondChanceLevel
            }
        }
        if s.members.count > 1 {
            add("+ \(s.basket == .worstOf ? "worst-of" : "weighted") basket ×\(s.members.count) (ρ \(String(format: "%.2f", s.correlation))\(s.crashCorrOn ? ", crash spike" : ""))") {
                $0.members = s.members; $0.basket = s.basket; $0.weights = s.weights
            }
        }
        if s.averaging != .none {
            add("+ Asian tail (\(s.averaging.fixings) daily fixings)") { $0.averaging = s.averaging }
        }
        if s.upside != .none {
            let upLabel: String
            if s.upside == .digital || s.upside == .digitalPlus {
                let itm = s.digitalStrike < 0.999 ? " ≥\(Int(s.digitalStrike * 100))%" : ""
                let lev = s.upside == .digitalPlus && s.digiPlusLeverage > 1.001
                    ? ", \(String(format: "%.2g", s.digiPlusLeverage))× above" : ""
                upLabel = "+ \(s.upside.rawValue.lowercased())\(itm)\(lev) leg"
            } else if s.upside == .absolute {
                upLabel = "+ absolute leg (KO \(Int(s.absoluteKO * 100))%, \(String(format: "%.2g", s.absParticipation))× down / \(String(format: "%.2g", s.participation))× up)"
            } else {
                upLabel = "+ \(s.upside.rawValue.lowercased()) leg"
            }
            add(upLabel) {
                $0.upside = s.upside; $0.participation = s.participation
                $0.cap = s.cap; $0.digital = s.digital
                $0.digitalStrike = s.digitalStrike; $0.digiPlusLeverage = s.digiPlusLeverage
                $0.absoluteKO = s.absoluteKO; $0.absParticipation = s.absParticipation
            }
        }
        if s.coupon == .contingent {
            add("+ contingent barrier \(Int(s.couponBarrier * 100))%") {
                $0.coupon = .contingent; $0.couponBarrier = s.couponBarrier
            }
        }
        if s.coupon == .contingent && s.couponBarrierObs == .dailyMonitored {
            add("+ coupon barrier monthly closes + bridge") { $0.couponBarrierObs = .dailyMonitored }
        }
        if s.memory {
            add("+ memory") { $0.memory = true }
        }
        if s.call != .none {
            add("+ \(s.call == .autocall ? "autocall" : "issuer call (LS)")") {
                $0.call = s.call; $0.callObs = s.callObs
                $0.callTrigger = s.callTrigger; $0.nonCallMonths = s.nonCallMonths
            }
        }
        if s.call != .none && s.callPremium > 0 {
            add("+ call premium \(String(format: "%.1f", s.callPremium * 100))%/yr") {
                $0.callPremium = s.callPremium
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
            LedgerRow(label: label, value: simulate(st, paths: paths).pv)
        }
    }
}
