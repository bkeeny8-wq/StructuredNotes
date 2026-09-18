//  Teach.swift
//  StructuredNotesDesk
//
//  The teaching layer. All explanatory copy lives here, apart from layout, so
//  it can be edited without touching view code. Four kinds of content:
//
//   1. blockHelp     — what each builder block is, which way it moves value, what to watch
//   2. describeChange — after every edit, name the change and explain the mechanism
//   3. lessons       — a guided curriculum; each lesson loads a spec
//   4. glossary / greeks / termSheet — reference material in plain and desk language
//
//  Rule followed throughout: copy states *mechanisms*, never specific prices.
//  The app supplies live numbers, so nothing here can go stale when data moves.

import Foundation

// MARK: - Block help

public struct BlockHelp: Sendable {
    public let what: String
    public let moves: String
    public let watch: String
    public init(what: String, moves: String, watch: String) {
        self.what = what; self.moves = moves; self.watch = watch
    }
}

// MARK: - Change explanation

public struct ChangeNote: Sendable, Equatable {
    public let label: String     // "KI barrier 60% → 65%"
    public let why: String       // the mechanism
    public let twoSided: Bool    // true when the direction genuinely depends on the build
    public init(label: String, why: String, twoSided: Bool = false) {
        self.label = label; self.why = why; self.twoSided = twoSided
    }
}

// MARK: - Lessons

public struct Lesson: Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let title: String
    public let goal: String
    public let steps: [String]
    public let notice: String
    public let spec: Instrument
    public init(number: Int, title: String, goal: String, steps: [String], notice: String, spec: Instrument) {
        self.number = number; self.title = title; self.goal = goal
        self.steps = steps; self.notice = notice; self.spec = spec
    }
}

// MARK: - Glossary

public struct GlossaryTerm: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let plain: String
    public let desk: String
    public init(name: String, plain: String, desk: String) {
        self.name = name; self.plain = plain; self.desk = desk
    }
}

public enum Teach {

    // MARK: block help

    public static func blockHelp(_ key: String) -> BlockHelp {
        switch key {
        case "underlying":
            return BlockHelp(
                what: "What the note watches. One name, or up to four in a basket. Nothing about the note's payoff refers to dollars — everything is measured as a percentage of each name's level on the pricing date.",
                moves: "Higher volatility means a wider range of outcomes, which makes any protection you sold more valuable to the desk. A worst-of basket is the cheapest way to manufacture volatility without buying it: the worst of three names is far more likely to be down than any one of them.",
                watch: "Add a third name and watch value fall at the same coupon. Then switch the basket from worst-of to weighted and watch it jump back. That gap is the correlation premium. Local vol and crash corr are off by default; turn them on to put a smile and a selloff-corr spike in the paths so a knock-in can see those, not only as charges.")
        case "tenor":
            return BlockHelp(
                what: "How long the note lives, and how the final level is measured. The Asian tail replaces the single closing level with an average of the last few daily fixings.",
                moves: "Longer term cuts two ways: par is discounted from further away and the barrier has more time to break, but there are also more coupons to collect. Averaging shrinks the variance of the final level, which cheapens the put you sold.",
                watch: "Drag the term across a call date boundary and watch the expected life on the Note tab shift. Turn the Asian tail on and off — the effect is small and two-sided, which is itself worth learning.")
        case "coupon":
            return BlockHelp(
                what: "The income leg. Guaranteed coupons pay in every scenario. Contingent coupons pay only when the underlying is at or above the coupon barrier on the observation date. A European coupon pays the full rate × tenor once at maturity — a 10% 3-year European is 30% at T, not a single 10% digital.",
                moves: "Value rises one-for-one with the coupon rate against the annuity factor Q shown on the math tab. Anything that makes coupons harder to earn — a higher barrier, more frequent observations, a call that ends the note early — lowers value at the same headline rate.",
                watch: "Set a coupon with everything else off and watch value climb above par. No issuer can sell that. Something has to be sold to pay for it, which is what the downside block does.")
        case "call":
            return BlockHelp(
                what: "Early redemption. An autocall triggers automatically when the underlying is at or above the trigger on an observation date. An issuer call is the bank's choice. Both stop the note and return par.",
                moves: "Adding a call lowers value at the same coupon, because the note is taken away in exactly the healthy scenarios where you were happy to keep collecting. That is why callable notes quote higher coupons than bullets.",
                watch: "Turn the autocall on and watch value fall, then raise the trigger and watch it recover — a harder trigger means the note survives longer. Switch Autocall to Issuer call: the bank now exercises when a small LS fit says the remaining note is worth more than par, not when the underlier prints 100%. The called-by distribution on the Note tab shows where the early exits cluster.")
        case "upside":
            return BlockHelp(
                what: "What you receive at maturity if the market is up. Linear participation pays a share of the gain. A digital pays a fixed amount if the final level clears its strike. Absolute pays gains in both directions.",
                moves: "Every upside feature costs value, so it has to be funded by something: a cap, a buffer that starts closer to par, or a lower coupon. A cap is the most common funding source — you sell the right tail to buy protection.",
                watch: "Add a cap and watch value fall back toward par. Set the digital strike below 100% and watch value jump, because an in-the-money digital pays in far more scenarios.")
        case "downside":
            return BlockHelp(
                what: "What you sell to fund everything else. A buffer absorbs the first slice of losses. A knock-in put removes protection entirely once the barrier breaks, so losses are measured from par rather than from the barrier.",
                moves: "Selling more downside always raises the value of the note as built, which is how the issuer affords the coupon or participation. Lower barrier, less sold. Higher barrier, more sold. A geared buffer sells the most of all.",
                watch: "Compare a 60% knock-in with a 60% buffer at the same coupon. The knock-in is worth much more to the issuer, because the buffer erodes gradually while the knock-in falls off a cliff.")
        case "protectionObs":
            return BlockHelp(
                what: "How the barrier is watched. European looks once, at maturity. Monitored looks on a schedule and the breach sticks forever. Daily adds a Brownian-bridge correction between monthly closes — not a 252-day fixings grid.",
                moves: "The more often you look, the more often the barrier breaks, so the put you sold is worth more and the note is worth less at the same coupon.",
                watch: "Hold the barrier at 60% and step through European, monthly, and daily. Three different prices for the same headline number — this is the single most under-read line on a term sheet.")
        case "rates":
            return BlockHelp(
                what: "The issuer's funding curve: Treasury yields plus the bank's credit spread. Every cash flow is discounted at the rate for its own date, and the paths drift on the risk-free forwards between dates.",
                moves: "A wider credit spread means the bond leg costs the issuer less to deliver, which leaves more money to spend on coupons and participation. This funding advantage is a large part of why banks issue notes at all.",
                watch: "Drag the front of the curve up and watch a short, high-call-probability structure react more than a long one. Called paths ride the short end, so the shape of the curve — not just its level — matters.")
        case "charges":
            return TeachCopy.chargesHelp
        case "payoff":
            return BlockHelp(
                what: "What you get back at maturity for every possible level of the underlying, per $1,000. The dashed line is what you would have had by simply owning the market instead, so the gap between the two lines is what the structure did for you — or to you. This is a European slice: knock is inferred from the final level, so a monitored knock-in that touched and recovered is drawn as if it never knocked.",
                moves: "",
                watch: "Find the places where the solid line jumps or bends. Every one of those is a barrier or a strike, and every one of them is a point where a small market move changes your outcome a lot. Coupons are not drawn here; they ride on top of whatever this chart shows.")
        case "decomposition":
            return BlockHelp(
                what: "The note taken apart into the pieces a trading desk actually buys and sells: the discounted promise to repay principal, the coupon stream, any upside option, and the downside option you sold.",
                moves: "",
                watch: "Check that the pieces add to the total. They do, exactly, because all of them were averaged over the same simulated paths. Read the downside line as the price tag on your protection giveaway — it is the budget every other line was paid from.")
        case "offer":
            return BlockHelp(
                what: "The walk from a frictionless model price down to a number a desk could actually trade, and then down again to what the issuer nets after paying the distributor.",
                moves: "",
                watch: "This is where a term sheet's estimated value comes from. Note where the selling concession sits: below the dealer offer, not above it. It comes out of the issuer's proceeds and does not change the option package at all.")
        case "outcomes":
            return BlockHelp(
                what: "How often each ending happens across the simulated paths: called early and when, finished with a loss, or ran to maturity clean.",
                moves: "",
                watch: "Read these as pricing weights, not as a forecast. They come from a risk-neutral simulation, which deliberately assumes every asset drifts at the funding rate rather than at whatever you believe equities will return. That assumption is what makes the price arbitrage-free, and it is why these numbers are the right input for valuation and the wrong input for a client's expected return.")
        case "advisor":
            return BlockHelp(
                what: "The same structure written the way you would say it out loud to a client: what they earn, how it can end early, and what they are risking. An issuer call is described as the bank's discretion; the LS exercise is the pricing assumption, not the contract.",
                moves: "",
                watch: "Every sentence here is generated from the live build, so it can never drift from the actual terms. If a sentence surprises you, the build is not what you thought it was.")
        case "risk":
            return BlockHelp(
                what: "The note priced again with one market input nudged and every contractual term held frozen. The difference is the sensitivity — that is all a Greek is.",
                moves: "",
                watch: "The hedge sheet underneath is the useful part: it bumps each underlying on its own, with the others held still, which is how a desk actually decides what to trade. On a worst-of the risk is rarely spread evenly.")
        case "events":
            return BlockHelp(
                what: "The clock rolled forward to the note's dangerous moments — the first call observation, and the final month before maturity — with the terms unchanged.",
                moves: "",
                watch: "Look for the sign flip through an autocall trigger, and the near-vertical stretch just above a KI barrier. On an issuer call the chart is min(continuation, redemption), not a 100% cliff. Those are the places where hedging a note is genuinely hard, and they are invisible in today's numbers.")
        case "ladder":
            return BlockHelp(
                what: "Value and sensitivity across a range of market levels, drawn rather than tabulated.",
                moves: "",
                watch: "Notice that sensitivity peaks between the barriers rather than at today's level. The note's fate is most uncertain there, which is exactly where its value moves fastest.")
        case "deskbook":
            return BlockHelp(
                what: "The mirror image of your position: what the issuing desk is left holding after selling you the note, and the trades it would put on to neutralise that.",
                moves: "",
                watch: "Everything the desk is long, you are short, and vice versa. Reading this makes the pricing intuitive — you can see why the desk cares about the barrier strike, the observation dates, and the correlation, because those are the things it has to hedge.")
        case "ledger":
            return BlockHelp(
                what: "The note rebuilt one feature at a time, priced at every step on the fast 1,600-path set (the headline mark uses 4,000). Each row's change is that feature's price in points of par — deltas versus the Note tab will not match to a tenth of a point.",
                moves: "",
                watch: "Order matters: a feature's price depends on what is already switched on, because features interact. A barrier is worth much more on a worst-of than on a single index. Read the ledger as one particular path through the build, not as a set of independent prices.")
        default:
            return BlockHelp(what: "", moves: "", watch: "")
        }
    }

    // MARK: change explanation

    /// Name what changed between two builds and explain the mechanism.
    /// Returns nil when nothing meaningful moved.
    public static func describeChange(from a: Instrument, to b: Instrument) -> ChangeNote? {
        func p(_ x: Double, _ d: Int = 0) -> String { String(format: "%.\(d)f%%", x * 100) }
        func moved(_ x: Double, _ y: Double, _ tol: Double = 1e-9) -> Bool { abs(x - y) > tol }

        // ---- underlying
        if a.members != b.members {
            if b.members.count > a.members.count {
                let added = b.members.filter { !a.members.contains($0) }.joined(separator: ", ")
                if b.basket == .weighted {
                    return ChangeNote(
                        label: "Added \(added) to the basket",
                        why: "A new name in a weighted basket dilutes every existing weight. You have more diversification, not a worse worst-of — the average usually gets safer, so the same terms are typically worth more. The move is two-sided if the name you added is much more volatile than what was already there.",
                        twoSided: true)
                }
                return ChangeNote(
                    label: "Added \(added) to the basket",
                    why: "Every name you add is another way for the worst performer to be worse. A worst-of over more names has a lower expected minimum, so barriers break more often and the note is worth less at the same coupon. Run it the other way and you see why issuers add names when a client asks for a bigger coupon.")
            }
            let dropped = a.members.filter { !b.members.contains($0) }.joined(separator: ", ")
            if b.basket == .weighted {
                return ChangeNote(
                    label: "Removed \(dropped) from the basket",
                    why: "Fewer names in a weighted basket concentrates the remaining weights. That can help or hurt depending on which name left — it is not the worst-of story where fewer names is always kinder.",
                    twoSided: true)
            }
            return ChangeNote(
                label: "Removed \(dropped) from the basket",
                why: "Fewer names means a less punishing worst performer, so the protection you sold is worth less to the desk and the note is worth more as built.")
        }
        if a.basket != b.basket {
            return b.basket == .weighted
                ? ChangeNote(label: "Basket → weighted",
                             why: "A weighted basket averages the members, so one blow-up gets diluted by the others. Averaging is much safer than taking the worst, so the same terms are worth more. This is the clearest lesson in the app: the fat coupon on a worst-of is payment for accepting no diversification.")
                : ChangeNote(label: "Basket → worst-of",
                             why: "Conditions now read the weakest member instead of the average. The worst of several names is far more likely to be below a barrier than their average, so you have sold much more downside and the note is worth less as built.")
        }
        if a.weights != b.weights && b.basket == .weighted {
            return ChangeNote(
                label: "Basket weights changed",
                why: "Weights are normalised to sum to 100%, so raising one name lowers the others proportionally. Concentrating into a high-vol name usually makes the same terms worth less; concentrating into a low-vol name usually makes them worth more. Watch the measured Δ rather than assuming diversification always helps.",
                twoSided: true)
        }
        if moved(a.correlation, b.correlation) {
            return b.correlation > a.correlation
                ? ChangeNote(label: "Correlation \(String(format: "%.2f", a.correlation)) → \(String(format: "%.2f", b.correlation))",
                             why: "When names move together, the worst performer is not much worse than the average, so a worst-of behaves more like a single name. That helps you as the holder. The desk is short this — there is no clean way to hedge correlation, which is why the charge stack carries a correlation bid-ask.")
                : ChangeNote(label: "Correlation \(String(format: "%.2f", a.correlation)) → \(String(format: "%.2f", b.correlation))",
                             why: "Lower correlation means the names scatter, so the worst of them is worse. More dispersion means more downside sold, and the note is worth less as built.")
        }
        if a.crashCorrOn != b.crashCorrOn {
            return b.crashCorrOn
                ? ChangeNote(label: "Crash corr on",
                             why: "Pairwise ρ now rises as the basket trades down — ρ(z) = ρ + slope × max(1−z, 0) × 10, via a fresh Cholesky at each step. A desk uses a term/spot corr surface; this is a one-parameter cartoon. The effect is two-sided: a worst-of can cheapen (less dispersion in the left tail) while a weighted-basket KI gets more systematic left-tail variance.",
                             twoSided: true)
                : ChangeNote(label: "Crash corr off",
                             why: "Back to one equicorrelation for the whole path. The selloff spike is gone; the correlation bid-ask in the charge stack is once again the only corr adjustment.")
        }
        if moved(a.crashCorrSlope, b.crashCorrSlope) {
            return ChangeNote(
                label: "Crash-corr slope \(String(format: "%.2f", a.crashCorrSlope)) → \(String(format: "%.2f", b.crashCorrSlope)) per 10% drop",
                why: "Steeper spike means names couple harder exactly when the basket is down. Watch worst-of and weighted separately — they often move opposite ways. This is not a calibrated surface.",
                twoSided: true)
        }
        if a.markVol != b.markVol {
            let keys = Set(a.markVol.keys).union(b.markVol.keys).sorted()
            let t = keys.first { moved(a.atmVol(for: $0), b.atmVol(for: $0)) } ?? keys.first ?? b.members.first ?? "name"
            return ChangeNote(
                label: "\(t) ATM \(String(format: "%.1f", a.atmVol(for: t) * 100))% → \(String(format: "%.1f", b.atmVol(for: t) * 100))% (your snapshot)",
                why: "You overwrote the compiled catalog ATM. This is your snapshot, not a live implied, and it persists with the spec. The Monte Carlo uses this vol plus the parallel vol shift. Higher vol widens outcomes: a sold knock-in or buffer is usually worth less to you; owned optionality is the other way.",
                twoSided: true)
        }
        if a.markSpot != b.markSpot {
            let keys = Set(a.markSpot.keys).union(b.markSpot.keys).sorted()
            let t = keys.first { moved(a.displaySpot(for: $0), b.displaySpot(for: $0)) } ?? keys.first ?? b.members.first ?? "name"
            return ChangeNote(
                label: "\(t) spot \(String(format: "%.2f", a.displaySpot(for: t))) → \(String(format: "%.2f", b.displaySpot(for: t))) (your snapshot)",
                why: "Spot is display-only. Paths run in return space, so this number does not change the mark. ATM vol on the same card is the input that prices. Still your snapshot, not a live print.")
        }
        if moved(a.volShift, b.volShift) {
            return ChangeNote(
                label: "Vol shift \(String(format: "%+.0f", a.volShift * 100)) → \(String(format: "%+.0f", b.volShift * 100)) pts",
                why: "Volatility widens the distribution of outcomes. If you have sold a put — a buffer or a knock-in — extra vol makes it more valuable to the desk and so the note is worth less to you. On a fully protected growth note with no downside sold, extra vol works the other way, because you own optionality instead of having sold it.",
                twoSided: true)
        }
        if a.localVolOn != b.localVolOn {
            return b.localVolOn
                ? ChangeNote(label: "Local vol on",
                             why: "Volatility now rises as a name trades down — σ(x) = σ_ATM + slope × max(1−x, 0) × 10. Barriers and puts see a smile in the paths, not only as a charge after the fact. A desk Dupire surface is calibrated to listed options and is time-dependent; this is a one-parameter cartoon. The skew charge is switched off while this is on, so the smile is not counted twice.")
                : ChangeNote(label: "Local vol off",
                             why: "Back to one flat volatility per name. The smile, if you want it, is the skew charge in the stack rather than something the paths themselves know about.")
        }
        if moved(a.localVolSlope, b.localVolSlope) {
            return ChangeNote(
                label: "Local-vol slope \(String(format: "%.1f", a.localVolSlope * 100)) → \(String(format: "%.1f", b.localVolSlope * 100))v per 10% below spot",
                why: "Steeper downside leverage means more vol exactly where knock-ins live, so a barrier note is worth less to you and more to the desk. At-the-money and upside states are unchanged. This is not a calibrated surface — it is the same units as the skew charge, put into the SDE.")
        }

        // ---- tenor
        if moved(a.termYears, b.termYears, 1e-6) {
            func t(_ x: Double) -> String {
                let m = Int((x * 12).rounded())
                return m < 12 ? "\(m)m" : (m % 12 == 0 ? "\(m / 12)y" : "\(m / 12)y \(m % 12)m")
            }
            return ChangeNote(
                label: "Term \(t(a.termYears)) → \(t(b.termYears))",
                why: "A longer term pulls in three directions at once: par is discounted from further away, the barrier has more time to break, and there are more coupon periods to collect. The first two lower value and the third raises it. Which one wins depends on how rich the coupon is.",
                twoSided: true)
        }
        if a.averaging != b.averaging {
            return b.averaging == .none
                ? ChangeNote(label: "Asian tail off", why: "The final level is once again a single close, so the tail of the distribution is as wide as the market makes it.", twoSided: true)
                : ChangeNote(label: "Asian tail → \(b.averaging.rawValue)",
                             why: "Averaging the last fixings replaces one lucky or unlucky close with a mean, which shrinks the variance of the final level and cheapens the put you sold. Working against that, under positive drift the average of the last fixings sits slightly below the final close. The two effects nearly cancel, which is why the measured move is small and can go either way.",
                             twoSided: true)
        }

        // ---- coupon
        if a.coupon != b.coupon {
            switch b.coupon {
            case .none:
                return ChangeNote(label: "Coupon off", why: "The income leg is gone. Whatever is left — the discounted par payment and any upside — is all the note is worth.")
            case .guaranteed:
                return ChangeNote(label: "Coupon → guaranteed",
                                  why: "Guaranteed coupons pay in every scenario, so at the same headline rate they are worth strictly more than contingent ones. The barrier is the entire reason a contingent coupon can be quoted higher.")
            case .contingent:
                return ChangeNote(label: "Coupon → contingent",
                                  why: "Coupons now pay only when the underlying clears the barrier on an observation date. You have sold the issuer a ladder of digital options, one per date, and the money you gave up is what funds the higher headline rate.")
            }
        }
        if moved(a.couponRate, b.couponRate), !b.snowball {
            return ChangeNote(
                label: "Coupon rate \(p(a.couponRate, 2)) → \(p(b.couponRate, 2))",
                why: "This is the one lever that moves value in a straight line. Value changes by the rate change times the annuity factor Q on the math tab, and nothing else. If you want to know what a feature is worth, price it and then solve for the coupon change that offsets it.")
        }
        if a.couponObs != b.couponObs {
            return ChangeNote(
                label: "Coupon schedule → \(b.couponObs.rawValue)",
                why: "The schedule changes both timing and conditionality. More observations mean more chances to clear the barrier and get paid sooner, which helps. It also means more separate digital tests. A European coupon pays the full rate × tenor once at maturity — a 10% 3-year European is 30% at T, not a single 10% digital.",
                twoSided: true)
        }
        if moved(a.couponBarrier, b.couponBarrier) {
            return b.couponBarrier > a.couponBarrier
                ? ChangeNote(label: "Coupon barrier \(p(a.couponBarrier)) → \(p(b.couponBarrier))",
                             why: "A higher barrier is harder to clear, so more coupons are missed. Value falls at the same headline rate — the barrier is precisely what the client sells to get the rate up.")
                : ChangeNote(label: "Coupon barrier \(p(a.couponBarrier)) → \(p(b.couponBarrier))",
                             why: "A lower barrier is cleared more often, so more coupons actually get paid and the note is worth more at the same headline rate.")
        }
        if a.couponBarrierObs != b.couponBarrierObs {
            return b.couponBarrierObs == .dailyMonitored
                ? ChangeNote(label: "Coupon barrier → monthly closes + bridge",
                             why: "A close or a Brownian-bridge touch below the barrier at any point in the coupon period now kills that coupon — the same interpolation the KI daily setting uses. The same headline rate is worth less to you.")
                : ChangeNote(label: "Coupon barrier → payment-date observed",
                             why: "Only the level on the payment date matters now. Intra-period touches are forgiven, so coupons are easier to earn.")
        }
        if a.memory != b.memory {
            return b.memory
                ? ChangeNote(label: "Memory on",
                             why: "Missed coupons are banked and paid on the next observation that clears the barrier. That is a real client benefit, so it costs value at the same rate. For the desk it turns a row of independent digitals into a chained one, which is harder to hedge.")
                : ChangeNote(label: "Memory off", why: "A missed coupon is now gone for good, which is cheaper for the issuer and worth less to you.")
        }

        // ---- callability
        if a.call != b.call {
            switch b.call {
            case .none:
                return ChangeNote(label: "Call off", why: "The note is now a bullet — it runs to maturity no matter what. You keep the coupon-rich scenarios that a call would have taken away, so the note is worth more as built.")
            case .autocall:
                return ChangeNote(label: "Autocall on",
                                  why: "The note now redeems early whenever the underlying is at or above the trigger on an observation date. Notice which scenarios that removes: the healthy ones, where you were happily collecting coupons. You keep the bad paths and lose the good ones, which is why value falls and why callables quote higher coupons than bullets.")
            case .issuerCall:
                return ChangeNote(label: "Issuer call on",
                                  why: "The bank decides when to call. Exercise is a small Longstaff–Schwartz regression on (1, z, z², knocked) — the issuer redeems when fitted continuation exceeds par plus any call premium. That is the right economics and a cartoon of a desk LSMC, not a production exercise boundary.")
            }
        }
        if a.callObs != b.callObs {
            return ChangeNote(label: "Call schedule → \(b.callObs.rawValue)",
                              why: "More call dates mean more chances for the note to be taken away, so expected life shortens and fewer coupons get collected. Check the called-by distribution on the Note tab and watch the mass move earlier.")
        }
        if moved(a.callTrigger, b.callTrigger) {
            return b.callTrigger > a.callTrigger
                ? ChangeNote(label: "Autocall trigger \(p(a.callTrigger)) → \(p(b.callTrigger))",
                             why: "A higher trigger is harder to reach, so the note survives longer and collects more coupons before it is called away. Value rises.")
                : ChangeNote(label: "Autocall trigger \(p(a.callTrigger)) → \(p(b.callTrigger))",
                             why: "A lower trigger is reached more easily, so the note is called sooner and you collect fewer coupons. Value falls.")
        }
        if moved(a.triggerStep, b.triggerStep) {
            return ChangeNote(
                label: "Trigger step-down \(String(format: "%.1f", a.triggerStep * 100)) → \(String(format: "%.1f", b.triggerStep * 100))%/yr",
                why: "Later triggers now sit lower, so calls come easier as the note ages. That cuts the tail — the note tends to redeem before trouble — but it also truncates coupon collection. These two effects are close in size, so this lever is genuinely two-sided. Watch the measured number rather than trusting intuition.",
                twoSided: true)
        }
        if moved(a.callPremium, b.callPremium) {
            return ChangeNote(
                label: "Call premium \(p(a.callPremium, 2)) → \(p(b.callPremium, 2))",
                why: "Cash paid on top of par, but only if the note is actually called. Value rises by roughly the premium times the expected discounted time to call, and you get nothing at all from this feature if the note runs to maturity.")
        }
        if moved(a.nonCallMonths, b.nonCallMonths, 0.4) {
            return b.nonCallMonths > a.nonCallMonths
                ? ChangeNote(label: "Non-call \(Int(a.nonCallMonths))m → \(Int(b.nonCallMonths))m",
                             why: "The note cannot be taken away during the lockout, so those coupon periods are locked in for you. Value rises.")
                : ChangeNote(label: "Non-call \(Int(a.nonCallMonths))m → \(Int(b.nonCallMonths))m",
                             why: "A shorter lockout means the note can be called sooner, so fewer coupons are guaranteed. Value falls.")
        }
        if a.snowball != b.snowball {
            return b.snowball
                ? ChangeNote(label: "Snowball on",
                             why: "Coupons stop paying as they go and instead accrue, paying in one sum when the note is called. The money arrives later and is conditional on a call happening, so at the same rate it is worth less to you — which is exactly why snowball rates are quoted higher than periodic ones.")
                : ChangeNote(label: "Snowball off", why: "Coupons pay as they are earned again rather than accruing to the call date, so the cash arrives sooner and is less conditional.")
        }
        if moved(a.snowballRate, b.snowballRate) {
            return ChangeNote(label: "Snowball rate \(p(a.snowballRate, 2)) → \(p(b.snowballRate, 2))",
                              why: "The accrual rate is its own dial, separate from the periodic coupon rate. Value rises with it, scaled by the expected discounted time to call.")
        }
        if a.lockIn != b.lockIn {
            return b.lockIn
                ? ChangeNote(label: "Lock-in on",
                             why: "Touch the lock level on an observation date and principal protection locks in permanently — the barrier can never hurt you afterwards. This is a large client benefit and value often jumps above par, which is the app telling you that the other terms would have to be re-levered before anyone could issue it.")
                : ChangeNote(label: "Lock-in off", why: "Protection can no longer be locked, so the barrier stays live for the whole term.")
        }
        if moved(a.lockLevel, b.lockLevel) {
            return b.lockLevel > a.lockLevel
                ? ChangeNote(label: "Lock level \(p(a.lockLevel)) → \(p(b.lockLevel))", why: "A higher lock level is harder to touch, so protection locks in less often and the feature is worth less to you.")
                : ChangeNote(label: "Lock level \(p(a.lockLevel)) → \(p(b.lockLevel))", why: "A lower lock level is touched more easily, so protection locks in more often and the feature is worth more.")
        }

        // ---- upside
        if a.upside != b.upside {
            switch b.upside {
            case .none:
                return ChangeNote(label: "Upside off", why: "No participation leg. At maturity you get par back, adjusted for whatever downside you sold, plus any coupons — nothing for the market being higher.")
            case .linear:
                return ChangeNote(label: "Upside → linear participation", why: "You now receive a share of any gain at maturity. This has to be paid for: expect to fund it with a cap, a thinner buffer, or a lower coupon.")
            case .digital:
                return ChangeNote(label: "Upside → digital", why: "A fixed payment if the final level clears the digital strike, and nothing extra above it. All-or-nothing at one level, which makes it cheap to buy and awkward to hedge.")
            case .digitalPlus:
                return ChangeNote(label: "Upside → digi-plus", why: "A fixed minimum if the strike is cleared, and leveraged participation once the gain exceeds that minimum. You get the better of the two rather than choosing.")
            case .absolute:
                return ChangeNote(label: "Upside → absolute (dual directional)", why: "Falls now become gains, down to the knock-out level. The client owns a down-and-out put on top of the usual upside — the payoff makes a V, and that peak at the knock-out is the whole point of the structure.")
            }
        }
        if moved(a.participation, b.participation) {
            return ChangeNote(label: "Participation \(p(a.participation)) → \(p(b.participation))",
                              why: "You keep more of any gain. Value moves in a straight line here: participation times the unit upside U printed on the math tab.")
        }
        if (a.cap == nil) != (b.cap == nil) {
            return b.cap == nil
                ? ChangeNote(label: "Cap removed", why: "The right tail is yours again, which is worth real money — expect the terms that the cap was funding to have to come down.")
                : ChangeNote(label: "Cap added", why: "You gave away the far upside. That is the classic funding source in growth notes: sell the tail you do not expect to reach, and buy a buffer or extra participation with the proceeds.")
        }
        if let ca = a.cap, let cb = b.cap, moved(ca, cb) {
            return cb > ca
                ? ChangeNote(label: "Cap \(p(ca - 1)) → \(p(cb - 1)) gain", why: "A higher cap leaves more of the upside with you, so the note is worth more.")
                : ChangeNote(label: "Cap \(p(ca - 1)) → \(p(cb - 1)) gain", why: "A tighter cap gives away more of the upside, which is what funds whatever else you just asked for.")
        }
        if moved(a.digital, b.digital) {
            return ChangeNote(label: "Digital level \(p(a.digital)) → \(p(b.digital))",
                              why: "The fixed payment if the strike is cleared. Value moves with it, scaled by the discounted probability of finishing above the strike.")
        }
        if moved(a.digitalStrike, b.digitalStrike) {
            return b.digitalStrike < a.digitalStrike
                ? ChangeNote(label: "Digital strike \(p(a.digitalStrike)) → \(p(b.digitalStrike))",
                             why: "The digital now pays even with the market down to that level. Struck below 100% it is in the money, so it pays in far more scenarios and is worth much more. This is how a buffered digital note is built.")
                : ChangeNote(label: "Digital strike \(p(a.digitalStrike)) → \(p(b.digitalStrike))",
                             why: "A higher strike means the digital pays in fewer scenarios, so it is worth less.")
        }
        if moved(a.digiPlusLeverage, b.digiPlusLeverage) {
            return ChangeNote(label: "Digi-plus leverage \(String(format: "%.2f", a.digiPlusLeverage))× → \(String(format: "%.2f", b.digiPlusLeverage))×",
                              why: "Leverage applies to gains above the digital, so you are adding calls on top of the fixed payment. Value rises with it.")
        }
        if moved(a.absoluteKO, b.absoluteKO) {
            return b.absoluteKO < a.absoluteKO
                ? ChangeNote(label: "Absolute knock-out \(p(a.absoluteKO)) → \(p(b.absoluteKO))",
                             why: "A lower knock-out widens the band in which falls become gains, so more of the payoff belongs to you and the note is worth more. The peak of the V sits at the knock-out level.")
                : ChangeNote(label: "Absolute knock-out \(p(a.absoluteKO)) → \(p(b.absoluteKO))",
                             why: "A higher knock-out narrows the dual-directional zone, so the feature pays in fewer scenarios and is worth less.")
        }
        if moved(a.absParticipation, b.absParticipation) {
            return ChangeNote(label: "Absolute participation \(p(a.absParticipation)) → \(p(b.absParticipation))",
                              why: "How much of a fall is converted into gain inside the dual-directional band. Most prints leave this at 100% and lever the upside side instead.")
        }

        // ---- downside
        if a.downside != b.downside {
            switch b.downside {
            case .par:
                return ChangeNote(label: "Downside → full protection",
                                  why: "You are no longer selling anything. Every feature now has to be funded out of the funding leg alone, which is why fully protected notes offer so much less. Turn this on and off to see the whole economics of the product in one move.")
            case .buffer:
                return ChangeNote(label: "Downside → buffer",
                                  why: "The first slice of any decline is absorbed, and losses start from the buffer strike. You have sold a put struck at that level, and its premium is what funds the coupon or participation.")
            case .kiPut:
                return ChangeNote(label: "Downside → knock-in put",
                                  why: "Below the barrier your loss is measured from par rather than from the barrier, so protection disappears entirely instead of eroding gradually. That cliff is why a knock-in at a given level funds a much fatter coupon than a buffer at the same level.")
            }
        }
        if moved(a.protection, b.protection) {
            let name = b.downside == .buffer ? "Buffer strike" : "KI barrier"
            return b.protection > a.protection
                ? ChangeNote(label: "\(name) \(p(a.protection)) → \(p(b.protection))",
                             why: "The barrier is closer to today's level, so it breaks more often and the put you sold is bigger. Value falls at the same coupon — this is the trade every income note makes.")
                : ChangeNote(label: "\(name) \(p(a.protection)) → \(p(b.protection))",
                             why: "The barrier is further away, so it breaks less often and you have sold less. Value rises at the same coupon, which is why deeper barriers come with thinner coupons.")
        }
        if a.gearedBuffer != b.gearedBuffer {
            return b.gearedBuffer
                ? ChangeNote(label: "Geared buffer on",
                             why: "Below the strike you lose more than one point per point — the gearing is one divided by the strike, so a total loss becomes reachable. You have sold much more downside, so expect noticeably better headline terms in exchange.")
                : ChangeNote(label: "Geared buffer off", why: "Losses below the strike are now one for one, so the most you can lose is the strike itself.")
        }
        if moved(a.minRedemption, b.minRedemption) {
            return b.minRedemption > a.minRedemption
                ? ChangeNote(label: "Min redemption floor \(p(a.minRedemption)) → \(p(b.minRedemption))",
                             why: "You bought the tail back: losses now stop at the floor. The desk is left short a put spread instead of the whole tail, so value rises sharply — and the coupon that the full tail was funding has to come down with it.")
                : ChangeNote(label: "Min redemption floor \(p(a.minRedemption)) → \(p(b.minRedemption))",
                             why: "A lower floor leaves more of the tail sold, so the note is worth less to you and more to the issuer.")
        }
        if a.secondChance != b.secondChance {
            return b.secondChance
                ? ChangeNote(label: "Second chance on",
                             why: "A barrier that has already broken is forgiven if the final level recovers above the second-chance level. It pulls a monitored knock back toward a European one, which hands back most of the monitoring penalty. Pair it with a monitored barrier to see the effect clearly.")
                : ChangeNote(label: "Second chance off", why: "Once the barrier breaks it stays broken, however strongly the market recovers.")
        }
        if moved(a.secondChanceLevel, b.secondChanceLevel) {
            return ChangeNote(label: "Second-chance level \(p(a.secondChanceLevel)) → \(p(b.secondChanceLevel))",
                              why: "The recovery level that forgives a breach. Lower is easier to reach, so the forgiveness is worth more.")
        }
        if a.protObs != b.protObs {
            return ChangeNote(
                label: "Protection observation → \(b.protObs.rawValue)",
                why: "This is the most under-read line on a term sheet. European looks once, at maturity. Monitored looks on a schedule and the breach sticks. Monthly closes + bridge also counts interpolated hits between those closes — not a 252-day fixings grid. The same barrier level can price points apart depending only on how it is watched.")
        }

        // ---- rates and funding
        if moved(a.ust3m, b.ust3m) || moved(a.ust1y, b.ust1y) || moved(a.ust2y, b.ust2y)
            || moved(a.ust3y, b.ust3y) || moved(a.ust5y, b.ust5y) || moved(a.ust7y, b.ust7y) {
            return ChangeNote(
                label: "Treasury curve reshaped",
                why: "The curve does two jobs at once. It discounts every cash flow at the rate for that flow's own date, and it sets the forward the paths drift along. Higher rates make the par payment worth less today but push the forward up, which helps upside legs and hurts barriers. Short, high-call-probability structures read the front end; long bullets read the back.",
                twoSided: true)
        }
        if moved(a.spreadShort, b.spreadShort) || moved(a.spreadLong, b.spreadLong) {
            let wider = (b.spreadShort + b.spreadLong) > (a.spreadShort + a.spreadLong)
            return ChangeNote(
                label: wider ? "Funding spread widened" : "Funding spread tightened",
                why: wider
                    ? "A wider credit spread means the issuer's bond leg costs less to deliver today, which leaves more money to spend on coupons and participation. This funding advantage is a large part of why banks issue notes at all — and it is also why a note is an unsecured claim on the bank, not on the index."
                    : "A tighter spread makes the bond leg more expensive to deliver, leaving less to spend on features. Everything else equal, better issuer credit means worse headline terms.")
        }

        // ---- charges
        if a.chargesOn != b.chargesOn {
            return b.chargesOn
                ? ChangeNote(label: "Charges on",
                             why: "You are now looking at both numbers: the model mid and the dealer offer. The gap between them is not a markup — it is the cost of hedging the things a flat-vol model cannot replicate. That gap is what becomes the estimated value on a term sheet.")
                : ChangeNote(label: "Charges off", why: "Back to the model mid — a frictionless price that no desk can actually trade at.")
        }
        if moved(a.skewSlope, b.skewSlope) {
            return ChangeNote(label: "Skew charge \(String(format: "%.1f", a.skewSlope * 100)) → \(String(format: "%.1f", b.skewSlope * 100))v",
                              why: "The model prices every option at one flat volatility, but a put struck at 60% trades several points above at-the-money vol. This reprices the downside leg at its own strike vol, and on income notes it is usually the largest single charge in the stack.")
        }
        if moved(a.barrierShift, b.barrierShift) {
            return ChangeNote(label: "Overhedge shift \(p(a.barrierShift, 2)) → \(p(b.barrierShift, 2))",
                              why: "No desk can replicate a barrier or a digital exactly — you hedge a shifted version and live with the difference. The width of the shift is simultaneously the hedge and the charge, which is why this lever also shows up as the width of the option spreads in the desk book.")
        }
        if moved(a.corrBA, b.corrBA) {
            return ChangeNote(label: "Correlation bid-ask ±\(String(format: "%.2f", a.corrBA)) → ±\(String(format: "%.2f", b.corrBA))",
                              why: "There is no listed instrument that hedges correlation cleanly, so the desk quotes off the adverse side of a band. Widen it and single-underlier notes do not move at all, while worst-of baskets sag — that difference is the entire correlation exposure made visible.")
        }
        if moved(a.volBA, b.volBA) {
            return ChangeNote(label: "Vol bid-ask \(String(format: "%.1f", a.volBA * 100)) → \(String(format: "%.1f", b.volBA * 100))v",
                              why: "The spread the desk pays to trade vega, charged against the note's own vega. Structures with little vol exposure barely notice it.")
        }
        if moved(a.reserveBps, b.reserveBps, 0.4) {
            return ChangeNote(label: "Model reserve \(Int(a.reserveBps)) → \(Int(b.reserveBps))bp",
                              why: "A flat allowance for rebalancing costs, gap risk, and model error. Honest bookkeeping: real hedging costs that nobody can compute precisely still have to be paid for.")
        }
        if moved(a.ufFee, b.ufFee) {
            return ChangeNote(label: "UF \(p(a.ufFee, 2)) → \(p(b.ufFee, 2))",
                              why: "The selling concession to the advisor and wholesaler. Notice that the model value does not move at all — UF comes out of the issuer's proceeds, not out of the option package. That is why it appears below the dealer offer in the build-up rather than above it.")
        }
        return nil
    }

    // MARK: lessons

    private static func build(_ mutate: (inout Instrument) -> Void) -> Instrument {
        var s = Instrument.initial
        mutate(&s)
        return s
    }

    public static let lessons: [Lesson] = [
        Lesson(number: 1,
               title: "What a note is before any features",
               goal: "See the raw material: a zero-coupon bond issued by a bank.",
               steps: ["Everything is switched off — one index, three years, nothing else.",
                       "Read the model value, then read the vs-par line beneath it."],
               notice: "Value lands well below par. That gap is three years of the issuer's funding rate, discounted back — and it is the entire budget available to buy features. Every structured note is this bond plus a package of options bought with the difference.",
               spec: build { _ in }),

        Lesson(number: 2,
               title: "Where the coupon comes from",
               goal: "Learn that features are not free — they are purchases.",
               steps: ["A single volatile name, three years, a 10.5% guaranteed coupon, and nothing sold against it.",
                       "Read the value, then find the coupon strip in the trader decomposition."],
               notice: "The value is far above par, which means no issuer on earth could sell this note. You are asking for a coupon strip worth more than the funding budget that pays for it. The coupon has to be paid for, and the only things you own that are worth selling are your upside and your downside.",
               spec: build { s in
                   s.members = ["NVDA"]
                   s.coupon = .guaranteed; s.couponRate = 0.105; s.couponObs = .quarterly
               }),

        Lesson(number: 3,
               title: "Selling the downside pays for it",
               goal: "Watch a knock-in put turn an impossible note into a real one.",
               steps: ["Lesson 2's exact build, with one thing added: a 60% knock-in put.",
                       "Compare the value with Lesson 2, then read the downside leg in the decomposition.",
                       "Now switch the underlying to SPX and watch what happens to the same barrier."],
               notice: "The value falls by about the size of that coupon overpay and lands near par — this note can actually be issued. That drop is the market price of your downside, and it is precisely what bought the coupon. Then swap in a low-volatility index and the same 60% barrier is suddenly worth almost nothing, so the note flies back above par. That is why the street writes income notes on volatile names and on worst-of baskets rather than on a single broad index: a barrier only funds a coupon if it might actually be reached.",
               spec: build { s in
                   s.members = ["NVDA"]
                   s.coupon = .guaranteed; s.couponRate = 0.105; s.couponObs = .quarterly
                   s.downside = .kiPut; s.protection = 0.60
               }),

        Lesson(number: 4,
               title: "Correlation is the coupon",
               goal: "Understand why worst-of baskets dominate the income market.",
               steps: ["A worst-of on three indices, contingent coupon, 70/60 barriers.",
                       "In the Underlying block, switch the basket from worst-of to weighted.",
                       "Switch it back, then drag correlation from 0.75 down to 0.40."],
               notice: "Weighted is worth several points more than worst-of on identical terms, and lowering correlation moves the same lever again. Nothing about the coupon or the barrier changed — only how many ways there are to be unlucky. This single comparison explains most of the income tape.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]; s.correlation = 0.75
                   s.coupon = .contingent; s.couponRate = 0.10; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.downside = .kiPut; s.protection = 0.60
               }),

        Lesson(number: 5,
               title: "The same barrier, three different prices",
               goal: "Learn that how a barrier is watched matters as much as where it sits.",
               steps: ["A 60% knock-in, observed at maturity only (European).",
                       "In the Downside block, change protection observation to monthly, then to daily.",
                       "Leave the barrier level untouched the whole time."],
               notice: "Three materially different values from one unchanged headline number. Monitoring adds every observation date as a chance to break; the daily setting is monthly closes plus a Brownian-bridge correction for touches between them — not a 252-day grid. When a term sheet says '60% barrier', the observation line is half the story.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]
                   s.coupon = .contingent; s.couponRate = 0.11; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.downside = .kiPut; s.protection = 0.60; s.protObs = .european
               }),

        Lesson(number: 6,
               title: "An autocall sells your good scenarios",
               goal: "See why callable notes pay more than bullets.",
               steps: ["Start from the bullet: coupons, barrier, no call.",
                       "Turn the Callability block on, then raise the trigger from 100% to 110%.",
                       "Open the called-by distribution on the Note tab."],
               notice: "Adding the call lowers value, and raising the trigger wins some of it back. The call removes exactly the healthy paths where you were happily collecting coupons, while leaving every bad path intact. You keep the losses and sell the wins, and the extra coupon is your payment for that.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]
                   s.coupon = .contingent; s.couponRate = 0.11; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.downside = .kiPut; s.protection = 0.60
               }),

        Lesson(number: 7,
               title: "Growth notes: the cap pays for the buffer",
               goal: "Read the funding trade inside a buffered growth note.",
               steps: ["Two-year SPX, 150% participation, a 10% buffer, and no cap.",
                       "Read the value — it sits above par, so as built it cannot be issued.",
                       "Add the cap. It arrives at +30%, which overshoots slightly, so drag it up until the value sits at par."],
               notice: "The cap level that lands you exactly at par is the honest answer to the question 'what does this buffer cost?'. Growth notes are almost always this one trade: sell a piece of the upside you do not expect to reach, and buy protection you might actually need. Drag the cap tighter and you can pay for a deeper buffer instead.",
               spec: build { s in
                   s.members = ["SPX"]; s.termYears = 2
                   s.upside = .linear; s.participation = 1.5; s.cap = nil
                   s.downside = .buffer; s.protection = 0.90
               }),

        Lesson(number: 8,
               title: "Dual directional: gains from a falling market",
               goal: "Understand a three-regime payoff and where its peak sits.",
               steps: ["Four-year SPX, absolute return down to an 80% knock-out, 60% knock-in below.",
                       "Study the maturity profile chart before reading anything else.",
                       "Then drag the knock-out from 80% down to 65%."],
               notice: "The payoff is three regimes, not a clean V: gains above par, a par shelf between the 60% knock-in and the 80% knock-out, then gains again down to the knock-out, then the KI cliff. The peak sits at the knock-out, and widening the band raises the value because more of the distribution pays you. Clients hear 'gains either way' — the knock-out is the fine print that limits it, and the shelf is the stretch where you just get par back.",
               spec: build { s in
                   s.members = ["SPX"]; s.termYears = 4
                   s.upside = .absolute; s.participation = 1.0
                   s.absoluteKO = 0.80; s.absParticipation = 1.0
                   s.downside = .kiPut; s.protection = 0.60
               }),

        Lesson(number: 9,
               title: "From model mid to the term sheet",
               goal: "Learn what the estimated-value gap actually is.",
               steps: ["A standard income note with the Charges block on.",
                       "Read the dealer offer build-up line by line on the Note tab.",
                       "Turn the skew charge to zero, then put it back."],
               notice: "The largest charge is skew — the model prices a 60% put at at-the-money vol, which is simply wrong, and the correction is worth points. The gap between mid and offer is not a markup: it is the cost of hedging what cannot be replicated, plus the distribution fee below it.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]
                   s.coupon = .contingent; s.couponRate = 0.11; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.call = .autocall; s.callObs = .quarterly; s.nonCallMonths = 6
                   s.downside = .kiPut; s.protection = 0.60
                   s.chargesOn = true
               }),

        Lesson(number: 10,
               title: "Funding is a curve, not a rate",
               goal: "See why the shape of the curve changes which structures work.",
               steps: ["A short reverse convertible on a single name, no call.",
                       "Drag the front of the Treasury curve up by 50 basis points.",
                       "Now set the term to seven years and drag the front end again."],
               notice: "The short note moves about twice as much as the long one on the same front-end shift, and the long one is far more sensitive to the back of the curve instead. Cash flows discount at their own dates, so a structure that pays back early lives on the front end. This is why on an issuance desk the call probability and the shape of the curve are the same conversation — and note that the seven-year version prices far above par, which tells you a 12% coupon for seven years is nowhere near fundable.",
               spec: build { s in
                   s.members = ["NVDA"]; s.termYears = 1.5
                   s.coupon = .guaranteed; s.couponRate = 0.12; s.couponObs = .quarterly
                   s.downside = .kiPut; s.protection = 0.65
               }),

        Lesson(number: 11,
               title: "Where the risk actually sits",
               goal: "Read a hedge sheet the way the issuing desk reads it.",
               steps: ["A worst-of on three single names with very different volatilities.",
                       "Open the Risk tab and read the per-underlying hedge sheet.",
                       "Compare each name's delta and vega against the others."],
               notice: "The risk is nowhere near evenly spread. The two volatile names carry the overwhelming majority of the vega and the low-volatility name barely registers — roughly a tenth of the total. The worst performer is almost always one of the two volatile names, so a client who was sold a basket of three actually owns a bet on two. A single aggregate delta hides that completely, which is exactly why a desk hedges name by name.",
               spec: build { s in
                   s.members = ["NVDA", "MSFT", "TSLA"]; s.correlation = 0.55
                   s.coupon = .contingent; s.couponRate = 0.16; s.couponObs = .monthly
                   s.couponBarrier = 0.70; s.memory = true
                   s.call = .autocall; s.callObs = .monthly; s.nonCallMonths = 3
                   s.downside = .kiPut; s.protection = 0.55
               }),

        Lesson(number: 12,
               title: "Issuer call is not autocall at 100%",
               goal: "See the difference between a forced 100% trigger and a small Longstaff–Schwartz exercise.",
               steps: ["A three-name income note with issuer call, quarterly after a 6-month lockout.",
                       "Read expected life and the called-by chart — this is the LS fit, not a contractual trigger.",
                       "Switch Callability to Autocall and leave the trigger at 100%. Compare expected life and value."],
               notice: "Autocall at 100% redeems every path that prints at or above par on an observation. Issuer call lets the bank keep cheap funding when the note is still a good deal for them, and only pull it when continuation is worth more than redemption. The model here is a four-regressor Longstaff–Schwartz (1, z, z², knocked) — a cartoon of that idea, not a desk LSMC. The autocall-at-100% number is a holder-unfriendly bound, not the contract.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]
                   s.coupon = .contingent; s.couponRate = 0.11; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.call = .issuerCall; s.callObs = .quarterly; s.nonCallMonths = 6
                   s.downside = .kiPut; s.protection = 0.60
               }),

        Lesson(number: 13,
               title: "A smile in the paths, not only a charge",
               goal: "Compare a flat-vol knock-in plus skew charge with a local-vol smile inside the Monte Carlo.",
               steps: ["A single-name 60% knock-in with Charges on and local vol off. Read the skew line in the offer build-up.",
                       "Turn local vol on in Underlying. The skew charge goes to zero — the smile is now in the paths.",
                       "Turn local vol back off and drag the skew slope. Do not run both: the engine already refuses to double-count."],
               notice: "The skew charge reprices the downside leg at strike vol after a flat-vol Monte Carlo. Local vol puts the same slope into σ(x) so the barrier can actually be hit more often. A desk Dupire surface is calibrated to listed options and depends on time; this is a one-parameter cartoon, default off. The two answers will not match to a point — they are two different ways of admitting the wing exists.",
               spec: build { s in
                   s.members = ["NVDA"]
                   s.coupon = .guaranteed; s.couponRate = 0.105; s.couponObs = .quarterly
                   s.downside = .kiPut; s.protection = 0.60
                   s.chargesOn = true
               }),

        Lesson(number: 14,
               title: "Crash corr is two-sided: worst-of vs weighted",
               goal: "Watch a selloff spike in ρ move a worst-of KI and a weighted KI in opposite directions.",
               steps: ["A three-index 70/60 income note, worst-of, one ρ. Turn crash corr on and read the value.",
                       "Switch the basket from worst-of to weighted. Leave the spike on.",
                       "Turn crash corr off and on again on the weighted build, then switch back to worst-of."],
               notice: "A worst-of holder is long correlation: when names couple in a crash there is less dispersion, so the worst is less bad and the KI you sold can cheapen. A weighted basket's variance rises with ρ, so the same spike fattens the left tail and the KI gets more expensive. One ρ cannot show that. This spike is a one-parameter cartoon (per-step Cholesky), not a desk term/spot corr surface. Default off.",
               spec: build { s in
                   s.members = ["SPX", "NDX", "RTY"]; s.correlation = 0.75
                   s.coupon = .contingent; s.couponRate = 0.10; s.couponObs = .quarterly
                   s.couponBarrier = 0.70
                   s.downside = .kiPut; s.protection = 0.60
               }),
    ]

    // MARK: what the Greeks mean for a note

    public static let greeks: [(String, String)] = [
        ("Mark", "What the note is worth today as a percentage of par. On the pricing date this is the model value; later in the note's life it is the mark a client sees on a statement, and it moves with the market rather than sitting at 100."),
        ("Delta", "How much the note's value moves for a 1% move in the underlying. The issuing desk trades the opposite of this to stay flat, and it re-trades after every observation date. Notice that delta is largest just above a barrier, not at the money — that is where the note's fate is most sensitive."),
        ("Gamma", "How fast delta itself changes. Short gamma means the hedge has to be sold as the market falls and bought as it rises, which is the uncomfortable direction. Income notes are typically short gamma near the barrier and the trigger, which is exactly why those two levels are the hard part of the book."),
        ("Vega", "Value change per one point of implied volatility. A holder who sold a knock-in put is short vega: rising vol makes the put they sold more valuable and their note worth less. The number is concentrated at the barrier strike, not spread evenly across strikes."),
        ("Correlation", "Value change per 0.05 of pairwise correlation, and only meaningful for baskets. Worst-of holders are long correlation and the desk is short it. There is no clean listed hedge, which is why it carries a bid-ask charge and why desks recycle it against dispersion books."),
        ("Funding DV", "Value change for 10 basis points of extra issuer credit spread. It is small per basis point and enormous in aggregate — the funding leg is the largest single component of most notes."),
        ("Theta (1m)", "What one month of the calendar passing is worth, with the terms frozen and the market unchanged. For an income note this is usually positive to the holder: coupons accrue and the barrier has less remaining time to break."),
    ]

    // MARK: glossary

    public static let glossary: [GlossaryTerm] = [
        .init(name: "Par",
              plain: "The face amount, usually $1,000 per note. Almost everything in the app is quoted as a percentage of it.",
              desk: "Value is expressed per $1 of par so structures of different sizes compare directly."),
        .init(name: "Model value",
              plain: "What the package of bond and options is actually worth today, before any of the desk's costs.",
              desk: "A frictionless mid. Nobody trades here; it is the starting point for the charge stack."),
        .init(name: "Estimated value",
              plain: "The number on the term sheet that sits below the $1,000 you paid. It is the dealer offer after charges.",
              desk: "Mid less skew, overhedge, correlation and vega bid-ask, and reserves. Distribution fees sit below that again."),
        .init(name: "Funding leg",
              plain: "The bond part of the note: the issuer's promise to repay, discounted at the bank's own borrowing rate.",
              desk: "z_f(t) = Treasury zero plus credit spread. Every flow discounts at its own tenor off that curve."),
        .init(name: "Contingent coupon",
              plain: "A coupon you receive only if the underlying is at or above the coupon barrier on the observation date.",
              desk: "A strip of digital options, one per observation. Pin risk on every date."),
        .init(name: "Coupon barrier",
              plain: "The level the underlying must hold for a contingent coupon to be paid.",
              desk: "The digital strike. Payment-date vs monthly-closes-plus-bridge observation changes the price; both KI daily and coupon daily-monitor use the same Brownian-bridge interpolation."),
        .init(name: "Memory",
              plain: "Missed coupons are remembered and paid later, on the first observation that clears the barrier.",
              desk: "Chains the digitals together instead of leaving them independent. Harder to hedge, worth more to the client."),
        .init(name: "Q (annuity factor)",
              plain: "The note's own discounted count of coupon payments. Multiply the coupon rate by Q to get the value of the whole income leg.",
              desk: "Q = E[Σ year-fraction × df at paid dates]. Because the model uses common random numbers, coupon leg = c × Q exactly."),
        .init(name: "Autocall",
              plain: "The note redeems early and automatically when the underlying is at or above the trigger on an observation date.",
              desk: "You are short the good scenarios. Negative gamma sits just under the trigger into each observation."),
        .init(name: "Issuer call",
              plain: "The bank chooses whether to redeem early. You do not.",
              desk: "Small Longstaff–Schwartz on (1, z, z², knocked). Issuer calls when fitted continuation exceeds redemption. A cartoon of optimal exercise — a desk uses more regressors, more paths, and a carefully chosen measure."),
        .init(name: "Step-down trigger",
              plain: "An autocall level that falls as the note ages, making early redemption progressively easier.",
              desk: "Truncates the tail and the coupon stream at once. Genuinely two-sided in value."),
        .init(name: "Snowball",
              plain: "Coupons accrue instead of paying, and arrive in one sum if and when the note is called.",
              desk: "Concentrates the income into a single conditional payment at the call date. Rates quote higher for the same reason."),
        .init(name: "Call premium",
              plain: "Extra cash on top of par, paid only if the note is called. Nothing if it runs to maturity.",
              desk: "Enlarges the digital at the trigger, which makes the pin harder to hedge."),
        .init(name: "Non-call period",
              plain: "An initial window in which the note cannot be redeemed early, so those coupons are locked in.",
              desk: "Lockout. Raises value because the early exits are removed from the front of the distribution."),
        .init(name: "Knock-in put (KI)",
              plain: "Once the underlying trades below the barrier, your downside protection disappears and losses are measured from par.",
              desk: "The cliff. Delta swells just above the barrier and collapses through it."),
        .init(name: "Buffer",
              plain: "The first slice of losses is absorbed. Below the buffer strike, you lose from that strike rather than from par.",
              desk: "A vanilla put struck at the buffer level. Erodes gradually, no discontinuity."),
        .init(name: "Geared buffer",
              plain: "Below the buffer you lose more than a point per point, so a total loss becomes possible.",
              desk: "Gearing is 1 divided by the strike. Sells materially more downside than a plain buffer at the same level."),
        .init(name: "Barrier observation",
              plain: "How often the barrier is checked: only at maturity, on a schedule, or monthly closes with a Brownian-bridge correction for touches between them.",
              desk: "European, monitored, or monthly+bridge. The same level prices points apart across the three."),
        .init(name: "Second chance",
              plain: "A barrier that already broke is forgiven if the final level recovers above a stated level.",
              desk: "Pulls an American knock back toward European. Recovers most of the monitoring penalty."),
        .init(name: "Lock-in",
              plain: "Touch a stated level on an observation date and your principal protection is locked in for good.",
              desk: "Kills the desk's long put on a good print. Often pushes value above par unless other terms are re-levered."),
        .init(name: "Worst-of",
              plain: "Every condition in the note reads the weakest of the underlyings, not the average.",
              desk: "Short correlation. More names or lower correlation make the worst worse, which is what funds the coupon."),
        .init(name: "Weighted basket",
              plain: "Conditions read a weighted average of the members, so one bad name is diluted by the others.",
              desk: "Long correlation relative to worst-of. Diversification cheapens the options, so terms are thinner."),
        .init(name: "Crash corr",
              plain: "Correlation that rises when the basket is down — names start moving together in a selloff.",
              desk: "Here a one-parameter spike, default off, per-step Cholesky. A desk uses a term/spot-dependent corr surface. Two-sided: worst-of vs weighted often move opposite ways. Not a quote."),
        .init(name: "Participation",
              plain: "The share of any gain that you receive at maturity. 150% participation pays one and a half times the rise.",
              desk: "Value is linear in it: upside leg = participation × unit upside U."),
        .init(name: "Cap",
              plain: "A ceiling on your upside. Gains above it are not yours.",
              desk: "The standard funding source in growth notes — sell the right tail, buy the buffer."),
        .init(name: "Digital",
              plain: "A fixed payment if the final level clears a strike, and nothing extra above it.",
              desk: "All-or-nothing at one level. Replicated as a tight call spread, which is where the overhedge comes from."),
        .init(name: "Absolute (dual directional)",
              plain: "Falls are converted into gains, down to a knock-out level. Below that the usual downside applies.",
              desk: "A down-and-out put owned by the client. The payoff peaks exactly at the knock-out."),
        .init(name: "Asian tail",
              plain: "The final level is an average of the last several daily closes rather than a single close.",
              desk: "Cuts terminal variance and terminal gamma. Slightly lowers the expected final level under positive drift."),
        .init(name: "Skew",
              plain: "Out-of-the-money puts trade at higher implied volatility than at-the-money options. A flat-volatility model misses this.",
              desk: "Default: reprice the downside leg at strike vol (the charge). Optional local vol puts the same slope into the paths instead. Do not run both."),
        .init(name: "Local vol",
              plain: "Volatility that changes with the level of the underlying — usually higher when the market is down.",
              desk: "Here a one-parameter leverage function, default off. A desk Dupire / local-vol surface is calibrated to the listed smile and depends on time. Treat the toggle as a way to see a barrier react to a smile, not as a quote."),
        .init(name: "Overhedge",
              plain: "A charge for the fact that barriers and digitals cannot be hedged exactly, only approximately.",
              desk: "Shift every discontinuity against the client and reprice. The shift width is both the hedge and the charge."),
        .init(name: "UF (selling concession)",
              plain: "The fee paid to the advisor and the wholesaler out of the issue proceeds.",
              desk: "Does not touch the model value at all. Sits below the dealer offer in the build-up, not above it."),
        .init(name: "Common random numbers",
              plain: "The model reuses one fixed set of random draws for every calculation, so differences between two builds are real rather than noise.",
              desk: "CRN. Makes charge and ledger differences clean, and keeps the leg identity exact."),
        .init(name: "Monte Carlo",
              plain: "The model simulates thousands of possible market paths and averages what the note would pay on each.",
              desk: "Risk-neutral GBM with a correlated Cholesky draw. Four thousand paths for the headline, fewer for the bumps."),
    ]

    // MARK: term-sheet translation

    /// Map the built structure to the language a client actually reads.
    public static func termSheet(_ s: Instrument, offer: Double?) -> [(String, String)] {
        func p(_ x: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f%%", x * 100) }
        var rows: [(String, String)] = []
        let names = s.members.joined(separator: ", ")
        rows.append(("Reference Asset\(s.members.count > 1 ? "s" : "")",
                     s.members.count > 1
                     ? "\(names) — payments read the \(s.basket == .worstOf ? "least performing" : "weighted average of the") reference asset\(s.basket == .worstOf ? "" : "s")"
                     : names))
        let m = Int((s.termYears * 12).rounded())
        rows.append(("Term", m < 12 ? "\(m) months" : (m % 12 == 0 ? "\(m / 12) years" : "\(m / 12) years \(m % 12) months")))
        if s.coupon != .none {
            let label = s.snowball ? "Accrued Coupon Rate" : (s.coupon == .contingent ? "Contingent Coupon Rate" : "Fixed Coupon Rate")
            rows.append((label, "\(p(s.snowball ? s.snowballRate : s.couponRate)) per annum, paid \(s.snowball ? "on the call date" : s.couponObs.rawValue.lowercased())"))
            if s.coupon == .contingent {
                rows.append(("Coupon Barrier", "\(p(s.couponBarrier, 0)) of Initial Level\(s.couponBarrierObs == .dailyMonitored ? ", observed continuously during the coupon period (monthly closes + Brownian-bridge hits)" : ", observed on each Coupon Observation Date")"))
            }
            if s.memory { rows.append(("Memory Feature", "Applicable — unpaid coupons are carried forward")) }
        }
        if s.call != .none {
            rows.append((s.call == .autocall ? "Automatic Call Level" : "Issuer Call",
                         s.call == .autocall
                         ? "\(p(s.callTrigger, 0)) of Initial\(s.triggerStep > 0 ? ", declining \(p(s.triggerStep, 1)) per annum" : ""), observed \(s.callObs.rawValue.lowercased()) after \(Int(s.nonCallMonths)) months"
                         : "At the Issuer's discretion on any Observation Date after \(Int(s.nonCallMonths)) months"))
            if s.callPremium > 0 {
                rows.append(("Call Premium", "\(p(s.callPremium)) per annum, payable only upon early redemption"))
            }
        }
        switch s.upside {
        case .none: break
        case .linear:
            rows.append(("Upside Participation", p(s.participation, 0) + (s.cap != nil ? ", subject to a Maximum Return of \(p((s.cap ?? 1.3) - 1, 0))" : ", uncapped")))
        case .digital:
            rows.append(("Digital Return", "\(p(s.digital, 0)) if the Final Level is at or above \(p(s.digitalStrike, 0)) of Initial"))
        case .digitalPlus:
            rows.append(("Digital Return", "\(p(s.digital, 0)) minimum if the Final Level is at or above \(p(s.digitalStrike, 0)), then \(String(format: "%.2f", s.digiPlusLeverage))× of the gain"))
        case .absolute:
            rows.append(("Absolute Return Feature", "Applicable between \(p(s.absoluteKO, 0)) and \(p(1.0, 0)) of Initial, at \(p(s.absParticipation, 0)) participation"))
        }
        switch s.downside {
        case .par:
            rows.append(("Principal at Risk", "No — full repayment of principal at maturity, subject to Issuer credit"))
        case .buffer:
            rows.append(("Buffer Level", "\(p(s.protection, 0)) of Initial\(s.gearedBuffer ? " — Downside Leverage Factor of \(String(format: "%.2f", 1 / s.protection))× applies below the Buffer" : "")"))
        case .kiPut:
            rows.append(("Downside Threshold", "\(p(s.protection, 0)) of Initial"))
            rows.append(("Barrier Observation", s.protObs == .european
                         ? "Final Valuation Date only"
                         : "\(s.protObs.rawValue) — a breach on any Observation Date is permanent"))
            if s.secondChance {
                rows.append(("Recovery Feature", "A breach is disregarded if the Final Level is at or above \(p(s.secondChanceLevel, 0))"))
            }
        }
        if s.minRedemption > 0 {
            rows.append(("Minimum Redemption", "\(p(s.minRedemption, 0)) of principal"))
        }
        if s.averaging != .none {
            rows.append(("Final Level", "Average of the closing levels on the final \(s.averaging.fixings) Trading Days"))
        }
        if s.lockIn {
            rows.append(("Lock-In Feature", "Principal repayment is secured once the Level closes at or above \(p(s.lockLevel, 0)) on any Observation Date"))
        }
        if let o = offer, s.chargesOn {
            rows.append(("Estimated Value on the Pricing Date",
                         "\(String(format: "$%.2f", o * 1000)) per $1,000 principal amount"))
            if s.ufFee > 0 {
                rows.append(("Underwriting Discount", "\(p(s.ufFee)) of principal"))
            }
        }
        rows.append(("Issuer Credit", "All payments are subject to the credit risk of the Issuer. These notes are unsecured obligations and are not deposits."))
        return rows
    }

    public static func termSheetPlain(_ s: Instrument, offer: Double?) -> String {
        var lines = ["STRUCTURED NOTE — term sheet (model)", ""]
        for (label, value) in termSheet(s, offer: offer) {
            lines.append("\(label): \(value)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Kept separate so the charges copy can be long without crowding the switch.
enum TeachCopy {
    static let chargesHelp = BlockHelp(
        what: "The bridge from a model mid to a price a desk could actually trade. Five costs: skew, overhedge, correlation bid-ask, vega bid-ask, and a flat reserve — then the selling concession below that. If local vol is on, skew is skipped so the smile is not charged twice.",
        moves: "Every charge lowers the offer. Skew is normally the largest on an income note, because a flat-volatility model badly underprices a deep out-of-the-money put. Correlation only bites when there is a basket.",
        watch: "Turn the whole block off and on to see the mid and the offer side by side. The difference is what becomes the estimated value on a term sheet — not a markup, but the cost of hedging what cannot be replicated.")
}
