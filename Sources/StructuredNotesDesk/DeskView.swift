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
            Text("Structured Notes")
                .font(.system(size: 26, weight: .semibold, design: .serif))
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
                Text("\(a.ticker) \(px) · σ \(Fmt.pct(a.vol))\(a.sourced ? "" : " est") · q \(Fmt.pct(a.div, 2)) · \(a.tapeCount) tape prints")
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
                mutate { $0.call = k }
            }
            Group {
                Picker("Call observations", selection: $spec.callObs) {
                    ForEach(CallObs.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .pickerStyle(.menu).tint(Theme.ink)
                LeverRow(label: spec.call == .autocall ? "Autocall trigger" : "Issuer-call rule: calls at ≥",
                         display: Fmt.pct(spec.callTrigger, 0),
                         value: $spec.callTrigger, range: 0.7...1.1, step: 0.01)
                LeverRow(label: "Trigger step-down", display: spec.triggerStep == 0 ? "off" : String(format: "−%.0f%%/yr", spec.triggerStep * 100),
                         value: $spec.triggerStep, range: 0...0.10, step: 0.005)
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
                    Text("Rule-based issuer call — holder value shown is an upper bound (LSMC optimal exercise is worth less to the holder).")
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
                LeverRow(label: "Participation", display: Fmt.pct(spec.participation, 0),
                         value: $spec.participation, range: 0.25...3, step: 0.05)
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
        Card(title: "Economics") {
            LeverRow(label: "Funding spread over UST \(Fmt.pct(Market.ust, 2))",
                     display: Fmt.bp(spec.fundingSpread),
                     value: $spec.fundingSpread, range: 0...0.02, step: 0.0005)
            LeverRow(label: "Vol shift (all names)", display: String(format: "%+.0f pts", spec.volShift * 100),
                     value: $spec.volShift, range: -0.10...0.15, step: 0.01)
            Text("Output is the note's model value as % of par. Every dial is an input — iterate the levers, read the price.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
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
            valueCard
            offerCard
            payoffCard
            decompositionCard
            workCard
            ledgerCard
            riskCard
            ladderCard
            deskBookCard
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
            call += " after \(String(format: "%.0f", spec.nonCallMonths))m"
            parts.append(call)
        }
        if spec.upside != .none {
            parts.append(spec.upside.rawValue.lowercased() + (spec.cap != nil ? " capped" : ""))
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
                    .init(name: "Coupons", frac: r.couponLeg, color: Theme.amber),
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
        out.append("df(t) = e^(−(\(Fmt.pct(Market.ust, 2)) + \(Fmt.bp(spec.fundingSpread)))·t)")
        out.append("par leg  E[df(τ)]·1000 = \(Fmt.usd0(r.parLeg * notional))")
        if spec.downside != .par {
            out.append("downside E[df·shortfall] = \(Fmt.usd0(r.downsideLeg * notional))   P(loss) = \(Fmt.pct(r.probLoss, 0))")
        }
        if spec.coupon != .none {
            out.append("Q = E[Σ df at paid dates] = \(String(format: "%.3f", r.qFactor))")
            let rate = spec.snowball ? spec.snowballRate : spec.couponRate
            out.append("coupon leg = \(spec.snowball ? "r_sb" : "c")·Q = \(Fmt.pct(rate))·\(String(format: "%.3f", r.qFactor)) = \(Fmt.usd0(r.couponLeg * notional))")
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
                    StatCard(title: "Equity delta", value: Fmt.usd0(g.delta * notional),
                             sub: "per $1,000 · desk offsets", color: Theme.opt)
                    StatCard(title: "Gamma", value: g.gamma >= 0 ? "Long" : "Short",
                             sub: g.gamma >= 0 ? "buys dips, sells rips" : "sells into weakness",
                             color: g.gamma >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Vega", value: String(format: "%+.2f", g.vega * notional),
                             sub: "per vol pt", color: g.vega >= 0 ? Theme.bond : Theme.loss)
                }
                HStack(spacing: 8) {
                    StatCard(title: "Correlation",
                             value: spec.members.count > 1 ? String(format: "%+.2f", g.corr * notional) : "—",
                             sub: "per +0.05 ρ", color: g.corr >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Funding DV", value: String(format: "%+.2f", g.fundingDV * notional),
                             sub: "per +10bp spread")
                    StatCard(title: "Theta (1m roll)", value: String(format: "%+.2f", g.theta1m * notional),
                             sub: "terms frozen", color: g.theta1m >= 0 ? Theme.bond : Theme.loss)
                    StatCard(title: "Paths", value: Engine.fullPaths.formatted(), sub: "CRN · seed fixed")
                }
            } else {
                ProgressView().font(.footnote)
            }
        }
    }

    private var ladderCard: some View {
        Card(title: "Spot ladder — value and delta into the barrier") {
            if ladder.isEmpty {
                ProgressView("Bumping the ladder…").font(.footnote)
            } else {
                HStack {
                    Text("Spot").font(.system(size: 11, weight: .bold)).frame(width: 60, alignment: .leading)
                    Text("Mark (% par)").font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Delta $/1k").font(.system(size: 11, weight: .bold)).frame(width: 100, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                ForEach(ladder) { row in
                    HStack {
                        Text(Fmt.pct(row.spot, 0)).font(.system(size: 13, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Text(Fmt.pct(row.mark, 1)).font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(Fmt.usd0(row.delta * notional))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(nearBarrier(row.spot) ? Theme.loss : Theme.ink)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .background(nearBarrier(row.spot) ? Theme.loss.opacity(0.07) : .clear)
                }
                Text("Delta concentrates near \(Fmt.pct(spec.protection, 0)); expect local sign flips at the call trigger near observation dates and small MC noise.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func nearBarrier(_ spot: Double) -> Bool {
        spec.downside != .par && abs(spot - spec.protection) <= 0.06
    }

    private var deskBookCard: some View {
        Card(title: "Desk book") {
            ForEach(deskBook, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.ink).frame(width: 5, height: 5).padding(.top, 6)
                    Text(line).font(.system(size: 13))
                }
            }
        }
    }

    private var deskBook: [String] {
        var lines = [String]()
        if spec.downside == .kiPut {
            lines.append("Desk is long the KI put the client sold — vega concentrated at the \(Fmt.pct(spec.protection, 0)) strike\(spec.protObs == .european ? "" : "; monitoring makes the put richer and the knock stickier").")
        }
        if spec.downside == .buffer {
            lines.append("Desk is long the \(spec.gearedBuffer ? "geared " : "")buffer put at \(Fmt.pct(spec.protection, 0))\(spec.gearedBuffer ? " — full downside is reachable, so the put is larger" : "").")
        }
        if spec.coupon == .contingent {
            lines.append("Short a digital ladder at \(Fmt.pct(spec.couponBarrier, 0)) — pin risk on each \(spec.couponObs.rawValue.lowercased()) observation\(spec.memory ? "; memory chains the digitals" : "").")
        }
        if spec.snowball {
            lines.append("Snowball at \(Fmt.pct(spec.snowballRate)) concentrates the coupon into the call date — one large digital instead of a strip.")
        }
        if spec.coupon == .contingent && spec.couponBarrierObs == .dailyMonitored {
            lines.append("Daily-observed coupon barrier turns the digital ladder one-touch — coupons are harder, and the same rate is worth less to the holder.")
        }
        if spec.lockIn {
            lines.append("Lock-in at \(Fmt.pct(spec.lockLevel, 0)): one touch extinguishes the desk's long KI put — the put dies on a good print.")
        }
        if spec.secondChance && spec.downside == .kiPut {
            lines.append("Second chance pulls the American knock back toward European — the desk's put cheapens and the note richens.")
        }
        if spec.call != .none {
            lines.append("Negative gamma just under the \(Fmt.pct(spec.callTrigger, 0)) trigger into \(spec.callObs.rawValue.lowercased()) observations — calling extinguishes coupon-rich states.")
        }
        if spec.call != .none && spec.triggerStep > 0 {
            lines.append("Step-down trigger: later digitals sit lower — calls come easier and the note de-risks itself over time.")
        }
        if spec.members.count > 1 {
            lines.append(spec.basket == .worstOf
                ? "Worst-of ×\(spec.members.count) = short correlation; the corr sensitivity recycles against dispersion books."
                : "Weighted basket: diversification cheapens the options — the desk is long correlation here.")
        }
        if spec.averaging != .none {
            lines.append("Asian tail (\(spec.averaging.fixings) fixings) dampens final-date variance — cheapens the KI put and trims terminal gamma.")
        }
        if spec.upside == .absolute {
            lines.append("Absolute upside adds a down-and-out put owned by the client — the desk is short realized absolute value while the barrier survives.")
        }
        if spec.upside == .linear || spec.upside == .digital || spec.upside == .digitalPlus {
            lines.append("Desk is short the upside leg — standard index vega, usually recycled against the income book.")
        }
        if spec.minRedemption > 0 {
            lines.append("Redemption floored at \(Fmt.pct(spec.minRedemption, 0)): the desk is short a put spread rather than the full tail.")
        }
        if spec.chargesOn {
            lines.append("The offer is mid less the cost of being wrong: the KI wing (skew), unreplicable digitals (overhedge), and unhedgeable correlation — that gap is the estimated-value discount clients see on term sheets.")
        }
        lines.append("Funding at UST + \(Fmt.bp(spec.fundingSpread)) discounts every flow — the funding DV is the issuer's edge on the shelf.")
        return lines
    }

    // MARK: repricing

    private func reprice() {
        let snapshot = spec
        pricing = true
        ladder = []; ledger = []; charges = nil
        Task.detached(priority: .userInitiated) {
            let r = Engine.price(snapshot)
            let g = Engine.sensitivities(snapshot)
            await MainActor.run {
                if snapshot == self.spec { self.result = r; self.sens = g }
                self.pricing = false
            }
            let ch = Engine.charges(snapshot, midValue: r.value, vega: g.vega)
            let lad = Engine.spotLadder(snapshot)
            let led = Engine.featureLedger(snapshot)
            await MainActor.run {
                if snapshot == self.spec { self.charges = ch; self.ladder = lad; self.ledger = led }
            }
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

