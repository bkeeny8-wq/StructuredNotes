//  Components.swift
//  StructuredNotesDesk
//
//  Annotated-term-sheet look: paper surface, serif clause headers,
//  monospaced tabular figures, ledger-green / loss-red leg coloring.

import SwiftUI

enum Theme {
    static let paper = Color(red: 0.969, green: 0.965, blue: 0.945)
    static let ink = Color(red: 0.11, green: 0.125, blue: 0.115)
    static let rule = Color(red: 0.86, green: 0.855, blue: 0.82)
    static let bond = Color(red: 0.04, green: 0.42, blue: 0.30)
    static let opt = Color(red: 0.13, green: 0.35, blue: 0.62)
    static let loss = Color(red: 0.70, green: 0.23, blue: 0.18)
    static let amber = Color(red: 0.73, green: 0.50, blue: 0.09)
    static let fee = Color(red: 0.55, green: 0.53, blue: 0.46)
}

enum Fmt {
    static func pct(_ x: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f%%", x * 100) }
    static func bp(_ x: Double) -> String { String(format: "%.0fbp", x * 10000) }
    static func usd0(_ x: Double) -> String { "$" + String(format: "%.0f", x.rounded()) }
    static func yrs(_ x: Double) -> String { String(format: "%.1fy", x) }
}

/// Tappable "ⓘ" that expands into three short teaching paragraphs:
/// what the thing is, which way it moves value, and something to try.
struct HelpDisclosure: View {
    let help: BlockHelp
    @Binding var open: Bool
    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: open ? "info.circle.fill" : "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(open ? Theme.opt : Theme.fee)
        }
        .buttonStyle(.plain)
    }
}

struct HelpBody: View {
    let help: BlockHelp
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach([("WHAT IT IS", help.what),
                     ("WHICH WAY IT MOVES VALUE", help.moves),
                     ("TRY THIS", help.watch)], id: \.0) { head, body in
                if !body.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(head).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.opt)
                        Text(body).font(.system(size: 11.5)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.955, green: 0.965, blue: 0.98), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A compact inline "why this matters" expander, for a single control that
/// deserves more explanation than a caption can carry.
struct MiniHelp: View {
    let title: String
    let help: BlockHelp
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "questionmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(title).font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Theme.opt)
            }
            .buttonStyle(.plain)
            if open { HelpBody(help: help) }
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    var help: BlockHelp? = nil
    @ViewBuilder var content: Content
    @State private var helpOpen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                if let h = help { HelpDisclosure(help: h, open: $helpOpen) }
                Spacer(minLength: 0)
            }
            if helpOpen, let h = help { HelpBody(help: h) }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
    }
}

/// Unit descriptor that lets a LeverRow show and parse a typed value in its
/// natural units: display number = raw × scale + offset. Editing writes the
/// raw value straight back through the same binding the slider uses, so the
/// two stay in lockstep. Typed values are clamped to the row's range but not
/// snapped to its step — the whole point of typing is precision the slider
/// cannot reach.
struct LeverField: Equatable {
    var scale: Double = 1
    var offset: Double = 0
    var decimals: Int = 1
    var suffix: String = ""
    var signed: Bool = false

    func string(_ v: Double) -> String { String(format: "%.\(decimals)f", v * scale + offset) }
    func raw(from text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let d = Double(t) else { return nil }
        return (d - offset) / scale
    }

    static let pct    = LeverField(scale: 100,   decimals: 1, suffix: "%")
    static let pct0   = LeverField(scale: 100,   decimals: 0, suffix: "%")
    static let bp     = LeverField(scale: 10000, decimals: 0, suffix: "bp")
    static let bps    = LeverField(scale: 1,     decimals: 0, suffix: "bp")
    static let months = LeverField(scale: 1,     decimals: 0, suffix: "m")
    static let corr   = LeverField(scale: 1,     decimals: 2)
    static let mult   = LeverField(scale: 1,     decimals: 2, suffix: "×")
    static let volV   = LeverField(scale: 100,   decimals: 1, suffix: "v")
    static let volPts = LeverField(scale: 100,   decimals: 0, suffix: "pts", signed: true)
    static let stepPct = LeverField(scale: 100,  decimals: 0, suffix: "%/yr")
    static let capPct = LeverField(scale: 100, offset: -100, decimals: 0, suffix: "%")
}

/// Labeled slider with an optional inline type-in field. Pass `field` to make
/// the value editable (tap the number, type, Done/blur to commit); leave it
/// nil and the row shows the read-only `display` string as before.
struct LeverRow: View {
    let label: String
    var display: String = ""
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var field: LeverField? = nil

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if let f = field {
                    HStack(spacing: 1) {
                        TextField("", text: $draft)
                            .focused($focused)
                            .keyboardType(f.signed ? .numbersAndPunctuation : .decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.footnote.monospaced().weight(.semibold))
                            .foregroundStyle(focused ? Theme.opt : Theme.ink)
                            .frame(width: 62, alignment: .trailing)
                            .onSubmit { commit(f) }
                            .onChange(of: focused) { _, now in if !now { commit(f) } }
                            .toolbar {
                                if focused {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") { focused = false }
                                    }
                                }
                            }
                        if !f.suffix.isEmpty {
                            Text(f.suffix)
                                .font(.footnote.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(display).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(Theme.ink)
                }
            }
            Slider(value: $value, in: range, step: step).tint(Theme.ink)
        }
        .onAppear { if let f = field { draft = f.string(value) } }
        .onChange(of: value) { _, v in if !focused, let f = field { draft = f.string(v) } }
    }

    private func commit(_ f: LeverField) {
        if let r = f.raw(from: draft) {
            value = min(range.upperBound, max(range.lowerBound, r))
        }
        draft = f.string(value)   // normalize the text to what was actually stored
        focused = false
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var sub: String = ""
    var color: Color = Theme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(value)
            .lineLimit(1)
            .minimumScaleFactor(0.55).font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(color)
            if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.rule))
    }
}

struct StackSeg: Identifiable {
    var id: String { name }
    let name: String
    let frac: Double
    let color: Color
}

/// Signature element: how $1,000 of par carves into legs, live.
struct CapitalStack: View {
    let segs: [StackSeg]
    let notional: Double
    var body: some View {
        let visible = segs.filter { $0.frac > 0.004 }
        let sum = visible.reduce(0.0) { $0 + $1.frac }
        let scale = max(sum, 1e-9)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(visible) { s in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(s.color.opacity(0.16))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(s.color).lineLimit(1)
                                Text(Fmt.usd0(s.frac * notional))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(s.color)
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(width: max(34, geo.size.width * CGFloat(s.frac / scale)))
                        .clipped()
                    }
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule))
            HStack {
                Text("$0"); Spacer()
                Text(sum > 1.002 ? "Value = " + Fmt.usd0(sum * notional) : "Par = " + Fmt.usd0(notional))
            }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

struct ChipToggle: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? Theme.ink : Color.white, in: Capsule())
            .foregroundStyle(on ? Color.white : Theme.ink)
            .overlay(Capsule().stroke(on ? Theme.ink : Theme.rule))
        }
        .buttonStyle(.plain)
    }
}

struct ChoiceChips<T: Hashable>: View {
    let options: [(T, String)]
    let selection: T
    let pick: (T) -> Void
    var body: some View {
        HStack(spacing: 5) {
            ForEach(options, id: \.0) { opt in
                Button { pick(opt.0) } label: {
                    Text(opt.1).font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(selection == opt.0 ? Theme.ink : Color.white, in: Capsule())
                        .foregroundStyle(selection == opt.0 ? Color.white : Theme.ink)
                        .overlay(Capsule().stroke(selection == opt.0 ? Theme.ink : Theme.rule))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LegRow: View {
    let label: String
    let value: String
    var color: Color = Theme.ink
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, 5)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.rule), alignment: .bottom)
    }
}

/// A builder section with an on/off switch in the header. Off shows a hint;
/// on reveals the section's features.
struct BlockCard<Content: View>: View {
    let title: String
    let on: Bool
    let toggle: () -> Void
    var offHint: String = "Off"
    var help: BlockHelp? = nil
    @ViewBuilder var content: Content
    @State private var helpOpen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                if let h = help { HelpDisclosure(help: h, open: $helpOpen) }
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() }))
                    .labelsHidden()
                    .tint(Theme.bond)
            }
            if helpOpen, let h = help { HelpBody(help: h) }
            if on {
                content
            } else {
                Text(offHint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
    }
}

enum OutputTab: String, CaseIterable, Identifiable {
    case note = "Note", risk = "Risk", math = "The math", learn = "Learn"
    var id: String { rawValue }
}

/// Capsule pill selector for the output column.
struct PillSelector: View {
    @Binding var tab: OutputTab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(OutputTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 13, weight: tab == t ? .bold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(tab == t ? Theme.ink : .clear, in: Capsule())
                        .foregroundStyle(tab == t ? .white : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(red: 0.93, green: 0.92, blue: 0.89), in: Capsule())
    }
}
