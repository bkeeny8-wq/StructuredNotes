//  DeskView.swift
//  Structured Notes
//
//  Builder on the left; always-price work-through on the right. Every dial is
//  an input; the output is the note's model value as a percentage of par.
//  Baskets are assembled by adding underliers one at a time. Coupon and call
//  schedules live in their own blocks. No solving, no presets, no tabs.

import SwiftUI
import Charts

public struct DeskView: View {
    @State private var spec: Instrument = .initial
    @State private var result: PricingResult?
    @State private var sens: Sensitivities?
    @State private var ladder: [LadderRow] = []
    @State private var ledger: [LedgerRow] = []
    @State private var charges: ChargeStack?
    @State private var events: [Engine.EventBlock] = []
    @State private var assetRisk: [Engine.AssetRisk] = []
    @State private var tab: OutputTab = .note
    @State private var glossaryTerm: String?
    @State private var repriceTask: Task<Void, Never>?
    @State private var pricing = false

    private let notional = 1000.0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                HStack(alignment: .top, spacing: 14) {
                    builder.frame(width: 336)
                    workThrough
                }
            }
            .padding(16)
        }
        .background(Theme.paper)
        .onAppear { reprice() }
        .onChange(of: spec) { _, _ in reprice() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Structured Notes")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                Spacer()
                Button {
                    spec = .initial
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.ink)
            }
            Divider().overlay(Theme.ink)
        }
    }

    // MARK: builder

    private var builder: some View {
        VStack(spacing: 10) {
            underlyingBlock
            tenorBlock
            couponBlock
            callBlock
            upsideBlock
            downsideBlock
            economicsBlock
            chargesBlock
        }
    }

    private var chargesBlock: some View {
        BlockCard(title: "Charges & reserves",
                  on: spec.chargesOn,
                  toggle: { mutate { $0.chargesOn.toggle() } },
                  offHint: "Off — quoting model mid. Toggle for the dealer offer.") {
            LeverRow(label: "Skew (vol pts per 10% moneyness)",
                     display: String(format: "%.1fv", spec.skewSlope * 100),
                     value: $spec.skewSlope, range: 0...0.025, step: 0.0025)
            LeverRow(label: "Overhedge barrier shift",
                     display: Fmt.pct(spec.barrierShift),
                     value: $spec.barrierShift, range: 0...0.03, step: 0.0025)
            LeverRow(label: "Correlation bid-ask (±ρ)",
                     display: String(format: "±%.2f", spec.corrBA),
                     value: $spec.corrBA, range: 0...0.08, step: 0.005)
            LeverRow(label: "Vol bid-ask on |vega|",
                     display: String(format: "%.1fv", spec.volBA * 100),
                     value: $spec.volBA, range: 0...0.015, step: 0.001)
            LeverRow(label: "Model / rebalancing reserve",
                     display: String(format: "%.0fbp", spec.reserveBps),
                     value: $spec.reserveBps, range: 0...50, step: 5)
            LeverRow(label: "UF — advisor + wholesaler (of reoffer)",
                     display: Fmt.pct(spec.ufFee),
                     value: $spec.ufFee, range: 0...0.05, step: 0.0025)
            Text("Flat-vol Monte Carlo is a mid. These are the desk's costs of being wrong: the KI wing, unreplicable digitals, unhedgeable correlation.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var underlyingBlock: some View {
        Card(title: "Underlying") {
            FlexibleWrap(spacing: 6) {
                ForEach(spec.members, id: \.self) { m in
                    Button {
                        mutate { s in
                            if s.members.count > 1, let i = s.members.firstIndex(of: m) {
                                s.members.remove(at: i)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(m).font(.system(size: 12.5, weight: .semibold))
                            if spec.members.count > 1 {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.ink, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                if spec.members.count < Engine.maxAssets {
                    addMenu(title: "Index/ETF", list: Market.indexETF)
                    addMenu(title: "Stock", list: Market.stocks)
                }
            }
            ForEach(spec.members, id: \.self) { m in
                let a = Market.asset(m)
                let px = a.spot == 0 ? "—" : (a.spot < 1000 ? String(format: "%.2f", a.spot) : Fmt.usd0(a.spot))
                Text("\(a.ticker) \(px) · σ \(Fmt.pct(a.vol))\(a.sourced ? "" : " est") · q \(Fmt.pct(a.div, 2))")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            if spec.members.count > 1 {
                ChoiceChips(options: BasketStyle.allCases.map { ($0, $0.rawValue) },
                            selection: spec.basket) { k in mutate { $0.basket = k } }
                if spec.basket == .weighted {
                    ForEach(Array(spec.members.enumerated()), id: \.element) { i, m in
                        LeverRow(label: "Weight \(m)",
                                 display: Fmt.pct(share(i), 0),
                                 value: shareBinding(i),
                                 range: 0.05...0.90, step: 0.01)
                    }
                    Text("Shares rebalance to sum to 100%.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LeverRow(label: "Pairwise correlation ρ", display: String(format: "%.2f", spec.correlation),
                         value: $spec.correlation, range: 0.2...0.95, step: 0.05)
            }
        }
    }

    private var tenorBlock: some View {
        Card(title: "Tenor & final valuation") {
            LeverRow(label: "Term", display: termStr(spec.termYears),
                     value: Binding(get: { spec.termYears * 12 },
                                    set: { spec.termYears = $0 / 12 }),
                     range: 1...84, step: 1)
            ChipToggle(label: "Asian tail on final valuation", on: spec.averaging != .none) {
                mutate { s in s.averaging = s.averaging == .none ? .lastMonth : .none }
            }
            if spec.averaging != .none {
                ChoiceChips(options: [(FinalAveraging.lastWeek, "Last week (5d)"), (.lastMonth, "Last month (21d)")],
                            selection: spec.averaging) { k in mutate { $0.averaging = k } }
            }
        }
    }

    private var couponBlock: some View {
        BlockCard(title: "Coupon",
                  on: spec.coupon != .none,
                  toggle: { mutate { s in
                      s.coupon = s.coupon == .none ? .contingent : .none
                  } },
                  offHint: "Off — no coupon leg. Toggle to add income.") {
            ChoiceChips(options: [(CouponStyle.guaranteed, "Guaranteed"), (.contingent, "Contingent")],
                        selection: spec.coupon) { k in
                mutate { s in
                    s.coupon = k
                    if k != .contingent { s.memory = false }
                }
            }
            Group {
                LeverRow(label: "Coupon rate", display: Fmt.pct(spec.couponRate),
                         value: $spec.couponRate, range: 0...0.25, step: 0.001)
                Picker("Coupon observations", selection: $spec.couponObs) {
                    ForEach(CouponObs.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .pickerStyle(.menu).tint(Theme.ink)
                .onChange(of: spec.couponObs) { _, o in
                    if o == .daily || o == .european { mutate { $0.memory = false } }
                }
                if spec.coupon == .contingent {
                    LeverRow(label: "Coupon barrier", display: Fmt.pct(spec.couponBarrier, 0),
                             value: $spec.couponBarrier, range: 0.4...1.0, step: 0.01)
                    if spec.couponObs != .daily && spec.couponObs != .european {
                        ChoiceChips(options: BarrierObsStyle.allCases.map { ($0, "Obs: " + $0.rawValue.lowercased()) },
                                    selection: spec.couponBarrierObs) { k in mutate { $0.couponBarrierObs = k } }
                        if spec.couponBarrierObs == .dailyMonitored {
                            Text("Any breach during the period kills that coupon — approximated at the simulation grid.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if spec.couponObs != .daily && spec.couponObs != .european && !spec.snowball {
                        ChipToggle(label: "Memory", on: spec.memory) { mutate { $0.memory.toggle() } }
                    }
                }
                if spec.couponObs == .daily {
                    Text("Daily accrual is approximated at the simulation grid.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var callBlock: some View {
        BlockCard(title: "Callability",
                  on: spec.call != .none,
                  toggle: { mutate { s in
                      s.call = s.call == .none ? .autocall : .none
                  } },
                  offHint: "Off — bullet, runs to maturity.") {
            ChoiceChips(options: [(CallFeature.autocall, "Autocall"), (.issuerCall, "Issuer call")],
                        selection: spec.call) { k in
                mutate { s in
                    s.call = k
                    if k == .issuerCall { s.callTrigger = 1.0; s.triggerStep = 0 }
                }
            }
            Group {
                Picker("Call observations", selection: $spec.callObs) {
                    ForEach(CallObs.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .pickerStyle(.menu).tint(Theme.ink)
                if spec.call == .autocall {
                    LeverRow(label: "Autocall trigger", display: Fmt.pct(spec.callTrigger, 0),
                             value: $spec.callTrigger, range: 0.7...1.1, step: 0.01)
                    LeverRow(label: "Trigger step-down", display: spec.triggerStep == 0 ? "off" : String(format: "−%.0f%%/yr", spec.triggerStep * 100),
                             value: $spec.triggerStep, range: 0...0.10, step: 0.005)
                }
                LeverRow(label: "Call premium (p.a., paid at call)",
                         display: spec.callPremium == 0 ? "off" : Fmt.pct(spec.callPremium),
                         value: $spec.callPremium, range: 0...0.50, step: 0.0025)
                if spec.callPremium > 0 {
                    Text("Paid only if called — unlike snowball, nothing at maturity.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LeverRow(label: "Non-call period", display: String(format: "%.0fm", spec.nonCallMonths),
                         value: $spec.nonCallMonths, range: 0...24, step: 1)
                if spec.coupon != .none {
                    ChipToggle(label: "Snowball: coupons accrue to call", on: spec.snowball) {
                        mutate { s in s.snowball.toggle(); if s.snowball { s.memory = false } }
                    }
                    if spec.snowball {
                        LeverRow(label: "Snowball rate (p.a.)", display: Fmt.pct(spec.snowballRate),
                                 value: $spec.snowballRate, range: 0...0.25, step: 0.0025)
                    }
                }
                ChipToggle(label: "Lock-in (Memorizer)", on: spec.lockIn) {
                    mutate { $0.lockIn.toggle() }
                }
                if spec.lockIn {
                    LeverRow(label: "Lock level", display: Fmt.pct(spec.lockLevel, 0),
                             value: $spec.lockLevel, range: 0.6...1.05, step: 0.01)
                    Text("Touch the lock level on an observation and par redemption locks for good.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if spec.call == .issuerCall {
                    Text("Issuer may call at any observation after the non-call period. Priced as call at ≥ 100%, no adjustment — holder value is an upper bound (LSMC solves lower for the holder).")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var upsideBlock: some View {
        BlockCard(title: "Upside at maturity",
                  on: spec.upside != .none,
                  toggle: { mutate { s in
                      s.upside = s.upside == .none ? .linear : .none
                  } },
                  offHint: "Off — no participation leg.") {
            ChoiceChips(options: [(UpsideKind.linear, "Linear"), (.absolute, "Absolute")],
                        selection: spec.upside) { k in mutate { $0.upside = k } }
            ChoiceChips(options: [(UpsideKind.digital, "Digital"), (.digitalPlus, "Digi-plus")],
                        selection: spec.upside) { k in mutate { $0.upside = k } }
            if [.linear, .absolute].contains(spec.upside) {
                LeverRow(label: spec.upside == .absolute ? "Upside participation" : "Participation",
                         display: Fmt.pct(spec.participation, 0),
                         value: $spec.participation, range: 0.25...3, step: 0.05)
                if spec.upside == .absolute {
                    LeverRow(label: "Absolute participation (down side)",
                             display: Fmt.pct(spec.absParticipation, 0),
                             value: $spec.absParticipation, range: 0.25...1.5, step: 0.05)
                    LeverRow(label: "Absolute knock-out",
                             display: Fmt.pct(spec.absoluteKO, 0),
                             value: $spec.absoluteKO, range: 0.4...1.0, step: 0.01)
                    Text("Absolute return pays between \(Fmt.pct(spec.absoluteKO, 0)) and par; below the KO, the downside block takes over. Max absolute gain = \(Fmt.pct(spec.absParticipation * (1 - spec.absoluteKO))).")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ChipToggle(label: spec.cap == nil ? "Add cap" : "Capped at +\(Fmt.pct((spec.cap ?? 1.3) - 1, 0))", on: spec.cap != nil) {
                    mutate { s in s.cap = s.cap == nil ? 1.30 : nil }
                }
                if spec.cap != nil {
                    LeverRow(label: "Cap level", display: "+" + Fmt.pct((spec.cap ?? 1.3) - 1, 0),
                             value: Binding(get: { spec.cap ?? 1.3 }, set: { spec.cap = $0 }),
                             range: 1.05...2.5, step: 0.01)
                }
            }
            if [.digital, .digitalPlus].contains(spec.upside) {
                LeverRow(label: "Digital level", display: Fmt.pct(spec.digital, 0),
                         value: $spec.digital, range: 0.05...1.0, step: 0.01)
                LeverRow(label: "Digital strike (ITM below 100%)",
                         display: Fmt.pct(spec.digitalStrike, 0),
                         value: $spec.digitalStrike, range: 0.5...1.1, step: 0.01)
                if spec.upside == .digitalPlus {
                    LeverRow(label: "Leverage above the digital",
                             display: String(format: "%.2f×", spec.digiPlusLeverage),
                             value: $spec.digiPlusLeverage, range: 1...3, step: 0.05)
                }
            }
        }
    }

    private var downsideBlock: some View {
        BlockCard(title: "Downside at maturity",
                  on: spec.downside != .par,
                  toggle: { mutate { s in
                      s.downside = s.downside == .par ? .kiPut : .par
                  } },
                  offHint: "Full protection (par floor). Toggle to sell downside.") {
            ChoiceChips(options: [(DownsideKind.buffer, "Buffer"), (.kiPut, "KI put")],
                        selection: spec.downside) { k in mutate { $0.downside = k } }
            Group {
                LeverRow(label: spec.downside == .buffer ? "Buffer strike" : "KI barrier",
                         display: Fmt.pct(spec.protection, 0),
                         value: $spec.protection, range: 0.4...0.95, step: 0.01)
                if spec.downside == .buffer {
                    ChipToggle(label: "Geared (lose 1/strike below)", on: spec.gearedBuffer) {
                        mutate { $0.gearedBuffer.toggle() }
                    }
                }
                if spec.downside == .kiPut {
                    Picker("Protection observation", selection: $spec.protObs) {
                        ForEach(ProtectionObs.allCases) { o in Text(o.rawValue).tag(o) }
                    }
                    .pickerStyle(.menu).tint(Theme.ink)
                    ChipToggle(label: "Second chance (Elite)", on: spec.secondChance) {
                        mutate { $0.secondChance.toggle() }
                    }
                    if spec.secondChance {
                        LeverRow(label: "Second-chance level", display: Fmt.pct(spec.secondChanceLevel, 0),
                                 value: $spec.secondChanceLevel, range: 0.3...0.9, step: 0.01)
                        Text("A monitored knock is forgiven if the final level recovers to at least this. Pair with a monitored barrier.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                LeverRow(label: "Min redemption floor", display: spec.minRedemption == 0 ? "off" : Fmt.pct(spec.minRedemption, 0),
                         value: $spec.minRedemption, range: 0...0.95, step: 0.05)
            }
        }
    }

    private var economicsBlock: some View {
        Card(title: "Rates & funding") {
            curveChart
            Text("Drag the chart to reshape the UST curve — the nearest pillar snaps to your finger. The shaded band is the credit spread resting on top. Sourced: Treasury.gov via Slickcharts, 7/22/26.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            LeverRow(label: "Funding spread @ 1Y", display: Fmt.bp(spec.spreadShort),
                     value: $spec.spreadShort, range: 0...0.02, step: 0.0005)
            LeverRow(label: "Funding spread @ 7Y", display: Fmt.bp(spec.spreadLong),
                     value: $spec.spreadLong, range: 0...0.02, step: 0.0005)
            LeverRow(label: "Vol shift (all names)", display: String(format: "%+.0f pts", spec.volShift * 100),
                     value: $spec.volShift, range: -0.10...0.15, step: 0.01)
            Text("Funding at \(termStr(spec.termYears)) = \(Fmt.pct(Engine.fundingZero(spec, spec.termYears), 2)). Cash flows discount off the funding curve at their own dates; paths drift off risk-free forwards.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private struct CurvePt: Identifiable {
        let id = UUID(); let t: Double; let lo: Double; let hi: Double
    }
    private var curveSamples: [CurvePt] {
        stride(from: 0.25, through: 7.0, by: 0.25).map { t in
            CurvePt(t: t, lo: Engine.zeroRF(spec, t) * 100, hi: Engine.fundingZero(spec, t) * 100)
        }
    }
    private static let pillarTenors: [Double] = [0.25, 1, 2, 3, 5, 7]
    private func pillarRate(_ t: Double) -> Double {
        switch t {
        case 0.25: return spec.ust3m
        case 1: return spec.ust1y
        case 2: return spec.ust2y
        case 3: return spec.ust3y
        case 5: return spec.ust5y
        default: return spec.ust7y
        }
    }
    private func setPillar(_ t: Double, _ r: Double) {
        let v = min(0.07, max(0.02, (r / 0.0005).rounded() * 0.0005))
        switch t {
        case 0.25: spec.ust3m = v
        case 1: spec.ust1y = v
        case 2: spec.ust2y = v
        case 3: spec.ust3y = v
        case 5: spec.ust5y = v
        default: spec.ust7y = v
        }
    }

    private var curveChart: some View {
        let pts = curveSamples
        let yLo = (pts.map(\.lo).min() ?? 3.5) - 0.35
        let yHi = (pts.map(\.hi).max() ?? 5.5) + 0.35
        return Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("Tenor", p.t),
                         yStart: .value("UST", p.lo),
                         yEnd: .value("Funding", p.hi))
                    .foregroundStyle(Theme.amber.opacity(0.22))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Tenor", p.t), y: .value("Rate", p.lo),
                         series: .value("s", "UST"))
                    .foregroundStyle(Theme.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Tenor", p.t), y: .value("Rate", p.hi),
                         series: .value("s", "Funding"))
                    .foregroundStyle(Theme.bond)
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
            }
            ForEach(Self.pillarTenors, id: \.self) { t in
                PointMark(x: .value("Tenor", t), y: .value("Rate", pillarRate(t) * 100))
                    .foregroundStyle(Theme.ink)
                    .symbolSize(46)
            }
            RuleMark(x: .value("T", spec.termYears))
                .foregroundStyle(Theme.loss.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("T · \(Fmt.pct(Engine.fundingZero(spec, spec.termYears), 2))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.loss)
                }
        }
        .chartYScale(domain: yLo...yHi)
        .chartXScale(domain: 0...7.3)
        .chartXAxisLabel("Tenor (years)")
        .chartYAxisLabel("Rate %")
        .frame(height: 185)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let frame = geo[proxy.plotAreaFrame]
                                let x = value.location.x - frame.origin.x
                                let y = value.location.y - frame.origin.y
                                guard let t: Double = proxy.value(atX: x),
                                      let r: Double = proxy.value(atY: y) else { return }
                                let nearest = Self.pillarTenors.min {
                                    abs($0 - t) < abs($1 - t)
                                } ?? 3
                                setPillar(nearest, r / 100)
                            }
                    )
            }
        }
    }

    private func addMenu(title: String, list: [Asset]) -> some View {
        Menu {
            ForEach(list.filter { !spec.members.contains($0.ticker) }, id: \.ticker) { a in
                Button("\(a.ticker) — \(a.name)") {
                    mutate { $0.members.append(a.ticker) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Theme.rule))
            .foregroundStyle(Theme.ink)
        }
    }

    private func share(_ i: Int) -> Double {
        let n = spec.members.count
        let total = (0..<n).reduce(0.0) { $0 + (spec.weights[safe: $1] ?? 1) }
        guard total > 0, let w = spec.weights[safe: i] else { return 1.0 / Double(max(n, 1)) }
        return w / total
    }

    private func shareBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { share(i) },
            set: { v in
                let n = spec.members.count
                guard i < n else { return }
                var s = (0..<n).map { share($0) }
                let others = 1 - s[i]
                let scale = others > 1e-6 ? (1 - v) / others : 0
                for j in 0..<n where j != i { s[j] = others > 1e-6 ? s[j] * scale : (1 - v) / Double(max(n - 1, 1)) }
                s[i] = v
                for j in 0..<n where j < spec.weights.count { spec.weights[j] = s[j] }
            })
    }

    private func mutate(_ f: (inout Instrument) -> Void) {
        var s = spec
        let beforeMembers = s.members
        let beforeBasket = s.basket
        f(&s)
        if s.members.isEmpty { s.members = ["SPX"] }
        if s.basket == .weighted, s.members != beforeMembers || beforeBasket != .weighted {
            let n = Double(s.members.count)
            for j in 0..<s.weights.count { s.weights[j] = 1.0 / n }
        }
        if s.coupon == .none { s.memory = false; s.snowball = false }
        if s.call == .none { s.snowball = false }
        if s.snowball { s.memory = false }
        spec = s
    }

    private func termStr(_ t: Double) -> String {
        let m = Int((t * 12).rounded())
        if m < 12 { return "\(m)m" }
        return m % 12 == 0 ? "\(m / 12)y" : "\(m / 12)y \(m % 12)m"
    }

    // MARK: work-through

    private var workThrough: some View {
        VStack(spacing: 12) {
            PillSelector(tab: $tab)
            switch tab {
            case .note:
                valueCard
                offerCard
                payoffCard
                decompositionCard
                advisorCard
                outcomesCard
            case .risk:
                riskCard
                eventCard
                ladderCard
                deskBookCard
            case .math:
                workCard
                ledgerCard
                glossaryCard
                suitabilityCard
            }
        }
    }

    // MARK: advisor education

    private var advisorCard: some View {
        Card(title: "How this note works — advisor view") {
            bulletRow(color: Theme.amber, head: "You earn", body: earnLine)
            if spec.call != .none, let r = result {
                bulletRow(color: Theme.opt, head: "It ends early",
                          body: "if the \(spec.members.count > 1 ? "basket condition holds" : "underlier is at or above \(Fmt.pct(spec.callTrigger, 0))") on a \(spec.callObs.rawValue.lowercased()) check after \(String(format: "%.0f", spec.nonCallMonths))m — \(Fmt.pct(r.probCalled, 0)) of paths, ~\(String(format: "%.1f", r.expectedLife))y average life.")
            }
            bulletRow(color: Theme.loss, head: "You risk", body: riskLine)
            Text("Plain-English, generated from the live terms — it cannot drift from the structure.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func bulletRow(color: Color, head: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.system(size: 13, weight: .bold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var earnLine: String {
        var parts = [String]()
        if spec.coupon != .none {
            if spec.snowball {
                parts.append("\(Fmt.pct(spec.snowballRate)) per year, accrued and paid in one sum if the note is called")
            } else if spec.coupon == .guaranteed {
                parts.append("\(Fmt.pct(spec.couponRate)) per year, paid \(spec.couponObs.rawValue.lowercased()) regardless of the market")
            } else {
                parts.append("\(Fmt.pct(spec.couponRate)) per year, paid \(spec.couponObs.rawValue.lowercased()) when the \(spec.members.count > 1 && spec.basket == .worstOf ? "worst performer" : "underlier") is at or above \(Fmt.pct(spec.couponBarrier, 0))\(spec.memory ? " (missed coupons recovered on the next good check)" : "")")
            }
        }
        if spec.callPremium > 0 {
            parts.append("a \(Fmt.pct(spec.callPremium))/yr premium on top of par, only if called")
        }
        switch spec.upside {
        case .linear: parts.append("\(Fmt.pct(spec.participation, 0)) of any gain at maturity\(spec.cap != nil ? ", capped at +\(Fmt.pct((spec.cap ?? 1.3) - 1, 0))" : "")")
        case .digital, .digitalPlus: parts.append("a fixed \(Fmt.pct(spec.digital, 0)) return if the final level is at or above \(Fmt.pct(spec.digitalStrike, 0))")
        case .absolute: parts.append("gains in both directions down to \(Fmt.pct(spec.absoluteKO, 0))")
        case .none: break
        }
        if parts.isEmpty { return "This is a principal instrument — its value is the discount to par at the funding rate." }
        return parts.joined(separator: "; plus ") + "."
    }

    private var riskLine: String {
        guard let r = result else { return "…" }
        switch spec.downside {
        case .par:
            return "principal is fully protected at maturity — your exposure is the issuer's credit."
        case .buffer:
            return "losses beyond the first \(Fmt.pct(1 - spec.protection, 0)) decline\(spec.gearedBuffer ? ", at an accelerated \(String(format: "%.2g", 1 / spec.protection))× rate below the buffer" : "") — \(Fmt.pct(r.probLoss, 0)) of paths."
        case .kiPut:
            return "full downside from the start if the \(spec.members.count > 1 ? "worst performer" : "underlier") \(spec.protObs == .european ? "finishes" : "ever trades") below \(Fmt.pct(spec.protection, 0)) — \(Fmt.pct(r.probLoss, 0)) of paths\(spec.secondChance ? " (forgiven if the final level recovers above \(Fmt.pct(spec.secondChanceLevel, 0)))" : "")."
        }
    }

    private var outcomesCard: some View {
        Card(title: "Outcomes — \(Engine.fullPaths.formatted()) paths") {
            if let r = result {
                if !r.callDist.isEmpty {
                    Text("CALLED BY").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(r.callDist) { b in
                            VStack(spacing: 3) {
                                Text(Fmt.pct(b.p, 0))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.opt)
                                Capsule().fill(Theme.opt.opacity(0.85))
                                    .frame(width: 26, height: max(6, b.p * 220))
                                Text(termStr(b.t))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                Text("P(called) \(Fmt.pct(r.probCalled, 0)) · P(loss) \(Fmt.pct(r.probLoss, 0)) · E[life] \(String(format: "%.1f", r.expectedLife))y · avg coupons \(String(format: "%.1f", r.avgCoupons))")
                    .font(.system(size: 12, design: .monospaced))
                Text("Runs to maturity un-called and clean: \(Fmt.pct(max(1 - r.probCalled - r.probLoss, 0), 0)).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Risk-neutral path frequencies — the distribution advisors get asked about.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: glossary + suitability

    private static let glossary: [(String, String)] = [
        ("τ exit time", "The path's exit date — the call date if called, else maturity. Par discounts from τ."),
        ("Q annuity", "Expected sum of discount factors at paid coupon dates. The coupon leg is exactly c × Q."),
        ("z_f funding zero", "The issuer's funding rate at a tenor: UST plus the credit spread curve. Every flow discounts at its own z_f."),
        ("ρ correlation", "Pairwise co-movement of basket members. Worst-of holders are long ρ; the desk is short it."),
        ("KI knock-in", "A barrier that, once breached (per its observation style), converts protection into full downside from par."),
        ("Worst-of", "Conditions read the weakest member. More members or lower ρ make the worst worse — and the coupon bigger."),
        ("Memory", "Missed contingent coupons are recovered on the next observation that clears the barrier."),
        ("CRN", "Common random numbers: one fixed random set for every reval, so charge and ledger differences are noise-free."),
    ]

    private var glossaryCard: some View {
        Card(title: "Symbols & terms — tap to expand") {
            FlexibleWrap(spacing: 6) {
                ForEach(Self.glossary, id: \.0) { term, _ in
                    Button {
                        glossaryTerm = glossaryTerm == term ? nil : term
                    } label: {
                        Text(term)
                            .font(.system(size: 11.5, weight: glossaryTerm == term ? .bold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(glossaryTerm == term ? Theme.ink : Color(red: 0.96, green: 0.95, blue: 0.92), in: Capsule())
                            .foregroundStyle(glossaryTerm == term ? .white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let t = glossaryTerm, let def = Self.glossary.first(where: { $0.0 == t })?.1 {
                Text(def).font(.system(size: 12)).foregroundStyle(Theme.ink)
                    .padding(10)
                    .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var suitabilityCard: some View {
        Card(title: "Suitability & structure — advisor education") {
            ForEach([
                "Unsecured issuer obligation — the client owns the bank's credit, not the index.",
                "Estimated value sits below the price at issue: the gap is the charge stack plus distribution (see the offer build-up).",
                "Secondary liquidity is dealer-driven; marks follow the model and the desk's book, not a NAV.",
                "Tax treatment varies by structure (CPDI/OID vs prepaid forward) — flag it before the trade, not after.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.fee).frame(width: 5, height: 5).padding(.top, 6)
                    Text(line).font(.system(size: 12.5))
                }
            }
        }
    }

    private var valueCard: some View {
        Card(title: "Model value — % of par") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(result.map { Fmt.pct($0.value, 2) } ?? "…")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.bond)
                if pricing { ProgressView().controlSize(.small) }
                if let r = result {
                    let dlt = (r.value - 1) * 100
                    Text(String(format: "vs par: %+.2f pts", dlt) + (dlt < 0 ? " — room for fees/margin at par issue" : " — rich to par; restructure"))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text(configSummary)
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var offerCard: some View {
        if spec.chargesOn, let r = result {
            Card(title: "Dealer offer build-up") {
                LegRow(label: "Model mid (flat vol)", value: Fmt.pct(r.value, 2))
                if let ch = charges {
                    if ch.skew > 0.0002 { LegRow(label: "− skew: downside leg at strike vol", value: "−" + Fmt.pct(ch.skew, 2), color: Theme.loss) }
                    if ch.overhedge > 0.0002 { LegRow(label: "− overhedge: barriers shifted \(Fmt.pct(spec.barrierShift))", value: "−" + Fmt.pct(ch.overhedge, 2), color: Theme.loss) }
                    if ch.corrBA > 0.0002 { LegRow(label: "− correlation bid-ask ±\(String(format: "%.2f", spec.corrBA))", value: "−" + Fmt.pct(ch.corrBA, 2), color: Theme.loss) }
                    if ch.vegaBA > 0.0002 { LegRow(label: "− vol bid-ask on |vega|", value: "−" + Fmt.pct(ch.vegaBA, 2), color: Theme.loss) }
                    if ch.reserve > 0.0002 { LegRow(label: "− model / rebalancing reserve", value: "−" + Fmt.pct(ch.reserve, 2), color: Theme.fee) }
                    HStack {
                        Text("Dealer offer").font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text(Fmt.pct(ch.offer, 2))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.bond)
                    }
                    .padding(.top, 4)
                    if spec.ufFee > 0.0001 {
                        LegRow(label: "UF — advisor + wholesaler", value: "−" + Fmt.pct(spec.ufFee, 2), color: Theme.fee)
                        LegRow(label: "Issuer net proceeds at par (100 − UF)", value: Fmt.pct(1 - spec.ufFee, 2))
                        LegRow(label: "Structuring margin (proceeds − offer)",
                               value: Fmt.pct(max(1 - spec.ufFee - ch.offer, 0), 2), color: Theme.bond)
                    }
                    Text("This is the number that becomes the term sheet's estimated value — the model mid less the desk's cost of hedging what it cannot replicate.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    ProgressView("Building the charge stack…").font(.footnote)
                }
            }
        }
    }

    private var configSummary: String {
        let names = spec.members.joined(separator: "/")
        var parts = ["\(names)\(spec.members.count > 1 ? " (\(spec.basket.rawValue.lowercased()))" : ""), \(termStr(spec.termYears))"]
        if spec.averaging != .none { parts.append("\(spec.averaging.fixings)-fixing Asian tail") }
        if spec.coupon != .none {
            var cpn = "\(Fmt.pct(spec.couponRate)) \(spec.coupon == .guaranteed ? "guaranteed" : "contingent @ \(Fmt.pct(spec.couponBarrier, 0))")"
            cpn += " (\(spec.couponObs.rawValue.lowercased()))"
            if spec.memory { cpn += " memory" }
            if spec.snowball { cpn += ", snowball \(Fmt.pct(spec.snowballRate))" }
            if spec.couponBarrierObs == .dailyMonitored && spec.coupon == .contingent { cpn += ", daily-obs" }
            parts.append(cpn)
        }
        if spec.call != .none {
            var call = "\(spec.call == .autocall ? "autocall" : "issuer call") \(Fmt.pct(spec.callTrigger, 0)) (\(spec.callObs.rawValue.lowercased()))"
            if spec.triggerStep > 0 { call += " −\(Int(spec.triggerStep * 100))%/yr" }
            if spec.callPremium > 0 { call += " + \(Fmt.pct(spec.callPremium)) premium" }
            call += " after \(String(format: "%.0f", spec.nonCallMonths))m"
            parts.append(call)
        }
        if spec.upside != .none {
            var up = spec.upside.rawValue.lowercased() + (spec.cap != nil ? " capped" : "")
            if spec.upside == .absolute { up = "absolute ≥\(Fmt.pct(spec.absoluteKO, 0)) (\(Fmt.pct(spec.absParticipation, 0)) down / \(Fmt.pct(spec.participation, 0)) up)" }
            if [.digital, .digitalPlus].contains(spec.upside) {
                if spec.digitalStrike < 0.999 { up += " ≥\(Fmt.pct(spec.digitalStrike, 0)) (ITM)" }
                if spec.upside == .digitalPlus && spec.digiPlusLeverage > 1.001 {
                    up += ", \(String(format: "%.2g", spec.digiPlusLeverage))× above"
                }
            }
            parts.append(up)
        }
        switch spec.downside {
        case .par: parts.append("full protection")
        case .buffer: parts.append("\(spec.gearedBuffer ? "geared " : "")buffer \(Fmt.pct(spec.protection, 0))")
        case .kiPut: parts.append("KI \(Fmt.pct(spec.protection, 0)) \(spec.protObs == .european ? "European" : spec.protObs.rawValue.lowercased())")
        }
        if spec.secondChance && spec.downside == .kiPut { parts.append("2nd-chance ≥\(Fmt.pct(spec.secondChanceLevel, 0))") }
        if spec.lockIn { parts.append("lock-in ≥\(Fmt.pct(spec.lockLevel, 0))") }
        if spec.minRedemption > 0 { parts.append("floored \(Fmt.pct(spec.minRedemption, 0))") }
        return parts.joined(separator: " · ") + "."
    }

    private struct PayoffPoint: Identifiable {
        let id = UUID(); let ret: Double; let series: String; let value: Double
    }
    private var payoffPoints: [PayoffPoint] {
        var pts: [PayoffPoint] = []
        var ret = -60.0
        while ret <= 100 {
            let x = 1 + ret / 100
            let knocked = spec.downside == .kiPut && x < spec.protection
            let (up, loss) = Engine.components(perf: x, knocked: knocked, s: spec)
            pts.append(.init(ret: ret, series: "Note", value: (1 + up - loss) * notional))
            pts.append(.init(ret: ret, series: "Direct", value: x * notional))
            ret += 2
        }
        return pts
    }

    private var payoffCard: some View {
        Card(title: "Redemption at maturity vs basket performance") {
            Chart(payoffPoints) { pt in
                LineMark(x: .value("Performance %", pt.ret), y: .value("Value $", pt.value))
                    .foregroundStyle(by: .value("Series", pt.series))
                    .lineStyle(StrokeStyle(lineWidth: pt.series == "Note" ? 2.6 : 1.4,
                                           dash: pt.series == "Note" ? [] : [5, 4]))
            }
            .chartForegroundStyleScale(["Note": Theme.opt, "Direct": Color.gray])
            .chartYAxisLabel("$ per $1,000")
            .frame(height: 250)
            if spec.coupon != .none {
                Text("Coupons ride on top of redemption.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var decompositionCard: some View {
        Card(title: "Trader decomposition (per $1,000)") {
            if let r = result {
                LegRow(label: "Par leg — principal at exit", value: "+" + Fmt.usd0(r.parLeg * notional), color: Theme.bond)
                if r.premiumLeg > 0.0005 {
                    LegRow(label: "Call premium leg", value: "+" + Fmt.usd0(r.premiumLeg * notional), color: Theme.amber)
                }
                if r.couponLeg > 0.0005 {
                    LegRow(label: spec.snowball ? "Coupon accrual (snowball)" : "Coupon strip",
                           value: "+" + Fmt.usd0(r.couponLeg * notional), color: Theme.amber)
                }
                if r.upsideLeg > 0.0005 {
                    LegRow(label: "Upside leg (\(spec.upside.rawValue.lowercased()))", value: "+" + Fmt.usd0(r.upsideLeg * notional), color: Theme.opt)
                }
                if r.downsideLeg > 0.0005 {
                    LegRow(label: "Downside sold", value: "−" + Fmt.usd0(r.downsideLeg * notional), color: Theme.loss)
                }
                LegRow(label: "Model value", value: Fmt.pct(r.value, 2))
                CapitalStack(segs: [
                    .init(name: "Net principal", frac: r.parLeg - r.downsideLeg, color: Theme.bond),
                    .init(name: "Coupons", frac: r.couponLeg + r.premiumLeg, color: Theme.amber),
                    .init(name: "Upside", frac: r.upsideLeg, color: Theme.opt),
                    .init(name: "Issue-at-par gap", frac: max(1 - r.value, 0), color: Theme.fee),
                ], notional: notional)
            }
        }
    }

    private var workCard: some View {
        Card(title: "The work — algebra with the numbers in") {
            if let r = result {
                ForEach(workLines(r), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 2)
                }
                Text("Monte Carlo, \(Engine.fullPaths.formatted()) paths, common random numbers — legs are exactly additive, so the identity ties.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func workLines(_ r: PricingResult) -> [String] {
        var out = [String]()
        let zT = Engine.fundingZero(spec, spec.termYears)
        out.append("z_f(\(termStr(spec.termYears))) = UST(\(Fmt.pct(Engine.zeroRF(spec, spec.termYears), 2))) + spread(\(Fmt.bp(Engine.spread(spec, spec.termYears)))) = \(Fmt.pct(zT, 2))")
        out.append("df(T) = e^(−z_f·T) = \(String(format: "%.4f", exp(-zT * spec.termYears))) · earlier flows discount at their own tenors")
        out.append("par leg  E[df(τ)]·1000 = \(Fmt.usd0(r.parLeg * notional))")
        if spec.downside != .par {
            out.append("downside E[df·shortfall] = \(Fmt.usd0(r.downsideLeg * notional))   P(loss) = \(Fmt.pct(r.probLoss, 0))")
        }
        if spec.coupon != .none {
            out.append("Q = E[Σ df at paid dates] = \(String(format: "%.3f", r.qFactor))")
            let rate = spec.snowball ? spec.snowballRate : spec.couponRate
            out.append("coupon leg = \(spec.snowball ? "r_sb" : "c")·Q = \(Fmt.pct(rate))·\(String(format: "%.3f", r.qFactor)) = \(Fmt.usd0(r.couponLeg * notional))")
        }
        if r.premiumLeg > 0.0005 {
            out.append("premium leg = E[df·p_call·τ·1{called}] = \(Fmt.usd0(r.premiumLeg * notional))")
        }
        if spec.upside != .none {
            if (spec.upside == .linear || spec.upside == .absolute), r.upUnit > 1e-9 {
                out.append("U = E[df·gain]/p = \(String(format: "%.4f", r.upUnit)) ⇒ upside = p·U = \(Fmt.usd0(r.upsideLeg * notional))")
            } else {
                out.append("upside   E[df·gain] = \(Fmt.usd0(r.upsideLeg * notional))")
            }
        }
        out.append("value = par + cpn + up − down = \(Fmt.pct(r.value, 2)) of par")
        out.append(String(format: "value − par = %+.2f pts of par", (r.value - 1) * 100))
        return out
    }

    private var ledgerCard: some View {
        Card(title: "Feature ledger — each feature's price, in points of par") {
            if ledger.isEmpty {
                ProgressView("Re-pricing the feature stack…").font(.footnote)
            }
            ForEach(Array(ledger.enumerated()), id: \.element.id) { i, row in
                HStack {
                    Text(row.label).font(.system(size: 12.5))
                    Spacer()
                    if i > 0 {
                        let d = row.value - ledger[i - 1].value
                        Text(String(format: "%+.1f", d * 100))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(d >= 0 ? Theme.bond : Theme.loss)
                    }
                    Text(Fmt.pct(row.value, 1))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(minWidth: 76, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
            }
            Text("Each row re-prices the build with one more feature at the same levers. Green adds value to the holder; red is value sold.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var riskCard: some View {
        Card(title: "Risk (terms frozen, market bumped)") {
            if let g = sens {
                HStack(spacing: 8) {
                    StatCard(title: "Mark", value: Fmt.pct(g.mark, 1), sub: "of par")
                    StatCard(title: "Gamma", value: g.gamma >= 0 ? "Long" : "Short",
                             sub: g.gamma >= 0 ? "buys dips, sells rips" : "sells weakness into obs",
                             color: g.gamma >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Correlation",
                             value: spec.members.count > 1 ? String(format: "%+.2f", g.corr * notional) : "—",
                             sub: "per +0.05 ρ", color: g.corr >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Funding DV", value: String(format: "%+.2f", g.fundingDV * notional),
                             sub: "per +10bp spread")
                    StatCard(title: "Theta (1m)", value: String(format: "%+.2f", g.theta1m * notional),
                             sub: "terms frozen", color: g.theta1m >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Paths", value: Engine.fullPaths.formatted(), sub: "CRN · fixed seed")
                }
            } else {
                ProgressView().font(.footnote)
            }
            Text("HEDGE SHEET — RISK BY UNDERLYING").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary).padding(.top, 8)
            if assetRisk.isEmpty {
                ProgressView("Bumping each name alone…").font(.footnote)
            } else {
                HStack {
                    Text("Name").font(.system(size: 11, weight: .bold)).frame(width: 70, alignment: .leading)
                    Text("Delta $/1k · per 1% in this name").font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Vega $/1k · per vol pt").font(.system(size: 11, weight: .bold))
                        .frame(width: 150, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                ForEach(assetRisk) { row in
                    HStack {
                        Text(row.ticker).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(width: 70, alignment: .leading)
                        Text(String(format: "%+.2f", row.delta * notional))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(row.delta >= 0 ? Theme.opt : Theme.loss)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(String(format: "%+.2f", row.vega * notional))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(row.vega >= 0 ? Theme.bond : Theme.loss)
                            .frame(width: 150, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
                }
                let td = assetRisk.reduce(0) { $0 + $1.delta }
                let tv = assetRisk.reduce(0) { $0 + $1.vega }
                HStack {
                    Text("Total").font(.system(size: 13, weight: .bold))
                        .frame(width: 70, alignment: .leading)
                    Text(String(format: "%+.2f", td * notional))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(String(format: "%+.2f", tv * notional))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 150, alignment: .trailing)
                }
                .padding(.vertical, 3)
                Text("Each row bumps that name alone, the others held flat — where the hedge actually trades. Worst-of loads the highest-vol name; totals ≈ the parallel bump up to cross terms.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var eventCard: some View {
        if spec.call != .none || spec.downside == .kiPut {
            Card(title: "Event risk — into the discontinuities") {
                if events.isEmpty {
                    ProgressView("Rolling the clock to the events…").font(.footnote)
                }
                ForEach(events) { block in
                    Text(block.title)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.top, 2)
                    let isKI = block.title.contains("KI")
                    let level = (isKI ? spec.protection : spec.callTrigger) * 100
                    Chart {
                        ForEach(block.rows) { row in
                            LineMark(x: .value("Spot", row.spot * 100),
                                     y: .value(isKI ? "Mark" : "Delta",
                                               isKI ? row.mark * 100 : row.delta * notional))
                                .foregroundStyle(isKI ? Theme.bond : Theme.opt)
                                .lineStyle(StrokeStyle(lineWidth: 2.2))
                            PointMark(x: .value("Spot", row.spot * 100),
                                      y: .value(isKI ? "Mark" : "Delta",
                                                isKI ? row.mark * 100 : row.delta * notional))
                                .foregroundStyle(isKI ? Theme.bond : Theme.opt)
                                .symbolSize(18)
                        }
                        RuleMark(x: .value("Level", level))
                            .foregroundStyle((isKI ? Theme.loss : Theme.opt).opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [4, 4]))
                        if !isKI {
                            RuleMark(y: .value("Zero", 0))
                                .foregroundStyle(Color.gray.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 0.8))
                        }
                    }
                    .chartYAxisLabel(isKI ? "Mark % par" : "Delta $/1k")
                    .frame(height: 120)
                    Text(block.caption)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private var ladderCard: some View {
        Card(title: "Profile — value & delta vs spot") {
            if ladder.isEmpty {
                ProgressView("Bumping the ladder…").font(.footnote)
            } else {
                Chart {
                    ForEach(ladder) { row in
                        LineMark(x: .value("Spot", row.spot * 100),
                                 y: .value("Mark", row.mark * 100))
                            .foregroundStyle(Theme.bond)
                            .lineStyle(StrokeStyle(lineWidth: 2.4))
                        PointMark(x: .value("Spot", row.spot * 100),
                                  y: .value("Mark", row.mark * 100))
                            .foregroundStyle(Theme.bond)
                            .symbolSize(20)
                    }
                    if spec.downside != .par {
                        RuleMark(x: .value("KI", spec.protection * 100))
                            .foregroundStyle(Theme.loss.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [4, 4]))
                    }
                    if spec.call != .none {
                        RuleMark(x: .value("Trigger", spec.callTrigger * 100))
                            .foregroundStyle(Theme.opt.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartYAxisLabel("Mark % of par")
                .frame(height: 150)
                Chart {
                    ForEach(ladder) { row in
                        BarMark(x: .value("Spot", row.spot * 100),
                                y: .value("Delta", row.delta * notional),
                                width: 12)
                            .foregroundStyle(nearBarrier(row.spot) || (spec.call != .none && abs(row.spot - spec.callTrigger) < 0.03)
                                             ? Theme.loss : Theme.opt)
                    }
                }
                .chartYAxisLabel("Delta $/1k")
                .frame(height: 100)
                Text("The cliff, the flattening, the pins — red bars mark where hedges die: the barrier zone and the trigger.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func nearBarrier(_ spot: Double) -> Bool {
        spec.downside != .par && abs(spot - spec.protection) <= 0.06
    }

    private var deskBookCard: some View {
        Card(title: "Desk book") {
            Text("EXPOSURE").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            ForEach(exposureLines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.ink).frame(width: 5, height: 5).padding(.top, 6)
                    Text(line).font(.system(size: 13))
                }
            }
            Text("HEDGING THE MARKET RISK").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary).padding(.top, 6)
            ForEach(hedgeLines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.bond).frame(width: 5, height: 5).padding(.top, 6)
                    Text(line).font(.system(size: 13))
                }
            }
        }
    }

    /// What the issuing desk is left holding — the mirror of the note.
    private var exposureLines: [String] {
        var out = [String]()
        if spec.downside == .kiPut {
            let obs = spec.protObs == .european ? "European"
                : spec.protObs == .daily ? "daily-monitored (bridge) — richest and stickiest"
                : "\(spec.protObs == .monthly ? "monthly" : "quarterly")-monitored"
            out.append("Long the client's \(Fmt.pct(spec.protection, 0)) KI put, \(obs). Vega and gamma concentrate at that strike.")
        }
        if spec.downside == .buffer {
            out.append("Long the \(spec.gearedBuffer ? "geared " : "")buffer put struck \(Fmt.pct(spec.protection, 0))\(spec.gearedBuffer ? " — full downside reachable" : "").")
        }
        if spec.coupon == .contingent {
            out.append("Short a \(spec.couponObs.rawValue.lowercased()) digital ladder at \(Fmt.pct(spec.couponBarrier, 0))\(spec.memory ? " with memory chaining" : "")\(spec.couponBarrierObs == .dailyMonitored ? ", one-touch observed" : "") — pin risk every observation date.")
        }
        if spec.call != .none {
            let prem = spec.callPremium > 0 ? " The \(Fmt.pct(spec.callPremium))/yr call premium enlarges the trigger digital." : ""
            out.append("Negative gamma under the \(Fmt.pct(spec.callTrigger, 0)) \(spec.call == .autocall ? "autocall" : "issuer-call") trigger into \(spec.callObs.rawValue.lowercased()) observations — a print through it extinguishes the coupon-rich states.\(prem)")
        }
        if spec.members.count > 1 && spec.basket == .worstOf {
            out.append("Short correlation ×\(spec.members.count) — the chronic worst-of issuance position. The +0.05ρ number in the risk block sizes it.")
        }
        if [.digital, .digitalPlus].contains(spec.upside) {
            let itm = spec.digitalStrike < 0.999 ? " struck \(Fmt.pct(spec.digitalStrike, 0)) in-the-money" : ""
            let lev = spec.upside == .digitalPlus && spec.digiPlusLeverage > 1.001
                ? " with \(String(format: "%.2g", spec.digiPlusLeverage))× calls layered above" : ""
            out.append("Short the \(Fmt.pct(spec.digital, 0)) digital\(itm)\(lev) — one large European pin at maturity.")
        }
        if spec.upside == .absolute {
            out.append("Short realized absolute value in the \(Fmt.pct(spec.absoluteKO, 0))–100% zone (\(Fmt.pct(spec.absParticipation, 0)) participation) — the client owns a down-and-out put that knocks at \(Fmt.pct(spec.absoluteKO, 0)).")
        }
        if spec.lockIn {
            out.append("The KI put dies if \(Fmt.pct(spec.lockLevel, 0)) prints on an observation (lock-in) — hedge decays toward that touch.")
        }
        if out.isEmpty { out.append("Pure funding note — rates and issuer-spread risk only.") }
        return out
    }

    /// Concrete strategies for the exposures above, sized off the live Greeks.
    private var hedgeLines: [String] {
        var out = [String]()
        let hasIndex = spec.members.contains { ["SPX", "NDX", "RTY", "INDU", "QQQ", "SPY", "IWM"].contains($0) }
        let instruments = hasIndex ? "index futures (ES/NQ/RTY) or SPY/QQQ" : "cash shares and single-stock options"
        if let g = sens {
            let side = g.delta >= 0 ? "Buy" : "Sell"
            out.append("Delta: \(side) ≈ \(Fmt.usd0(abs(g.delta) * notional)) per $1,000 of notes across \(spec.members.joined(separator: "/")) via \(instruments). Re-strike after each observation; widen rebalancing bands near the trigger and barrier where gamma flips.")
            if spec.downside != .par {
                if g.vega < 0 {
                    out.append("Vol: issuance leaves the desk long the \(Fmt.pct(spec.protection, 0)) wing — recycle by selling \(termStr(spec.termYears)) puts or put spreads near that strike (vanilla-vs-barrier basis stays), or net against growth-note flow that runs the book short vol.")
                } else {
                    out.append("Vol: the book is short vol here — buy back \(termStr(spec.termYears)) options near \(Fmt.pct(spec.protection, 0)) or source vega from income-note issuance.")
                }
            }
        }
        if spec.members.count > 1 && spec.basket == .worstOf {
            out.append("Correlation: no listed hedge — reduce via short dispersion (sell single-name vol, buy index vol) or corr swaps where bid; otherwise warehouse and recycle against the dispersion desk.")
        }
        if spec.coupon == .contingent || spec.call != .none || (spec.downside == .kiPut && spec.protObs != .european) {
            out.append("Digitals & barriers: replicate as \(Fmt.pct(spec.barrierShift))-wide option spreads (the overhedge lever *is* the replication width); pre-position delta into observation dates instead of chasing the pin on the day.")
        }
        out.append("Rates: swap the fixed funding leg and key-rate the \(termStr(spec.termYears)) pillar — the curve chart marks the hedge tenor; the funding DV per 10bp sizes it.")
        return out
    }

    // MARK: repricing

    private func reprice() {
        repriceTask?.cancel()
        let snapshot = spec
        pricing = true
        repriceTask = Task.detached(priority: .userInitiated) {
            // debounce: coalesce slider/curve-drag ticks into one compute
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                self.ladder = []; self.ledger = []; self.charges = nil
                self.events = []; self.assetRisk = []
            }
            let r = Engine.price(snapshot)
            let g = Engine.sensitivities(snapshot, mark: r.value)
            await MainActor.run {
                if snapshot == self.spec { self.result = r; self.sens = g }
                self.pricing = false
            }
            let ch = Engine.charges(snapshot, midValue: r.value, vega: g.vega)
            await MainActor.run { if snapshot == self.spec { self.charges = ch } }
            let ar = Engine.perAssetRisk(snapshot)
            await MainActor.run { if snapshot == self.spec { self.assetRisk = ar } }
            let ev = Engine.eventScenarios(snapshot)
            await MainActor.run { if snapshot == self.spec { self.events = ev } }
            let lad = Engine.spotLadder(snapshot)
            await MainActor.run { if snapshot == self.spec { self.ladder = lad } }
            let led = Engine.featureLedger(snapshot)
            await MainActor.run { if snapshot == self.spec { self.ledger = led } }
        }
    }
}

struct FlexibleWrap: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

