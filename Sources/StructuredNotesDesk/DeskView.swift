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
                            Text(m.rawValue).font(.system(size: 12.5, weight: .semibold))
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
                    Menu {
                        ForEach(AssetID.allCases.filter { !spec.members.contains($0) }) { a in
                            Button(Market.asset(a).name + " (" + a.rawValue + ")") {
                                mutate { $0.members.append(a) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("Add").font(.system(size: 12.5, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Theme.rule))
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
            ForEach(spec.members, id: \.self) { m in
                let a = Market.asset(m)
                Text("\(a.ticker) \(a.spot < 1000 ? String(format: "%.2f", a.spot) : Fmt.usd0(a.spot)) · σ \(Fmt.pct(a.vol)) · q \(Fmt.pct(a.div, 2))")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            if spec.members.count > 1 {
                ChoiceChips(options: BasketStyle.allCases.map { ($0, $0.rawValue) },
                            selection: spec.basket) { k in mutate { $0.basket = k } }
                if spec.basket == .weighted {
                    ForEach(Array(spec.members.enumerated()), id: \.element) { i, m in
                        LeverRow(label: "Weight \(m.rawValue)",
                                 display: String(format: "%.2f", spec.weights[safe: i] ?? 1),
                                 value: Binding(get: { spec.weights[safe: i] ?? 1 },
                                                set: { if i < spec.weights.count { spec.weights[i] = $0 } }),
                                 range: 0.05...1, step: 0.05)
                    }
                    Text("Weights normalize in the engine.")
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
            Picker("Final valuation", selection: $spec.averaging) {
                ForEach(FinalAveraging.allCases) { o in Text(o.rawValue).tag(o) }
            }
            .pickerStyle(.menu).tint(Theme.ink)
        }
    }

    private var couponBlock: some View {
        Card(title: "Coupon") {
            ChoiceChips(options: CouponStyle.allCases.map { ($0, $0 == .none ? "None" : $0.rawValue) },
                        selection: spec.coupon) { k in
                mutate { s in
                    s.coupon = k
                    if k != .contingent { s.memory = false }
                    if k == .none { s.snowball = false }
                }
            }
            if spec.coupon != .none {
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
        Card(title: "Callability") {
            ChoiceChips(options: CallFeature.allCases.map { ($0, $0.rawValue) },
                        selection: spec.call) { k in
                mutate { s in
                    s.call = k
                    if k == .none { s.snowball = false }
                }
            }
            if spec.call != .none {
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
                }
                if spec.call == .issuerCall {
                    Text("Rule-based issuer call — holder value shown is an upper bound (LSMC optimal exercise is worth less to the holder).")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var upsideBlock: some View {
        Card(title: "Upside at maturity") {
            ChoiceChips(options: [(UpsideKind.none, "None"), (.linear, "Linear"), (.absolute, "Absolute")],
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
        Card(title: "Downside at maturity") {
            ChoiceChips(options: DownsideKind.allCases.map { ($0, $0 == .par ? "Par" : $0 == .buffer ? "Buffer" : "KI put") },
                        selection: spec.downside) { k in mutate { $0.downside = k } }
            if spec.downside != .par {
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

    private func mutate(_ f: (inout Instrument) -> Void) {
        var s = spec
        f(&s)
        if s.members.isEmpty { s.members = [.spx] }
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
                    Text("issue at par ⇒ embedded fee \(Fmt.pct(max(1 - r.value, 0)))")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text(configSummary)
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var configSummary: String {
        let names = spec.members.map(\.rawValue).joined(separator: "/")
        var parts = ["\(names)\(spec.members.count > 1 ? " (\(spec.basket.rawValue.lowercased()))" : ""), \(termStr(spec.termYears))"]
        if spec.averaging != .none { parts.append("\(spec.averaging.fixings)-fixing Asian tail") }
        if spec.coupon != .none {
            var cpn = "\(Fmt.pct(spec.couponRate)) \(spec.coupon == .guaranteed ? "guaranteed" : "contingent @ \(Fmt.pct(spec.couponBarrier, 0))")"
            cpn += " (\(spec.couponObs.rawValue.lowercased()))"
            if spec.memory { cpn += " memory" }
            if spec.snowball { cpn += ", snowball" }
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
            out.append("coupon leg = c·Q = \(Fmt.pct(spec.couponRate))·\(String(format: "%.3f", r.qFactor)) = \(Fmt.usd0(r.couponLeg * notional))")
        }
        if spec.upside != .none {
            if (spec.upside == .linear || spec.upside == .absolute), r.upUnit > 1e-9 {
                out.append("U = E[df·gain]/p = \(String(format: "%.4f", r.upUnit)) ⇒ upside = p·U = \(Fmt.usd0(r.upsideLeg * notional))")
            } else {
                out.append("upside   E[df·gain] = \(Fmt.usd0(r.upsideLeg * notional))")
            }
        }
        out.append("value = par + cpn + up − down = \(Fmt.pct(r.value, 2)) of par")
        out.append("issue at par ⇒ embedded fee = 1 − value = \(Fmt.pct(max(1 - r.value, 0), 2))")
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
            lines.append("Snowball concentrates the coupon into the call date — one large digital instead of a strip.")
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
        lines.append("Funding at UST + \(Fmt.bp(spec.fundingSpread)) discounts every flow — the funding DV is the issuer's edge on the shelf.")
        return lines
    }

    // MARK: repricing

    private func reprice() {
        let snapshot = spec
        pricing = true
        ladder = []; ledger = []
        Task.detached(priority: .userInitiated) {
            let r = Engine.price(snapshot)
            let g = Engine.sensitivities(snapshot)
            await MainActor.run {
                if snapshot == self.spec { self.result = r; self.sens = g }
                self.pricing = false
            }
            let lad = Engine.spotLadder(snapshot)
            let led = Engine.featureLedger(snapshot)
            await MainActor.run {
                if snapshot == self.spec { self.ladder = lad; self.ledger = led }
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

