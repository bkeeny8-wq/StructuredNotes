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

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
    }
}

struct LeverRow: View {
    let label: String
    let display: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Slider(value: $value, in: range, step: step).tint(Theme.ink)
        }
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
            Text(value).font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(color)
            if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.rule))
    }
}

struct StackSeg: Identifiable {
    let id = UUID()
    let name: String
    let frac: Double
    let color: Color
}

/// Signature element: how $1,000 of par carves into legs, live.
struct CapitalStack: View {
    let segs: [StackSeg]
    let notional: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segs.filter { $0.frac > 0.004 }) { s in
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
                        .frame(width: max(34, geo.size.width * s.frac))
                        .clipped()
                    }
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule))
            HStack {
                Text("$0"); Spacer(); Text("Par = " + Fmt.usd0(notional))
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
