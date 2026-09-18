//  DeskView.swift
//  Structured Notes
//
//  Builder on the left; always-price work-through on the right. Every dial is
//  an input; the output is the note's model value as a percentage of par.
//  Baskets are assembled by adding underliers one at a time. Coupon and call
//  schedules live in their own blocks. No solving, no presets. Four work-
//  through tabs (Note, Risk, The math, Learn).

import SwiftUI
import Charts

public struct DeskView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("structurednotes.spec") private var specJSON: String = ""
    @SceneStorage("structurednotes.pinned") private var pinnedJSON: String = ""
    @SceneStorage("structurednotes.pinnedMark") private var pinnedMarkRaw: String = ""
    @SceneStorage("structurednotes.lessonsDone") private var lessonsDoneRaw: String = ""
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
    @State private var prevSpec: Instrument?
    @State private var prevValue: Double?
    @State private var lastChange: ChangeNote?
    @State private var lastDelta: Double?
    @State private var openLesson: Int?
    @State private var pricing = false
    @State private var rememberedAutocallTrigger: Double = 1.0
    @State private var rememberedTriggerStep: Double = 0
    @State private var didRestore = false
    @State private var solverNote: String?

    private let notional = 1000.0
    private var isCompact: Bool { sizeClass == .compact }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isCompact {
                    VStack(alignment: .leading, spacing: 14) {
                        builder
                        workThrough
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        builder.frame(width: 336)
                        workThrough
                    }
                }
            }
            .padding(isCompact ? 12 : 16)
        }
        .background(Theme.paper)
        .onAppear {
            if !didRestore {
                didRestore = true
                if let saved = Instrument.fromJSON(specJSON), saved != spec {
                    spec = saved
                } else {
                    reprice()
                }
            }
        }
        .onChange(of: spec) { _, new in
            if let json = new.jsonString() { specJSON = json }
            reprice()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Structured Notes")
                    .font(.system(size: isCompact ? 22 : 26, weight: .semibold, design: .serif))
                Spacer()
                if !isCompact { headerButtons }
            }
            if isCompact { headerButtons }
            Divider().overlay(Theme.ink)
        }
    }

    private var headerButtons: some View {
        FlexibleWrap(spacing: 6) {
            Button {
                pinnedJSON = spec.jsonString() ?? ""
                pinnedMarkRaw = result.map { String($0.value) } ?? ""
            } label: {
                Label(pinnedJSON.isEmpty ? "Pin build" : "Re-pin", systemImage: "pin")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.ink)
            ShareLink(item: Teach.termSheetPlain(spec, offer: charges?.offer)) {
                Label("Share term sheet", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.ink)
            Button {
                clearTrail()
                spec = .initial
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.ink)
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
                  offHint: "Off — quoting model mid. Toggle for the dealer offer.",
                  help: Teach.blockHelp("charges")) {
            LeverRow(label: "Skew (vol pts per 10% moneyness)",
                     value: $spec.skewSlope, range: 0...0.025, step: 0.0025, field: .volV)
            LeverRow(label: "Overhedge barrier shift",
                     value: $spec.barrierShift, range: 0...0.03, step: 0.0025, field: .pct)
            LeverRow(label: "Correlation bid-ask (±ρ)",
                     value: $spec.corrBA, range: 0...0.08, step: 0.005, field: .corr)
            LeverRow(label: "Vol bid-ask on |vega|",
                     value: $spec.volBA, range: 0...0.015, step: 0.001, field: .volV)
            LeverRow(label: "Model / rebalancing reserve",
                     value: $spec.reserveBps, range: 0...50, step: 5, field: .bps)
            LeverRow(label: "UF — advisor + wholesaler (of principal)",
                     value: $spec.ufFee, range: 0...0.05, step: 0.0025, field: .pct)
            Text("Flat-vol Monte Carlo is a mid. These are the desk's costs of being wrong: the KI wing, unreplicable digitals, unhedgeable correlation.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var underlyingBlock: some View {
        Card(title: "Underlying", help: Teach.blockHelp("underlying")) {
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
                Text("\(a.ticker) — \(a.name) · \(px) · σ \(Fmt.pct(a.vol))\(a.sourced ? " modeled" : " est") · q \(Fmt.pct(a.div, 2))")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(Market.asOf)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if spec.members.count > 1 {
                ChoiceChips(options: BasketStyle.allCases.map { ($0, $0.rawValue) },
                            selection: spec.basket) { k in mutate { $0.basket = k } }
                if spec.basket == .weighted {
                    ForEach(Array(spec.members.enumerated()), id: \.element) { i, m in
                        LeverRow(label: "Weight \(m)",
                                 value: shareBinding(i),
                                 range: 0.05...0.90, step: 0.01, field: .pct0)
                    }
                    Text("Shares rebalance to sum to 100%.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LeverRow(label: "Pairwise correlation ρ",
                         value: $spec.correlation, range: 0.2...0.95, step: 0.05, field: .corr)
            }
            LeverRow(label: "Vol shift (all names)",
                     value: $spec.volShift, range: -0.10...0.15, step: 0.01, field: .volPts)
        }
    }

    private var tenorBlock: some View {
        Card(title: "Tenor & final valuation", help: Teach.blockHelp("tenor")) {
            LeverRow(label: "Term (\(termStr(spec.termYears)))",
                     value: Binding(get: { spec.termYears * 12 },
                                    set: { spec.termYears = $0 / 12 }),
                     range: 1...84, step: 1, field: .months)
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
                  offHint: "Off — no coupon leg. Toggle to add income.",
                  help: Teach.blockHelp("coupon")) {
            ChoiceChips(options: [(CouponStyle.guaranteed, "Guaranteed"), (.contingent, "Contingent")],
                        selection: spec.coupon) { k in
                mutate { s in
                    s.coupon = k
                    if k != .contingent { s.memory = false }
                }
            }
            Group {
                if !spec.snowball {
                    LeverRow(label: "Coupon rate",
                             value: $spec.couponRate, range: 0...0.25, step: 0.001, field: .pct)
                }
                Picker("Coupon observations", selection: $spec.couponObs) {
                    ForEach(CouponObs.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .pickerStyle(.menu).tint(Theme.ink)
                .onChange(of: spec.couponObs) { _, o in
                    if o == .european { mutate { $0.memory = false } }
                }
                if spec.couponObs == .european {
                    Text("European pays the full rate × tenor once at maturity — a 10% 3-year coupon is 30% at T, not a single 10% digital. Periodic schedules (monthly / quarterly / …) pay on calendar month-ends from issue.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Paid on calendar month-ends from issue (quarterly = 3, 6, 9, … months). Leftover months shorter than one period do not pay a stub.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if spec.coupon == .contingent {
                    LeverRow(label: "Coupon barrier",
                             value: $spec.couponBarrier, range: 0.4...1.0, step: 0.01, field: .pct0)
                    if spec.couponObs != .european {
                        ChoiceChips(options: BarrierObsStyle.allCases.map { ($0, "Obs: " + $0.deskLabel.lowercased()) },
                                    selection: spec.couponBarrierObs) { k in mutate { $0.couponBarrierObs = k } }
                        if spec.couponBarrierObs == .dailyMonitored {
                            Text("A close or a Brownian-bridge touch below the barrier at any point in the coupon period kills that coupon — the same interpolation KI daily monitoring uses, not a 252-day grid.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if spec.couponObs != .european && !spec.snowball {
                        ChipToggle(label: "Memory", on: spec.memory) { mutate { $0.memory.toggle() } }
                    }
                }
                Button {
                    let snapshot = spec
                    pricing = true
                    Task.detached(priority: .userInitiated) {
                        let c = await withCheckedContinuation { cont in
                            Self.mcQueue.async {
                                cont.resume(returning: Engine.couponForPar(snapshot))
                            }
                        }
                        await MainActor.run {
                            self.pricing = false
                            if let c {
                                mutate { s in
                                    if s.snowball { s.snowballRate = c } else { s.couponRate = c }
                                }
                                solverNote = snapshot.chargesOn
                                    ? "Set so the dealer offer prints at par (charges held at the current stack, then refreshed)."
                                    : "Set so the model mid prints at par — exact via Q on this schedule."
                            } else {
                                solverNote = "No coupon dates survive on this build, so there is no rate that prints par."
                            }
                        }
                    }
                } label: {
                    Label(spec.snowball ? "Solve snowball to par" : "Solve coupon to par",
                          systemImage: "equal.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered).tint(Theme.bond)
                Text(solverNote ?? "Solves the coupon so the dealer offer prints at par (model mid, if charges are off). Linear in Q on the live calendar, so the mid identity is exact.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var callBlock: some View {
        BlockCard(title: "Callability",
                  on: spec.call != .none,
                  toggle: { mutate { s in
                      if s.call == .autocall {
                          rememberedAutocallTrigger = s.callTrigger
                          rememberedTriggerStep = s.triggerStep
                      }
                      s.call = s.call == .none ? .autocall : .none
                      if s.call == .autocall {
                          s.callTrigger = rememberedAutocallTrigger
                          s.triggerStep = rememberedTriggerStep
                      }
                  } },
                  offHint: "Off — bullet, runs to maturity.",
                  help: Teach.blockHelp("call")) {
            ChoiceChips(options: [(CallFeature.autocall, "Autocall"), (.issuerCall, "Issuer call")],
                        selection: spec.call) { k in
                mutate { s in
                    if s.call == .autocall && k == .issuerCall {
                        rememberedAutocallTrigger = s.callTrigger
                        rememberedTriggerStep = s.triggerStep
                    }
                    s.call = k
                    if k == .issuerCall {
                        s.callTrigger = 1.0
                        s.triggerStep = 0
                    } else if k == .autocall {
                        s.callTrigger = rememberedAutocallTrigger
                        s.triggerStep = rememberedTriggerStep
                    }
                }
            }
            Group {
                Picker("Call observations", selection: $spec.callObs) {
                    ForEach(CallObs.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .pickerStyle(.menu).tint(Theme.ink)
                if spec.call == .autocall {
                    LeverRow(label: "Autocall trigger",
                             value: $spec.callTrigger, range: 0.7...1.1, step: 0.01, field: .pct0)
                    LeverRow(label: "Trigger step-down",
                             value: $spec.triggerStep, range: 0...0.10, step: 0.005, field: .stepPct)
                }
                LeverRow(label: "Call premium (p.a., paid at call)",
                         value: $spec.callPremium, range: 0...0.50, step: 0.0025, field: .pct)
                if spec.callPremium > 0 {
                    Text("Paid only if called — unlike snowball, nothing at maturity.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LeverRow(label: "Non-call period",
                         value: $spec.nonCallMonths, range: 0...24, step: 1, field: .months)
                if spec.coupon != .none {
                    ChipToggle(label: "Snowball: coupons accrue to call", on: spec.snowball) {
                        mutate { s in s.snowball.toggle(); if s.snowball { s.memory = false } }
                    }
                    if spec.snowball {
                        LeverRow(label: "Snowball rate (p.a.)",
                                 value: $spec.snowballRate, range: 0...0.25, step: 0.0025, field: .pct)
                    }
                }
                ChipToggle(label: "Lock-in (Memorizer)", on: spec.lockIn) {
                    mutate { $0.lockIn.toggle() }
                }
                if spec.lockIn {
                    LeverRow(label: "Lock level",
                             value: $spec.lockLevel, range: 0.6...1.05, step: 0.01, field: .pct0)
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
                  offHint: "Off — no participation leg.",
                  help: Teach.blockHelp("upside")) {
            ChoiceChips(options: [(UpsideKind.linear, "Linear"), (.absolute, "Absolute")],
                        selection: spec.upside) { k in mutate { $0.upside = k } }
            ChoiceChips(options: [(UpsideKind.digital, "Digital"), (.digitalPlus, "Digi-plus")],
                        selection: spec.upside) { k in mutate { $0.upside = k } }
            if [.linear, .absolute].contains(spec.upside) {
                LeverRow(label: spec.upside == .absolute ? "Upside participation" : "Participation",
                         value: $spec.participation, range: 0.25...3, step: 0.05, field: .pct0)
                if spec.upside == .absolute {
                    LeverRow(label: "Absolute participation (down side)",
                             value: $spec.absParticipation, range: 0.25...1.5, step: 0.05, field: .pct0)
                    LeverRow(label: "Absolute knock-out",
                             value: $spec.absoluteKO, range: 0.4...1.0, step: 0.01, field: .pct0)
                    Text("Absolute return pays between \(Fmt.pct(spec.absoluteKO, 0)) and par; below the KO, the downside block takes over. Max absolute gain = \(Fmt.pct(spec.absParticipation * (1 - spec.absoluteKO))).")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ChipToggle(label: spec.cap == nil ? "Add cap" : "Capped at +\(Fmt.pct((spec.cap ?? 1.3) - 1, 0))", on: spec.cap != nil) {
                    mutate { s in s.cap = s.cap == nil ? 1.30 : nil }
                }
                if spec.cap != nil {
                    LeverRow(label: "Cap level (+ above par)",
                             value: Binding(get: { spec.cap ?? 1.3 }, set: { spec.cap = $0 }),
                             range: 1.05...2.5, step: 0.01, field: .capPct)
                }
            }
            if [.digital, .digitalPlus].contains(spec.upside) {
                LeverRow(label: "Digital level",
                         value: $spec.digital, range: 0.05...1.0, step: 0.01, field: .pct0)
                LeverRow(label: "Digital strike (ITM below 100%)",
                         value: $spec.digitalStrike, range: 0.5...1.1, step: 0.01, field: .pct0)
                if spec.upside == .digitalPlus {
                    LeverRow(label: "Leverage above the digital",
                             value: $spec.digiPlusLeverage, range: 1...3, step: 0.05, field: .mult)
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
                  offHint: "Full protection (par floor). Toggle to sell downside.",
                  help: Teach.blockHelp("downside")) {
            ChoiceChips(options: [(DownsideKind.buffer, "Buffer"), (.kiPut, "KI put")],
                        selection: spec.downside) { k in mutate { $0.downside = k } }
            Group {
                LeverRow(label: spec.downside == .buffer ? "Buffer strike" : "KI barrier",
                         value: $spec.protection, range: 0.4...0.95, step: 0.01, field: .pct0)
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
                    Text(protObsHint)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    MiniHelp(title: "Why the observation matters more than the level",
                             help: Teach.blockHelp("protectionObs"))
                    ChipToggle(label: "Second chance (Elite)", on: spec.secondChance) {
                        mutate { $0.secondChance.toggle() }
                    }
                    if spec.secondChance {
                        LeverRow(label: "Second-chance level",
                                 value: $spec.secondChanceLevel, range: 0.3...0.9, step: 0.01, field: .pct0)
                        Text("A monitored knock is forgiven if the final level recovers to at least this. Pair with a monitored barrier.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                LeverRow(label: "Min redemption floor",
                         value: $spec.minRedemption, range: 0...0.95, step: 0.05, field: .pct0)
            }
        }
    }

    private var economicsBlock: some View {
        Card(title: "Rates & funding", help: Teach.blockHelp("rates")) {
            curveChart
            Text("Drag the chart to reshape the UST curve — the nearest pillar snaps to your finger. The shaded band is the credit spread resting on top. Sourced: Treasury.gov via Slickcharts, 7/22/26.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            LeverRow(label: "Funding spread @ 1Y",
                     value: $spec.spreadShort, range: 0...0.02, step: 0.0005, field: .bp)
            LeverRow(label: "Funding spread @ 7Y",
                     value: $spec.spreadLong, range: 0...0.02, step: 0.0005, field: .bp)
            Text("Funding at \(termStr(spec.termYears)) = \(Fmt.pct(Engine.fundingZero(spec, spec.termYears), 2)). Cash flows discount off the funding curve at their own dates; paths drift off risk-free forwards.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private struct CurvePt: Identifiable {
        var id: Double { t }
        let t: Double
        let lo: Double
        let hi: Double
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
        solverNote = nil
        var s = spec
        let beforeMembers = s.members
        let beforeBasket = s.basket
        f(&s)
        if s.members.isEmpty { s.members = ["SPX"] }
        if s.basket == .weighted, s.members != beforeMembers || beforeBasket != .weighted {
            let n = Double(s.members.count)
            for j in 0..<s.weights.count { s.weights[j] = 1.0 / n }
        }
        s.applyBuilderRules()
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
            if let ch = lastChange { changeCard(ch) }
            if pinnedSpec != nil && tab == .note { compareCard }
            switch tab {
            case .note:
                if isBare { startHereCard }
                valueCard
                offerCard
                payoffCard
                decompositionCard
                advisorCard
                outcomesCard
            case .risk:
                riskCard
                greeksCard
                eventCard
                ladderCard
                deskBookCard
            case .math:
                workCard
                ledgerCard
                assumptionsCard
            case .learn:
                lessonsCard
                termSheetCard
                glossaryCard
                suitabilityCard
            }
        }
    }

    private var isBare: Bool {
        spec.coupon == .none && spec.call == .none
            && spec.upside == .none && spec.downside == .par
    }

    private var protObsHint: String {
        switch spec.protObs {
        case .european:
            return "Looked at once, on the final valuation date. Intra-life dips are forgiven entirely."
        case .quarterly:
            return "Checked every quarter. One breach on any check is permanent, even if the market recovers."
        case .monthly:
            return "Checked every month — twelve times the chances to break versus a single European look."
        case .daily:
            return "Monthly closes plus a Brownian-bridge correction for touches between them — stricter than monthly monitoring, not a true 252-day fixings grid."
        }
    }

    // MARK: teaching — what just changed

    private func changeCard(_ ch: ChangeNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOU CHANGED").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.opt)
                Spacer()
                if let dl = lastDelta {
                    Text(String(format: "%+.2f pts of par", dl * 100))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(abs(dl) < 0.0002 ? Theme.fee : (dl > 0 ? Theme.bond : Theme.loss))
                }
            }
            Text(ch.label).font(.system(size: 14, weight: .semibold))
            Text(ch.why).font(.system(size: 12)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if ch.twoSided {
                Text("This lever is genuinely two-sided — read the measured number above rather than trusting the intuition.")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.amber)
            }
            if let dl = lastDelta, abs(dl) < 0.0002 {
                Text("Value barely moved. Either the feature is nearly free at these levels, or two effects inside it cancelled out.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.955, green: 0.965, blue: 0.98), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.opt.opacity(0.35)))
    }

    private var startHereCard: some View {
        Card(title: "Start here") {
            Text("Nothing is switched on yet, so what you are looking at is the raw material of every structured note: a promise from the bank to repay $1,000 in \(termStr(spec.termYears)), and nothing else.")
                .font(.system(size: 12.5))
            Text("Read the value below. The gap between it and par is the issuer's funding cost over the term — and that gap is the entire budget available to buy coupons, participation, or protection. Switch a block on in the rail to spend it.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
            Button {
                tab = .learn
            } label: {
                Label("Take the guided lessons", systemImage: "graduationcap")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent).tint(Theme.bond)
        }
    }

    // MARK: teaching — what the risk numbers mean

    private var greeksCard: some View {
        Card(title: "What these numbers mean") {
            ForEach(Teach.greeks, id: \.0) { name, meaning in
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 12.5, weight: .bold))
                    Text(meaning).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
            }
            Text("Every number above is a re-price of the same note with one input nudged and the terms held frozen. That is all a Greek is: the same instrument, priced twice.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: teaching — what the model does and does not do

    private var assumptionsCard: some View {
        Card(title: "What this model does — and where it is wrong") {
            ForEach(Self.assumptionRows, id: \.0) { head, body in
                VStack(alignment: .leading, spacing: 2) {
                    Text(head).font(.system(size: 12.5, weight: .bold))
                    Text(body).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
            }
            Text("Knowing where a model is wrong is more useful than knowing where it is right. Every item above is a real limitation, and each one has a well-known fix that a production desk applies.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private static let assumptionRows: [(String, String)] = [
        ("Simulation, not a formula",
         "Thousands of possible market paths are generated, the note's payoff is computed on each, and the results are averaged and discounted. There is no closed-form price for a path-dependent note, so this is what every desk does. Common random numbers are reused across calculations so that the difference between two builds is a real economic difference rather than sampling noise."),
        ("One flat volatility per name — the biggest simplification",
         "The model prices every option on a name at a single volatility. Real markets charge more for out-of-the-money puts, which is exactly where a knock-in barrier sits. That is why the mid is not the offer: the skew charge in the charge stack is the correction, and on income notes it is usually the largest single line."),
        ("Correlation is a single number",
         "One pairwise correlation is applied across the whole basket, and it does not change with the market. In practice correlation rises sharply in sell-offs, which makes worst-of baskets behave worse than modelled precisely when it matters most."),
        ("The issuer call is rule-based",
         "An issuer call is priced as though the bank calls whenever the level is at or above 100%. A bank exercising optimally would do better for itself and worse for the holder, so a value shown for an issuer-callable note is an upper bound rather than a quote."),
        ("Barriers are watched at fixed times",
         "Monitored barriers are checked on their observation schedule. The daily setting adds a Brownian-bridge correction for touches between closes, which is close to continuous monitoring but not identical to it."),
        ("Prices come from a stored snapshot",
         "Levels, dividends and volatilities are a saved snapshot, not a live feed, and volatilities for most names are documented estimates rather than listed implieds. Directions and magnitudes are reliable; the last decimal is not."),
        ("Lognormal paths",
         "Returns are assumed lognormal with constant volatility. Real markets gap, and gaps hurt barrier structures more than smooth diffusion does — which is part of what the model reserve in the charge stack is paying for."),
    ]

    // MARK: advisor education

    private var advisorCard: some View {
        Card(title: "How this note works — advisor view", help: Teach.blockHelp("advisor")) {
            bulletRow(color: Theme.amber, head: "You earn", body: earnLine)
            if spec.call != .none, let r = result {
                let life = "\(Fmt.pct(r.probCalled, 0)) of paths, ~\(String(format: "%.1f", r.expectedLife))y average life"
                if spec.call == .issuerCall {
                    bulletRow(color: Theme.opt, head: "It ends early",
                              body: "if the issuer chooses to, on a \(spec.callObs.rawValue.lowercased()) check after \(String(format: "%.0f", spec.nonCallMonths))m. The contract is at the issuer's discretion; the model prices the friendliest rule for you — call whenever the underlier is at or above 100% — so \(life) is an upper bound on what you keep, not the term sheet.")
                } else {
                    bulletRow(color: Theme.opt, head: "It ends early",
                              body: "if the \(spec.members.count > 1 ? "basket condition holds" : "underlier is at or above \(Fmt.pct(spec.callTrigger, 0))") on a \(spec.callObs.rawValue.lowercased()) check after \(String(format: "%.0f", spec.nonCallMonths))m — \(life).")
                }
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
            } else if spec.couponObs == .european {
                let lump = spec.couponRate * spec.termYears
                let when = spec.coupon == .guaranteed
                    ? "regardless of the market"
                    : "if the \(spec.members.count > 1 && spec.basket == .worstOf ? "worst performer" : "underlier") finishes at or above \(Fmt.pct(spec.couponBarrier, 0))"
                parts.append("a single \(Fmt.pct(lump)) at maturity (\(Fmt.pct(spec.couponRate)) × \(termStr(spec.termYears))), \(when)")
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
        case .digital: parts.append("a fixed \(Fmt.pct(spec.digital, 0)) return if the final level is at or above \(Fmt.pct(spec.digitalStrike, 0))")
        case .digitalPlus:
            parts.append("a \(Fmt.pct(spec.digital, 0)) minimum if the final level is at or above \(Fmt.pct(spec.digitalStrike, 0)), then \(String(format: "%.2g", spec.digiPlusLeverage))× of any further gain")
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
        Card(title: "Outcomes — \(Engine.fullPaths.formatted()) paths", help: Teach.blockHelp("outcomes")) {
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
                                Text(b.lumped ? "later" : termStr(b.t))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                Text("P(called) \(Fmt.pct(r.probCalled, 0)) · P(loss) \(Fmt.pct(r.probLoss, 0)) · E[life] \(String(format: "%.1f", r.expectedLife))y · avg coupons \(String(format: "%.1f", r.avgCoupons))")
                    .font(.system(size: 12, design: .monospaced))
                Text("Runs to maturity un-called and clean: \(Fmt.pct(max(1 - r.probCalled - r.probLoss, 0), 0)). P(loss) is a principal shortfall at maturity, not a knock that recovered through par.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Risk-neutral pricing weights — the right input for valuation, the wrong input for a client's expected return.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: glossary + suitability

    private var glossaryCard: some View {
        Card(title: "Plain English — tap any term") {
            FlexibleWrap(spacing: 6) {
                ForEach(Teach.glossary) { term in
                    Button {
                        glossaryTerm = glossaryTerm == term.name ? nil : term.name
                    } label: {
                        Text(term.name)
                            .font(.system(size: 11.5, weight: glossaryTerm == term.name ? .bold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(glossaryTerm == term.name ? Theme.ink : Color(red: 0.96, green: 0.95, blue: 0.92), in: Capsule())
                            .foregroundStyle(glossaryTerm == term.name ? .white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let t = glossaryTerm, let term = Teach.glossary.first(where: { $0.name == t }) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IF YOU ARE NEW").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.bond)
                        Text(term.plain).font(.system(size: 12.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOW A DESK SAYS IT").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.opt)
                        Text(term.desk).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("\(Teach.glossary.count) terms, each written twice: once for someone who has never seen a note, once the way it would be said on a desk.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: teaching — guided lessons

    private var lessonsCard: some View {
        Card(title: "Guided lessons") {
            let done = doneLessons
            let next = Teach.lessons.first { !done.contains($0.number) }
            Text("\(done.count) of \(Teach.lessons.count) loaded. Each one drops a structure into the rail and tells you what to do to it and what to watch.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next {
                Text("Next: Lesson \(next.number) — \(next.title)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.bond)
            } else {
                Text("You've loaded every lesson. Reset progress if you want to walk them again.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.bond)
            }
            ForEach(Teach.lessons) { lesson in
                VStack(alignment: .leading, spacing: 7) {
                    Button {
                        openLesson = openLesson == lesson.number ? nil : lesson.number
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: done.contains(lesson.number) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(done.contains(lesson.number) ? Theme.bond : Theme.fee)
                            Text("\(lesson.number)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(next?.number == lesson.number ? Theme.bond : Theme.ink))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(lesson.title).font(.system(size: 13.5, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(lesson.goal).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: openLesson == lesson.number ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10)).foregroundStyle(Theme.fee)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if openLesson == lesson.number {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(lesson.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 7) {
                                    Text("\(i + 1).").font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.opt)
                                    Text(step).font(.system(size: 12))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WHAT TO NOTICE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.bond)
                                Text(lesson.notice).font(.system(size: 12)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button {
                                clearTrail()
                                markLessonDone(lesson.number)
                                spec = lesson.spec
                                tab = .note
                            } label: {
                                Label("Load this build", systemImage: "arrow.down.circle")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.bordered).tint(Theme.bond)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 5)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
            }
            if !done.isEmpty {
                Button("Reset lesson progress") {
                    lessonsDoneRaw = ""
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.fee)
            }
        }
    }

    // MARK: teaching — the same note as a term sheet

    private var termSheetCard: some View {
        Card(title: "The same note, as a term sheet") {
            Text("Clients never see a slider. They see this. Every line below is generated from the build in the rail, in the language a prospectus would use.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Teach.termSheet(spec, offer: charges?.offer), id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.fee)
                    Text(value).font(.system(size: 12.5, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
            }
            Text("Read it against the rail: each phrase here is a lever you just dragged. The two most under-read lines on a real term sheet are the barrier observation and the estimated value.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ShareLink(item: Teach.termSheetPlain(spec, offer: charges?.offer)) {
                Label("Share term sheet", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered).tint(Theme.ink)
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

    private var compareCard: some View {
        Card(title: "Pinned vs live") {
            if let pinned = pinnedSpec {
                let liveMark = result?.value
                let pinMark = pinnedMark
                let pinCol = VStack(alignment: .leading, spacing: 3) {
                    Text("PINNED").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.fee)
                    Text(pinMark.map { Fmt.pct($0, 2) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text(blurb(pinned)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let liveCol = VStack(alignment: .leading, spacing: 3) {
                    Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.opt)
                    Text(liveMark.map { Fmt.pct($0, 2) } ?? "…")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.bond)
                    Text(blurb(spec)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCompact {
                    VStack(alignment: .leading, spacing: 10) { pinCol; liveCol }
                } else {
                    HStack(alignment: .top, spacing: 12) { pinCol; liveCol }
                }
                if let a = pinMark, let b = liveMark {
                    Text(String(format: "Δ %+.2f pts of par", (b - a) * 100))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(b >= a ? Theme.bond : Theme.loss)
                }
                if let note = Teach.describeChange(from: pinned, to: spec) {
                    Text(note.why).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button {
                        clearTrail()
                        spec = pinned
                    } label: {
                        Label("Load pinned", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered).tint(Theme.ink)
                    Button {
                        pinnedJSON = ""; pinnedMarkRaw = ""
                    } label: {
                        Label("Clear pin", systemImage: "pin.slash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered).tint(Theme.fee)
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
            Card(title: "Dealer offer build-up", help: Teach.blockHelp("offer")) {
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
            if spec.snowball {
                var cpn = "snowball \(Fmt.pct(spec.snowballRate))"
                if spec.coupon == .contingent { cpn += " contingent @ \(Fmt.pct(spec.couponBarrier, 0))" }
                if spec.couponBarrierObs == .dailyMonitored && spec.coupon == .contingent { cpn += ", monthly+bridge obs" }
                parts.append(cpn)
            } else {
                var cpn = "\(Fmt.pct(spec.couponRate)) \(spec.coupon == .guaranteed ? "guaranteed" : "contingent @ \(Fmt.pct(spec.couponBarrier, 0))")"
                cpn += " (\(spec.couponObs.rawValue.lowercased()))"
                if spec.memory { cpn += " memory" }
                if spec.couponBarrierObs == .dailyMonitored && spec.coupon == .contingent { cpn += ", monthly+bridge obs" }
                parts.append(cpn)
            }
        }
        if spec.call != .none {
            var call: String
            if spec.call == .autocall {
                call = "autocall \(Fmt.pct(spec.callTrigger, 0)) (\(spec.callObs.rawValue.lowercased()))"
                if spec.triggerStep > 0 { call += " −\(Int(spec.triggerStep * 100))%/yr" }
            } else {
                call = "issuer call at discretion (\(spec.callObs.rawValue.lowercased()); priced as if ≥100%)"
            }
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
        var id: String { series + String(ret) }
        let ret: Double
        let series: String
        let value: Double
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
        Card(title: "Redemption at maturity vs basket performance", help: Teach.blockHelp("payoff")) {
            Chart(payoffPoints) { pt in
                LineMark(x: .value("Performance %", pt.ret), y: .value("Value $", pt.value))
                    .foregroundStyle(by: .value("Series", pt.series))
                    .lineStyle(StrokeStyle(lineWidth: pt.series == "Note" ? 2.6 : 1.4,
                                           dash: pt.series == "Note" ? [] : [5, 4]))
            }
            .chartForegroundStyleScale(["Note": Theme.opt, "Direct": Color.gray])
            .chartYAxisLabel("$ per $1,000")
            .frame(height: 250)
            if spec.downside == .kiPut && spec.protObs != .european {
                Text("Drawn as European KI: knock is inferred from the final level only. A monitored knock that recovered through the barrier is drawn as clean.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if spec.coupon != .none {
                Text("Coupons ride on top of redemption.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var decompositionCard: some View {
        Card(title: "Trader decomposition (per $1,000)", help: Teach.blockHelp("decomposition")) {
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

    private struct MathStep: Identifiable {
        let id: Int
        let title: String
        let lines: [String]
        let meaning: String
    }

    private var workCard: some View {
        Card(title: "The work — every number, derived") {
            if let r = result {
                Text("Nothing below is asserted. Each step is computed from the same \(Engine.fullPaths.formatted()) simulated paths, and the formula is printed with its numbers already substituted so you can check it by hand.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(mathSteps(r)) { step in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text("\(step.id)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Theme.ink))
                            Text(step.title).font(.system(size: 13, weight: .semibold, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(step.lines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(step.meaning)
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
                }
            } else {
                ProgressView().font(.footnote)
            }
        }
    }

    private func mathSteps(_ r: PricingResult) -> [MathStep] {
        var out = [MathStep]()
        var n = 1
        func add(_ title: String, _ lines: [String], _ meaning: String) {
            out.append(MathStep(id: n, title: title, lines: lines, meaning: meaning)); n += 1
        }

        let zT = Engine.fundingZero(spec, spec.termYears)
        add("Discount every promise at the issuer's own cost of money",
            ["z_f(\(termStr(spec.termYears))) = UST \(Fmt.pct(Engine.zeroRF(spec, spec.termYears), 2)) + spread \(Fmt.bp(Engine.spread(spec, spec.termYears))) = \(Fmt.pct(zT, 2))",
             "df(T) = e^(−z_f·T) = \(String(format: "%.4f", exp(-zT * spec.termYears)))",
             "each earlier cash flow uses the rate for its own date"],
            "A dollar promised in the future is worth less today, and how much less depends on when it arrives and what it costs this particular bank to borrow. This is where the money for every feature comes from: the issuer keeps the interest it would have paid on a plain bond and spends it on options instead.")

        add("The par leg — the promise to give the principal back",
            ["par leg = E[df(τ)] × 1000 = \(Fmt.usd0(r.parLeg * notional))",
             spec.call != .none
                ? "P(called) = \(Fmt.pct(r.probCalled, 0)) · expected life \(String(format: "%.1f", r.expectedLife))y"
                : "no call — τ is always maturity"],
            "τ is simply the date the note ends: the call date on paths that get called, maturity on the rest. Average the discount factor at that date across every path and you have what the repayment promise is worth today. A call actually makes this leg worth more, because the principal comes back sooner.")

        if spec.downside != .par {
            add("The downside you sold — this is what funds the note",
                ["downside leg = E[df × shortfall] × 1000 = \(Fmt.usd0(r.downsideLeg * notional))",
                 "P(principal loss at maturity) = \(Fmt.pct(r.probLoss, 0))"],
                "On the paths where protection fails, the note repays less than par and the shortfall is money that stays with the issuer. Averaged and discounted, that is the market price of your downside. Every coupon and every point of participation in this note was bought with it.")
        }

        if spec.coupon != .none {
            let rate = spec.snowball ? spec.snowballRate : spec.couponRate
            let cName = spec.snowball ? "r_sb" : "c"
            let rateDec = String(format: "%.4f", rate)
            let qStr = String(format: "%.3f", r.qFactor)
            let legDec = String(format: "%.4f", r.couponLeg)
            add("The income leg — the coupon rate times Q",
                ["Q = E[Σ year-fraction × df at dates actually paid] = \(qStr)",
                 "\(cName) = \(rateDec) (\(Fmt.pct(rate, 2)) p.a.)",
                 "coupon leg = \(cName) × Q = \(rateDec) × \(qStr) = \(legDec) = \(Fmt.pct(r.couponLeg, 2)) of par = \(Fmt.usd0(r.couponLeg * notional)) per $1,000",
                 "coupons expected: \(String(format: "%.1f", r.avgCoupons))"],
                "Q is the note's own discounted count of coupons that actually get paid — not the number of dates on the schedule, but what survives after barriers and early calls take their toll. Multiply the headline rate by Q and you have the whole income leg, exactly. If you learn one number from this app, learn Q: comparing two income notes means comparing rate times Q, not rate.")
        }

        if r.premiumLeg > 0.0005 {
            add("The call premium leg — paid only if called",
                ["premium leg = E[df × premium × τ × 1{called}] = \(Fmt.usd0(r.premiumLeg * notional))"],
                "This leg exists only on the paths where the note is redeemed early. If it runs to maturity, this feature pays nothing at all — which is why a call premium and a coupon are not interchangeable, however similar the headline rates look.")
        }

        if spec.upside != .none {
            let linearUncapped = spec.upside == .linear && spec.cap == nil
            if (spec.upside == .linear || spec.upside == .absolute), r.upUnit > 1e-9 {
                if linearUncapped {
                    add("The upside leg — one unit at a time",
                        ["U = \(String(format: "%.4f", r.upUnit))",
                         "participation = \(String(format: "%.2f", spec.participation)) (\(Fmt.pct(spec.participation, 0)))",
                         "upside leg = participation × U = \(String(format: "%.2f", spec.participation)) × \(String(format: "%.4f", r.upUnit)) = \(String(format: "%.4f", r.upsideLeg)) = \(Fmt.pct(r.upsideLeg, 2)) of par = \(Fmt.usd0(r.upsideLeg * notional)) per $1,000"],
                        "U is what a single unit of participation is worth. Because the payoff is linear in participation, doubling participation exactly doubles this leg — so you can read a fair participation straight off U instead of guessing and re-pricing.")
                } else {
                    add("The upside leg — U is a residual unit, not a scalable participation price",
                        ["U = \(String(format: "%.4f", r.upUnit))",
                         "participation = \(String(format: "%.2f", spec.participation)) (\(Fmt.pct(spec.participation, 0)))",
                         "upside leg = participation × U = \(String(format: "%.2f", spec.participation)) × \(String(format: "%.4f", r.upUnit)) = \(String(format: "%.4f", r.upsideLeg)) = \(Fmt.pct(r.upsideLeg, 2)) of par = \(Fmt.usd0(r.upsideLeg * notional)) per $1,000"],
                        "The identity still ties because U is defined as the upside cash divided by the participation lever. That does not make the payoff linear in that lever: a binding cap, or the down-leg of an absolute note (which uses its own participation), will not double if you double the up-side participation. Read U as a residual, not a price you can scale.")
                }
            } else {
                add("The upside leg",
                    ["upside leg = E[df × payoff above par] × 1000 = \(Fmt.usd0(r.upsideLeg * notional))"],
                    "A digital pays a fixed amount in the states where it finishes above its strike, so its value is essentially that amount times the discounted probability of clearing the strike. There is no linearity to exploit here, which is why digitals are quoted by level rather than by participation.")
            }
        }

        var identity = "value = par"
        var numbers = String(format: "%.2f", r.parLeg * 100)
        if r.couponLeg > 0.0005 { identity += " + coupons"; numbers += String(format: " + %.2f", r.couponLeg * 100) }
        if r.premiumLeg > 0.0005 { identity += " + premium"; numbers += String(format: " + %.2f", r.premiumLeg * 100) }
        if r.upsideLeg > 0.0005 { identity += " + upside"; numbers += String(format: " + %.2f", r.upsideLeg * 100) }
        if r.downsideLeg > 0.0005 { identity += " − downside"; numbers += String(format: " − %.2f", r.downsideLeg * 100) }
        add("Add the legs up — the identity has to tie",
            [identity, numbers + String(format: " = %.2f%% of par", r.value * 100),
             String(format: "value − par = %+.2f pts", (r.value - 1) * 100)],
            "The legs add to the total with no residual, because every one of them was averaged over the same set of simulated paths. That is what reusing one fixed set of random draws buys you: an identity you can check on paper instead of a black box you have to trust.")

        if spec.chargesOn, let ch = charges {
            var line = String(format: "offer = mid %.2f", r.value * 100)
            if ch.skew > 0.0002 { line += String(format: " − skew %.2f", ch.skew * 100) }
            if ch.overhedge > 0.0002 { line += String(format: " − overhedge %.2f", ch.overhedge * 100) }
            if ch.corrBA > 0.0002 { line += String(format: " − corr %.2f", ch.corrBA * 100) }
            if ch.vegaBA > 0.0002 { line += String(format: " − vega %.2f", ch.vegaBA * 100) }
            if ch.reserve > 0.0002 { line += String(format: " − reserve %.2f", ch.reserve * 100) }
            add("From a model mid to a price a desk could trade",
                [line, String(format: "= %.2f%% of par", ch.offer * 100),
                 spec.ufFee > 0.0001
                    ? String(format: "issuer net at par = 100 − UF %.2f = %.2f · structuring margin %.2f",
                             spec.ufFee * 100, (1 - spec.ufFee) * 100, max(1 - spec.ufFee - ch.offer, 0) * 100)
                    : "no selling concession applied"],
                "The mid is frictionless and untradeable. Each subtraction is a real cost of hedging something the model cannot replicate — the volatility skew at the barrier strike, barriers and digitals that can only be approximated, correlation that has no clean hedge. The result is the number that appears on a term sheet as the estimated value, and the gap to par is not a markup but the price of the hedge plus distribution.")
        }

        let readback: String
        if r.value > 1.005 {
            readback = "Above par. No issuer could sell this, because the option package is worth more than the money coming in. Something has to be given back: a lower coupon, a tighter cap, a deeper barrier, or a shorter non-call period. Finding which lever does it most cheaply is exactly the structurer's job."
        } else if r.value < 0.93 {
            readback = "Well below par. There is a lot of unspent budget here, which means the terms are stingy for the risk being taken — the coupon or participation could go up materially before the note stops working for the issuer."
        } else {
            readback = "Inside the range a desk could actually print. Charges and distribution have to come out of the gap to par, and what remains is the structuring margin."
        }
        add("Reading the answer",
            [String(format: "model value %.2f%% of par  ·  %+.2f pts vs par", r.value * 100, (r.value - 1) * 100)],
            readback)

        return out
    }

    private var ledgerCard: some View {
        Card(title: "Feature ledger — each feature's price, in points of par", help: Teach.blockHelp("ledger")) {
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
            Text("Each row re-prices the build with one more feature at the same levers, on \(Engine.fastPaths.formatted()) paths rather than the headline \(Engine.fullPaths.formatted()). Green adds value to the holder; red is value sold. Do not expect 0.1pt agreement with the Note tab.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var riskCard: some View {
        Card(title: "Risk (terms frozen, market bumped)", help: Teach.blockHelp("risk")) {
            if let g = sens {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatCard(title: "Mark", value: Fmt.pct(g.mark, 1), sub: "of par")
                        StatCard(title: "Delta", value: String(format: "%+.2f", g.delta * notional),
                                 sub: "per 1% spot", color: g.delta >= 0 ? Theme.bond : Theme.loss)
                        StatCard(title: "Vega", value: String(format: "%+.2f", g.vega * notional),
                                 sub: "per vol pt", color: g.vega >= 0 ? Theme.bond : Theme.loss)
                        StatCard(title: "Gamma",
                                 value: abs(g.gamma) * notional < 0.5 ? "≈0" : (g.gamma >= 0 ? "Long" : "Short"),
                                 sub: abs(g.gamma) * notional < 0.5 ? "flat / sampling noise"
                                    : (g.gamma >= 0 ? "buys dips, sells rips" : "sells weakness into obs"),
                                 color: abs(g.gamma) * notional < 0.5 ? Theme.fee
                                    : (g.gamma >= 0 ? Theme.bond : Theme.loss))
                    }
                    HStack(spacing: 8) {
                        StatCard(title: "Correlation",
                                 value: spec.members.count > 1 ? String(format: "%+.2f", g.corr * notional) : "—",
                                 sub: "per +0.05 ρ", color: g.corr >= 0 ? Theme.bond : Theme.loss)
                        StatCard(title: "Funding DV", value: String(format: "%+.2f", g.fundingDV * notional),
                                 sub: "per +10bp spread")
                        StatCard(title: "Theta (1m)", value: String(format: "%+.2f", g.theta1m * notional),
                                 sub: "terms frozen", color: g.theta1m >= 0 ? Theme.bond : Theme.loss)
                        StatCard(title: "Paths", value: Engine.fullPaths.formatted(), sub: "CRN · fixed seed")
                    }
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
            Card(title: "Event risk — into the discontinuities", help: Teach.blockHelp("events")) {
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
        Card(title: "Profile — value & delta vs spot", help: Teach.blockHelp("ladder")) {
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
        Card(title: "Desk book", help: Teach.blockHelp("deskbook")) {
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
                : spec.protObs == .daily ? "monthly closes + Brownian-bridge hits"
                : "\(spec.protObs == .monthly ? "monthly" : "quarterly")-monitored"
            out.append("Long the client's \(Fmt.pct(spec.protection, 0)) KI put, \(obs). Vega and gamma concentrate at that strike.")
        }
        if spec.downside == .buffer {
            out.append("Long the \(spec.gearedBuffer ? "geared " : "")buffer put struck \(Fmt.pct(spec.protection, 0))\(spec.gearedBuffer ? " — full downside reachable" : "").")
        }
        if spec.coupon == .contingent {
            out.append("Short a \(spec.couponObs.rawValue.lowercased()) digital ladder at \(Fmt.pct(spec.couponBarrier, 0))\(spec.memory ? " with memory chaining" : "")\(spec.couponBarrierObs == .dailyMonitored ? ", monthly closes + Brownian-bridge hits" : "") — pin risk every observation date.")
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

    private var pinnedSpec: Instrument? { Instrument.fromJSON(pinnedJSON) }
    private var pinnedMark: Double? { Double(pinnedMarkRaw) }

    private var doneLessons: Set<Int> {
        Set(lessonsDoneRaw.split(separator: ",").compactMap { Int($0) })
    }

    private func markLessonDone(_ n: Int) {
        var s = doneLessons
        s.insert(n)
        lessonsDoneRaw = s.sorted().map(String.init).joined(separator: ",")
    }

    private func blurb(_ s: Instrument) -> String {
        let names = s.members.joined(separator: "/")
        let cpn: String
        if s.coupon == .none { cpn = "no coupon" }
        else if s.snowball { cpn = "snowball \(Fmt.pct(s.snowballRate))" }
        else { cpn = "\(Fmt.pct(s.couponRate)) \(s.coupon == .guaranteed ? "gtd" : "contingent")" }
        return "\(names), \(termStr(s.termYears)), \(cpn)"
    }

    private func clearTrail() {
        lastChange = nil; lastDelta = nil; prevSpec = nil; prevValue = nil
    }

    private static let mcQueue = DispatchQueue(label: "structurednotes.mc", qos: .userInitiated)
    private static let pricingGate = PricingGate()

    private func reprice() {
        repriceTask?.cancel()
        let snapshot = spec
        let baseSpec = prevSpec
        let baseValue = prevValue
        let myGen = Self.pricingGate.next()
        pricing = true
        repriceTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled || Self.pricingGate.current() != myGen { return }
            await MainActor.run {
                self.ladder = []; self.ledger = []; self.charges = nil
                self.events = []; self.assetRisk = []
            }
            let head: (PricingResult, Sensitivities)? = await withCheckedContinuation { cont in
                Self.mcQueue.async {
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let r = Engine.price(snapshot)
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let g = Engine.sensitivities(snapshot, mark: r.value)
                    cont.resume(returning: (r, g))
                }
            }
            guard let head, Self.pricingGate.current() == myGen else { return }
            let (r, g) = head
            await MainActor.run {
                if snapshot == self.spec {
                    self.result = r; self.sens = g
                    if let bs = baseSpec, let bv = baseValue, bs != snapshot {
                        if let note = Teach.describeChange(from: bs, to: snapshot) {
                            self.lastChange = note
                            self.lastDelta = r.value - bv
                        } else {
                            self.lastChange = nil
                            self.lastDelta = nil
                        }
                    }
                    self.prevSpec = snapshot
                    self.prevValue = r.value
                }
                self.pricing = false
            }
            let tail: (ChargeStack, [Engine.AssetRisk], [Engine.EventBlock], [LadderRow], [LedgerRow])? = await withCheckedContinuation { cont in
                Self.mcQueue.async {
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let ch = Engine.charges(snapshot, midValue: r.value, vega: g.vega)
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let ar = Engine.perAssetRisk(snapshot)
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let ev = Engine.eventScenarios(snapshot)
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let lad = Engine.spotLadder(snapshot)
                    guard Self.pricingGate.current() == myGen else {
                        cont.resume(returning: nil); return
                    }
                    let led = Engine.featureLedger(snapshot)
                    cont.resume(returning: (ch, ar, ev, lad, led))
                }
            }
            guard let tail, Self.pricingGate.current() == myGen else { return }
            await MainActor.run {
                if snapshot == self.spec {
                    self.charges = tail.0
                    self.assetRisk = tail.1
                    self.events = tail.2
                    self.ladder = tail.3
                    self.ledger = tail.4
                }
            }
        }
    }
}

private final class PricingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }
    func current() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
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

