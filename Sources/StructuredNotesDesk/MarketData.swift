//  MarketData.swift
//  Structured Notes
//
//  Snapshot: indices ≈ Jul 20 2026 close, stocks/ETFs Jul 21 2026 close.
//  Underlier menu is data-driven: the tape's #1 worst-of basket, top three
//  single names, and top two ETFs. Replace with a live feed for production.

import Foundation

public struct Asset: Hashable, Sendable {
    public let name: String
    public let ticker: String
    public let spot: Double
    public let vol: Double        // 30-day proxy or flagged analyst assumption
    public let div: Double
    public let source: String

    public init(name: String, ticker: String, spot: Double, vol: Double, div: Double, source: String) {
        self.name = name
        self.ticker = ticker
        self.spot = spot
        self.vol = vol
        self.div = div
        self.source = source
    }
}

public enum Market {
    public static let asOf = "indices Jul 20 · stocks/ETFs Jul 21 2026 close"
    /// ^TNX ~4.60% (Yahoo Finance). Substitute the term-matched tenor.
    public static let ust = 0.046

    public static let spx = Asset(name: "S&P 500", ticker: "SPX", spot: 7478, vol: 0.184, div: 0.0105,
                           source: "Spot Yahoo · VIX 18.4 Cboe · yld Multpl")
    public static let ndx = Asset(name: "Nasdaq-100", ticker: "NDX", spot: 28604, vol: 0.285, div: 0.0060,
                           source: "Spot Yahoo · VXN 28.5 · QQQ yld")
    public static let rty = Asset(name: "Russell 2000", ticker: "RTY", spot: 2942, vol: 0.230, div: 0.0120,
                           source: "Spot Yahoo · vol/div ASSUMPTION (use RVX)")
    public static let nvda = Asset(name: "NVIDIA", ticker: "NVDA", spot: 207.29, vol: 0.42, div: 0.0002,
                            source: "Close 7/21 Nasdaq/MacroTrends · vol ASSUMPTION ~42")
    public static let amzn = Asset(name: "Amazon", ticker: "AMZN", spot: 247.55, vol: 0.33, div: 0.0,
                            source: "Close 7/21 Investing.com · vol ASSUMPTION ~33")
    public static let msft = Asset(name: "Microsoft", ticker: "MSFT", spot: 397.64, vol: 0.25, div: 0.0092,
                            source: "Close 7/21 Investing.com · yld 0.92% sourced · vol ASSUMPTION ~25")
    public static let aapl = Asset(name: "Apple", ticker: "AAPL", spot: 326.59, vol: 0.25, div: 0.0032,
                            source: "Close 7/21 CNBC · yld 0.32% sourced · vol ASSUMPTION ~25")
    public static let googl = Asset(name: "Alphabet", ticker: "GOOGL", spot: 351.99, vol: 0.28, div: 0.004,
                             source: "Close 7/21 CNBC · vol/div ASSUMPTION")
    public static let tsla = Asset(name: "Tesla", ticker: "TSLA", spot: 369.57, vol: 0.55, div: 0.0,
                            source: "Close 7/21 CNBC · vol ASSUMPTION ~55")
    public static let avgo = Asset(name: "Broadcom", ticker: "AVGO", spot: 386.50, vol: 0.40, div: 0.0068,
                            source: "Close 7/21 CNN · yld 0.68% sourced · vol ASSUMPTION ~40")
    public static let qqq = Asset(name: "QQQ", ticker: "QQQ", spot: 740.62, vol: 0.285, div: 0.0060,
                           source: "Close 7/21 CNBC · VXN proxy")
    public static let spy = Asset(name: "SPY", ticker: "SPY", spot: 746.74, vol: 0.184, div: 0.0105,
                           source: "Close 7/21 CNBC · VIX proxy")

    public static func asset(_ id: AssetID) -> Asset {
        switch id {
        case .spx: return spx
        case .ndx: return ndx
        case .rty: return rty
        case .nvda: return nvda
        case .amzn: return amzn
        case .msft: return msft
        case .aapl: return aapl
        case .googl: return googl
        case .tsla: return tsla
        case .avgo: return avgo
        case .qqq: return qqq
        case .spy: return spy
        }
    }

    public static func assets(for members: [AssetID]) -> [Asset] { members.map(asset) }
}
