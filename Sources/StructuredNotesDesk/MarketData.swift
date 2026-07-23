//  MarketData.swift
//  Structured Notes
//
//  Data-driven catalog: the tape's top 50 index/ETF underliers and top 100
//  single stocks by 1H 2026 issuance count. Sourced entries carry real quotes
//  (indices ~Jul 20, stocks/ETFs Jul 21 2026 closes); the rest carry flagged
//  assumption-tier vol/div until a live feed is wired. Pricing uses vol, div
//  and correlation only — paths run in ratios, so spot is display-only.

import Foundation

public enum AssetClass: String, Hashable, Sendable {
    case indexETF = "Index / ETF"
    case stock = "Stock"
}

public struct Asset: Hashable, Sendable {
    public let ticker: String
    public let name: String
    public let cls: AssetClass
    public let spot: Double          // 0 = not sourced (display only)
    public let vol: Double
    public let div: Double
    public let sourced: Bool
    public let tapeCount: Int
    public let source: String

    public init(ticker: String, name: String, cls: AssetClass, spot: Double, vol: Double, div: Double, sourced: Bool, tapeCount: Int, source: String) {
        self.ticker = ticker; self.name = name; self.cls = cls; self.spot = spot
        self.vol = vol; self.div = div; self.sourced = sourced; self.tapeCount = tapeCount; self.source = source
    }
}

public enum Market {
    public static let asOf = "indices/NVDA Jul 22 close · ETFs Jul 23 · other stocks Jul 21 2026"
    /// ^TNX ~4.60% (Yahoo). Substitute the term-matched tenor.
    public static let ust = 0.046

    public static let catalog: [Asset] = [
        Asset(ticker: "SPX", name: "S&P 500", cls: .indexETF, spot: 7498.96, vol: 0.166, div: 0.0105, sourced: true, tapeCount: 15708, source: "Close 7/22 Yahoo · VIX 16.6 Cboe · yld Multpl"),
        Asset(ticker: "RTY", name: "Russell 2000", cls: .indexETF, spot: 2959.94, vol: 0.23, div: 0.012, sourced: true, tapeCount: 13882, source: "Close 7/22 Yahoo · vol/div est (use RVX)"),
        Asset(ticker: "NDX", name: "Nasdaq-100", cls: .indexETF, spot: 27240, vol: 0.285, div: 0.006, sourced: true, tapeCount: 8599, source: "DERIVED: QQQ 7/23 × 38.6 NAV ratio · VXN 28.5"),
        Asset(ticker: "INDU", name: "Dow Jones Industrial", cls: .indexETF, spot: 52218.58, vol: 0.17, div: 0.017, sourced: true, tapeCount: 4263, source: "Close 7/22 Yahoo · vol/div est"),
        Asset(ticker: "SX5E", name: "Euro Stoxx 50", cls: .indexETF, spot: 0, vol: 0.17, div: 0.031, sourced: false, tapeCount: 3530, source: "assumption tier — wire a feed"),
        Asset(ticker: "NDXT", name: "Nasdaq-100 Tech", cls: .indexETF, spot: 0, vol: 0.3, div: 0.004, sourced: false, tapeCount: 2131, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPXFP", name: "S&P 500 Futures-adj", cls: .indexETF, spot: 0, vol: 0.184, div: 0.0105, sourced: false, tapeCount: 1692, source: "assumption tier — wire a feed"),
        Asset(ticker: "QQQ", name: "Invesco QQQ", cls: .indexETF, spot: 705.35, vol: 0.285, div: 0.006, sourced: true, tapeCount: 726, source: "7/23 Slickcharts/Massive · VXN proxy · tech −4.8% since 7/21"),
        Asset(ticker: "SPY", name: "SPDR S&P 500", cls: .indexETF, spot: 747.41, vol: 0.166, div: 0.0105, sourced: true, tapeCount: 704, source: "7/23 Slickcharts/Massive · VIX proxy"),
        Asset(ticker: "XLU", name: "Utilities SPDR", cls: .indexETF, spot: 44.92, vol: 0.18, div: 0.0266, sourced: true, tapeCount: 654, source: "Close 7/21 stockanalysis.com · yld 2.66 ttm sourced · vol est 18"),
        Asset(ticker: "KRE", name: "Regional Banks", cls: .indexETF, spot: 0, vol: 0.28, div: 0.028, sourced: false, tapeCount: 640, source: "assumption tier — wire a feed"),
        Asset(ticker: "NKY", name: "Nikkei 225", cls: .indexETF, spot: 0, vol: 0.19, div: 0.016, sourced: false, tapeCount: 634, source: "assumption tier — wire a feed"),
        Asset(ticker: "SMH", name: "Semiconductor ETF", cls: .indexETF, spot: 584.08, vol: 0.32, div: 0.0019, sourced: true, tapeCount: 633, source: "Close 7/21 stockanalysis.com · yld 0.19 ttm sourced · vol est 32"),
        Asset(ticker: "SMI", name: "Swiss Market", cls: .indexETF, spot: 0, vol: 0.15, div: 0.028, sourced: false, tapeCount: 620, source: "assumption tier — wire a feed"),
        Asset(ticker: "UKX", name: "FTSE 100", cls: .indexETF, spot: 0, vol: 0.15, div: 0.036, sourced: false, tapeCount: 602, source: "assumption tier — wire a feed"),
        Asset(ticker: "AS51", name: "ASX 200", cls: .indexETF, spot: 0, vol: 0.15, div: 0.04, sourced: false, tapeCount: 589, source: "assumption tier — wire a feed"),
        Asset(ticker: "MQUSLVA", name: "Macquarie US Low Vol", cls: .indexETF, spot: 0, vol: 0.1, div: 0, sourced: false, tapeCount: 572, source: "assumption tier — wire a feed"),
        Asset(ticker: "MQUSTVA", name: "Macquarie US Target Vol", cls: .indexETF, spot: 0, vol: 0.1, div: 0, sourced: false, tapeCount: 572, source: "assumption tier — wire a feed"),
        Asset(ticker: "XLE", name: "Energy SPDR", cls: .indexETF, spot: 0, vol: 0.24, div: 0.032, sourced: false, tapeCount: 564, source: "assumption tier — wire a feed"),
        Asset(ticker: "GDX", name: "Gold Miners", cls: .indexETF, spot: 0, vol: 0.35, div: 0.01, sourced: false, tapeCount: 562, source: "assumption tier — wire a feed"),
        Asset(ticker: "IWM", name: "Russell 2000 ETF", cls: .indexETF, spot: 0, vol: 0.23, div: 0.012, sourced: false, tapeCount: 516, source: "assumption tier — wire a feed"),
        Asset(ticker: "EFA", name: "MSCI EAFE", cls: .indexETF, spot: 0, vol: 0.16, div: 0.029, sourced: false, tapeCount: 438, source: "assumption tier — wire a feed"),
        Asset(ticker: "XLK", name: "Technology SPDR", cls: .indexETF, spot: 0, vol: 0.24, div: 0.006, sourced: false, tapeCount: 407, source: "assumption tier — wire a feed"),
        Asset(ticker: "GLD", name: "SPDR Gold", cls: .indexETF, spot: 0, vol: 0.16, div: 0, sourced: false, tapeCount: 401, source: "assumption tier — wire a feed"),
        Asset(ticker: "TPX", name: "TPX", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 368, source: "assumption tier — wire a feed"),
        Asset(ticker: "SLV", name: "SLV", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 340, source: "assumption tier — wire a feed"),
        Asset(ticker: "MXEA", name: "MXEA", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 305, source: "assumption tier — wire a feed"),
        Asset(ticker: "MXEF", name: "MXEF", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 298, source: "assumption tier — wire a feed"),
        Asset(ticker: "IGV", name: "Software ETF", cls: .indexETF, spot: 0, vol: 0.3, div: 0.002, sourced: false, tapeCount: 293, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPUMP40", name: "SPUMP40", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 292, source: "assumption tier — wire a feed"),
        Asset(ticker: "GSMBFC5", name: "GSMBFC5", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 283, source: "assumption tier — wire a feed"),
        Asset(ticker: "XLF", name: "XLF", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 205, source: "assumption tier — wire a feed"),
        Asset(ticker: "EEM", name: "EEM", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 204, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPXFD356", name: "SPXFD356", cls: .indexETF, spot: 0, vol: 0.184, div: 0.035, sourced: false, tapeCount: 194, source: "decrement index — div set to the decrement rate, vol ≈ SPX"),
        Asset(ticker: "SPW", name: "SPW", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 193, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPXFD406", name: "SPXFD406", cls: .indexETF, spot: 0, vol: 0.184, div: 0.04, sourced: false, tapeCount: 180, source: "decrement index — div set to the decrement rate, vol ≈ SPX"),
        Asset(ticker: "XLP", name: "XLP", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 176, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPXF40D4", name: "SPXF40D4", cls: .indexETF, spot: 0, vol: 0.184, div: 0.04, sourced: false, tapeCount: 166, source: "decrement index — div set to the decrement rate, vol ≈ SPX"),
        Asset(ticker: "IBIT", name: "IBIT", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 145, source: "assumption tier — wire a feed"),
        Asset(ticker: "MID", name: "MID", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 138, source: "assumption tier — wire a feed"),
        Asset(ticker: "BXIIUT4E", name: "BXIIUT4E", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 137, source: "assumption tier — wire a feed"),
        Asset(ticker: "XLV", name: "XLV", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 129, source: "assumption tier — wire a feed"),
        Asset(ticker: "TLT", name: "TLT", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 124, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPAR4V6", name: "SPAR4V6", cls: .indexETF, spot: 0, vol: 0.184, div: 0.04, sourced: false, tapeCount: 116, source: "decrement index — div set to the decrement rate, vol ≈ SPX"),
        Asset(ticker: "XME", name: "XME", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 115, source: "assumption tier — wire a feed"),
        Asset(ticker: "BNPIMADX", name: "BNPIMADX", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 113, source: "assumption tier — wire a feed"),
        Asset(ticker: "EWZ", name: "EWZ", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 107, source: "assumption tier — wire a feed"),
        Asset(ticker: "RSP", name: "RSP", cls: .indexETF, spot: 0, vol: 0.24, div: 0.015, sourced: false, tapeCount: 105, source: "assumption tier — wire a feed"),
        Asset(ticker: "MAX", name: "MAX", cls: .indexETF, spot: 0, vol: 0.17, div: 0.02, sourced: false, tapeCount: 104, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPXF4EV6", name: "SPXF4EV6", cls: .indexETF, spot: 0, vol: 0.184, div: 0.04, sourced: false, tapeCount: 100, source: "decrement index — div set to the decrement rate, vol ≈ SPX"),
        Asset(ticker: "NVDA", name: "NVIDIA", cls: .stock, spot: 212.06, vol: 0.42, div: 0.0002, sourced: true, tapeCount: 2466, source: "Close 7/22 stockanalysis/Investing · vol est 42"),
        Asset(ticker: "AMZN", name: "Amazon", cls: .stock, spot: 247.55, vol: 0.33, div: 0.0, sourced: true, tapeCount: 1452, source: "Close 7/21 Investing.com · vol est 33"),
        Asset(ticker: "MSFT", name: "Microsoft", cls: .stock, spot: 397.64, vol: 0.25, div: 0.0092, sourced: true, tapeCount: 1199, source: "Close 7/21 Investing.com · yld sourced · vol est"),
        Asset(ticker: "AVGO", name: "Broadcom", cls: .stock, spot: 386.5, vol: 0.4, div: 0.0068, sourced: true, tapeCount: 976, source: "Close 7/21 CNN · yld sourced · vol est"),
        Asset(ticker: "GOOGL", name: "Alphabet A", cls: .stock, spot: 351.99, vol: 0.28, div: 0.004, sourced: true, tapeCount: 920, source: "Close 7/21 CNBC · vol/div est"),
        Asset(ticker: "MU", name: "Micron", cls: .stock, spot: 0, vol: 0.55, div: 0.002, sourced: false, tapeCount: 915, source: "assumption tier — wire a feed"),
        Asset(ticker: "TSLA", name: "Tesla", cls: .stock, spot: 369.57, vol: 0.55, div: 0.0, sourced: true, tapeCount: 906, source: "Close 7/21 CNBC · vol est 55"),
        Asset(ticker: "META", name: "Meta Platforms", cls: .stock, spot: 643.81, vol: 0.3, div: 0.003, sourced: true, tapeCount: 903, source: "Close 7/21 CNN · vol/div est"),
        Asset(ticker: "AMD", name: "AMD", cls: .stock, spot: 503.57, vol: 0.48, div: 0.0, sourced: true, tapeCount: 889, source: "7/21 close via CNN arithmetic · vol est 48"),
        Asset(ticker: "ORCL", name: "Oracle", cls: .stock, spot: 127.05, vol: 0.45, div: 0.0161, sourced: true, tapeCount: 791, source: "Close CNN · yld 1.61 sourced · vol est (elevated)"),
        Asset(ticker: "PLTR", name: "Palantir", cls: .stock, spot: 0, vol: 0.6, div: 0, sourced: false, tapeCount: 746, source: "assumption tier — wire a feed"),
        Asset(ticker: "AAPL", name: "Apple", cls: .stock, spot: 326.59, vol: 0.25, div: 0.0032, sourced: true, tapeCount: 687, source: "Close 7/21 CNBC · yld 0.32 sourced · vol est"),
        Asset(ticker: "GOOG", name: "Alphabet C", cls: .stock, spot: 0, vol: 0.28, div: 0.004, sourced: false, tapeCount: 503, source: "assumption tier — wire a feed"),
        Asset(ticker: "INTC", name: "Intel", cls: .stock, spot: 0, vol: 0.45, div: 0.01, sourced: false, tapeCount: 432, source: "assumption tier — wire a feed"),
        Asset(ticker: "NFLX", name: "Netflix", cls: .stock, spot: 0, vol: 0.35, div: 0, sourced: false, tapeCount: 406, source: "assumption tier — wire a feed"),
        Asset(ticker: "BX", name: "Blackstone", cls: .stock, spot: 0, vol: 0.35, div: 0.03, sourced: false, tapeCount: 348, source: "assumption tier — wire a feed"),
        Asset(ticker: "JPM", name: "JPMorgan", cls: .stock, spot: 0, vol: 0.22, div: 0.023, sourced: false, tapeCount: 313, source: "assumption tier — wire a feed"),
        Asset(ticker: "NOW", name: "ServiceNow", cls: .stock, spot: 0, vol: 0.4, div: 0, sourced: false, tapeCount: 306, source: "assumption tier — wire a feed"),
        Asset(ticker: "CEG", name: "Constellation Energy", cls: .stock, spot: 0, vol: 0.4, div: 0.005, sourced: false, tapeCount: 300, source: "assumption tier — wire a feed"),
        Asset(ticker: "MRVL", name: "Marvell", cls: .stock, spot: 0, vol: 0.5, div: 0.003, sourced: false, tapeCount: 287, source: "assumption tier — wire a feed"),
        Asset(ticker: "BAC", name: "Bank of America", cls: .stock, spot: 0, vol: 0.28, div: 0.026, sourced: false, tapeCount: 282, source: "assumption tier — wire a feed"),
        Asset(ticker: "LLY", name: "Eli Lilly", cls: .stock, spot: 0, vol: 0.28, div: 0.008, sourced: false, tapeCount: 278, source: "assumption tier — wire a feed"),
        Asset(ticker: "TSM", name: "TSMC", cls: .stock, spot: 0, vol: 0.35, div: 0.015, sourced: false, tapeCount: 273, source: "assumption tier — wire a feed"),
        Asset(ticker: "GS", name: "Goldman Sachs", cls: .stock, spot: 0, vol: 0.27, div: 0.021, sourced: false, tapeCount: 267, source: "assumption tier — wire a feed"),
        Asset(ticker: "CRWD", name: "CrowdStrike", cls: .stock, spot: 0, vol: 0.45, div: 0, sourced: false, tapeCount: 249, source: "assumption tier — wire a feed"),
        Asset(ticker: "MS", name: "Morgan Stanley", cls: .stock, spot: 0, vol: 0.28, div: 0.033, sourced: false, tapeCount: 242, source: "assumption tier — wire a feed"),
        Asset(ticker: "UNH", name: "UnitedHealth", cls: .stock, spot: 0, vol: 0.3, div: 0.015, sourced: false, tapeCount: 241, source: "assumption tier — wire a feed"),
        Asset(ticker: "DELL", name: "Dell", cls: .stock, spot: 0, vol: 0.45, div: 0.012, sourced: false, tapeCount: 227, source: "assumption tier — wire a feed"),
        Asset(ticker: "C", name: "Citigroup", cls: .stock, spot: 0, vol: 0.28, div: 0.031, sourced: false, tapeCount: 222, source: "assumption tier — wire a feed"),
        Asset(ticker: "FCX", name: "FCX", cls: .stock, spot: 0, vol: 0.38, div: 0.015, sourced: false, tapeCount: 211, source: "assumption tier — wire a feed"),
        Asset(ticker: "SNOW", name: "SNOW", cls: .stock, spot: 0, vol: 0.45, div: 0, sourced: false, tapeCount: 208, source: "assumption tier — wire a feed"),
        Asset(ticker: "HOOD", name: "Robinhood", cls: .stock, spot: 0, vol: 0.6, div: 0, sourced: false, tapeCount: 203, source: "assumption tier — wire a feed"),
        Asset(ticker: "CRWV", name: "CoreWeave", cls: .stock, spot: 0, vol: 0.8, div: 0, sourced: false, tapeCount: 199, source: "assumption tier — wire a feed"),
        Asset(ticker: "GEV", name: "GEV", cls: .stock, spot: 0, vol: 0.4, div: 0.002, sourced: false, tapeCount: 194, source: "assumption tier — wire a feed"),
        Asset(ticker: "VST", name: "VST", cls: .stock, spot: 0, vol: 0.45, div: 0.01, sourced: false, tapeCount: 185, source: "assumption tier — wire a feed"),
        Asset(ticker: "CRM", name: "CRM", cls: .stock, spot: 0, vol: 0.32, div: 0.002, sourced: false, tapeCount: 175, source: "assumption tier — wire a feed"),
        Asset(ticker: "VRT", name: "VRT", cls: .stock, spot: 0, vol: 0.45, div: 0.002, sourced: false, tapeCount: 175, source: "assumption tier — wire a feed"),
        Asset(ticker: "AMAT", name: "AMAT", cls: .stock, spot: 0, vol: 0.38, div: 0.012, sourced: false, tapeCount: 174, source: "assumption tier — wire a feed"),
        Asset(ticker: "QCOM", name: "QCOM", cls: .stock, spot: 0, vol: 0.32, div: 0.021, sourced: false, tapeCount: 166, source: "assumption tier — wire a feed"),
        Asset(ticker: "WFC", name: "WFC", cls: .stock, spot: 0, vol: 0.27, div: 0.03, sourced: false, tapeCount: 164, source: "assumption tier — wire a feed"),
        Asset(ticker: "PANW", name: "PANW", cls: .stock, spot: 0, vol: 0.35, div: 0, sourced: false, tapeCount: 150, source: "assumption tier — wire a feed"),
        Asset(ticker: "LRCX", name: "LRCX", cls: .stock, spot: 0, vol: 0.4, div: 0.01, sourced: false, tapeCount: 149, source: "assumption tier — wire a feed"),
        Asset(ticker: "COIN", name: "Coinbase", cls: .stock, spot: 0, vol: 0.75, div: 0, sourced: false, tapeCount: 139, source: "assumption tier — wire a feed"),
        Asset(ticker: "UBER", name: "UBER", cls: .stock, spot: 0, vol: 0.35, div: 0, sourced: false, tapeCount: 134, source: "assumption tier — wire a feed"),
        Asset(ticker: "SHOP", name: "SHOP", cls: .stock, spot: 0, vol: 0.45, div: 0, sourced: false, tapeCount: 133, source: "assumption tier — wire a feed"),
        Asset(ticker: "APO", name: "APO", cls: .stock, spot: 0, vol: 0.35, div: 0.018, sourced: false, tapeCount: 133, source: "assumption tier — wire a feed"),
        Asset(ticker: "ANET", name: "ANET", cls: .stock, spot: 0, vol: 0.4, div: 0, sourced: false, tapeCount: 132, source: "assumption tier — wire a feed"),
        Asset(ticker: "CAT", name: "CAT", cls: .stock, spot: 0, vol: 0.27, div: 0.017, sourced: false, tapeCount: 128, source: "assumption tier — wire a feed"),
        Asset(ticker: "IBM", name: "IBM", cls: .stock, spot: 0, vol: 0.22, div: 0.028, sourced: false, tapeCount: 128, source: "assumption tier — wire a feed"),
        Asset(ticker: "BA", name: "BA", cls: .stock, spot: 0, vol: 0.35, div: 0, sourced: false, tapeCount: 125, source: "assumption tier — wire a feed"),
        Asset(ticker: "NKE", name: "NKE", cls: .stock, spot: 0, vol: 0.3, div: 0.02, sourced: false, tapeCount: 122, source: "assumption tier — wire a feed"),
        Asset(ticker: "WMT", name: "WMT", cls: .stock, spot: 0, vol: 0.2, div: 0.009, sourced: false, tapeCount: 120, source: "assumption tier — wire a feed"),
        Asset(ticker: "ACN", name: "ACN", cls: .stock, spot: 0, vol: 0.25, div: 0.017, sourced: false, tapeCount: 119, source: "assumption tier — wire a feed"),
        Asset(ticker: "ETN", name: "ETN", cls: .stock, spot: 0, vol: 0.28, div: 0.011, sourced: false, tapeCount: 118, source: "assumption tier — wire a feed"),
        Asset(ticker: "KKR", name: "KKR", cls: .stock, spot: 0, vol: 0.35, div: 0.007, sourced: false, tapeCount: 113, source: "assumption tier — wire a feed"),
        Asset(ticker: "APP", name: "APP", cls: .stock, spot: 0, vol: 0.6, div: 0, sourced: false, tapeCount: 111, source: "assumption tier — wire a feed"),
        Asset(ticker: "WDC", name: "WDC", cls: .stock, spot: 0, vol: 0.45, div: 0.008, sourced: false, tapeCount: 102, source: "assumption tier — wire a feed"),
        Asset(ticker: "DAL", name: "DAL", cls: .stock, spot: 0, vol: 0.38, div: 0.01, sourced: false, tapeCount: 99, source: "assumption tier — wire a feed"),
        Asset(ticker: "COF", name: "COF", cls: .stock, spot: 0, vol: 0.3, div: 0.018, sourced: false, tapeCount: 98, source: "assumption tier — wire a feed"),
        Asset(ticker: "ARES", name: "ARES", cls: .stock, spot: 0, vol: 0.35, div: 0.02, sourced: false, tapeCount: 98, source: "assumption tier — wire a feed"),
        Asset(ticker: "INTU", name: "INTU", cls: .stock, spot: 0, vol: 0.3, div: 0.006, sourced: false, tapeCount: 94, source: "assumption tier — wire a feed"),
        Asset(ticker: "GE", name: "GE", cls: .stock, spot: 0, vol: 0.3, div: 0.008, sourced: false, tapeCount: 91, source: "assumption tier — wire a feed"),
        Asset(ticker: "SMCI", name: "Super Micro", cls: .stock, spot: 0, vol: 0.7, div: 0, sourced: false, tapeCount: 90, source: "assumption tier — wire a feed"),
        Asset(ticker: "V", name: "V", cls: .stock, spot: 0, vol: 0.22, div: 0.007, sourced: false, tapeCount: 88, source: "assumption tier — wire a feed"),
        Asset(ticker: "BSX", name: "BSX", cls: .stock, spot: 0, vol: 0.25, div: 0, sourced: false, tapeCount: 88, source: "assumption tier — wire a feed"),
        Asset(ticker: "F", name: "F", cls: .stock, spot: 0, vol: 0.32, div: 0.05, sourced: false, tapeCount: 85, source: "assumption tier — wire a feed"),
        Asset(ticker: "GLW", name: "GLW", cls: .stock, spot: 0, vol: 0.3, div: 0.021, sourced: false, tapeCount: 80, source: "assumption tier — wire a feed"),
        Asset(ticker: "UAL", name: "UAL", cls: .stock, spot: 0, vol: 0.42, div: 0, sourced: false, tapeCount: 79, source: "assumption tier — wire a feed"),
        Asset(ticker: "DOW", name: "DOW", cls: .stock, spot: 0, vol: 0.3, div: 0.055, sourced: false, tapeCount: 79, source: "assumption tier — wire a feed"),
        Asset(ticker: "ADBE", name: "ADBE", cls: .stock, spot: 0, vol: 0.32, div: 0, sourced: false, tapeCount: 78, source: "assumption tier — wire a feed"),
        Asset(ticker: "MELI", name: "MELI", cls: .stock, spot: 0, vol: 0.4, div: 0, sourced: false, tapeCount: 78, source: "assumption tier — wire a feed"),
        Asset(ticker: "ASML", name: "ASML", cls: .stock, spot: 0, vol: 0.35, div: 0.008, sourced: false, tapeCount: 75, source: "assumption tier — wire a feed"),
        Asset(ticker: "NEE", name: "NEE", cls: .stock, spot: 0, vol: 0.22, div: 0.029, sourced: false, tapeCount: 74, source: "assumption tier — wire a feed"),
        Asset(ticker: "SOFI", name: "SOFI", cls: .stock, spot: 0, vol: 0.55, div: 0, sourced: false, tapeCount: 73, source: "assumption tier — wire a feed"),
        Asset(ticker: "KLAC", name: "KLAC", cls: .stock, spot: 0, vol: 0.38, div: 0.012, sourced: false, tapeCount: 73, source: "assumption tier — wire a feed"),
        Asset(ticker: "MRNA", name: "MRNA", cls: .stock, spot: 0, vol: 0.55, div: 0, sourced: false, tapeCount: 72, source: "assumption tier — wire a feed"),
        Asset(ticker: "NVO", name: "NVO", cls: .stock, spot: 0, vol: 0.3, div: 0.017, sourced: false, tapeCount: 70, source: "assumption tier — wire a feed"),
        Asset(ticker: "ARM", name: "Arm", cls: .stock, spot: 0, vol: 0.55, div: 0, sourced: false, tapeCount: 69, source: "assumption tier — wire a feed"),
        Asset(ticker: "UPS", name: "UPS", cls: .stock, spot: 0, vol: 0.28, div: 0.05, sourced: false, tapeCount: 69, source: "assumption tier — wire a feed"),
        Asset(ticker: "COHR", name: "COHR", cls: .stock, spot: 0, vol: 0.5, div: 0, sourced: false, tapeCount: 69, source: "assumption tier — wire a feed"),
        Asset(ticker: "DIS", name: "DIS", cls: .stock, spot: 0, vol: 0.27, div: 0.009, sourced: false, tapeCount: 67, source: "assumption tier — wire a feed"),
        Asset(ticker: "SNDK", name: "SNDK", cls: .stock, spot: 0, vol: 0.55, div: 0, sourced: false, tapeCount: 67, source: "assumption tier — wire a feed"),
        Asset(ticker: "XOM", name: "XOM", cls: .stock, spot: 0, vol: 0.22, div: 0.033, sourced: false, tapeCount: 67, source: "assumption tier — wire a feed"),
        Asset(ticker: "FSLR", name: "FSLR", cls: .stock, spot: 0, vol: 0.45, div: 0, sourced: false, tapeCount: 66, source: "assumption tier — wire a feed"),
        Asset(ticker: "HD", name: "HD", cls: .stock, spot: 0, vol: 0.22, div: 0.024, sourced: false, tapeCount: 65, source: "assumption tier — wire a feed"),
        Asset(ticker: "TGT", name: "TGT", cls: .stock, spot: 0, vol: 0.3, div: 0.03, sourced: false, tapeCount: 63, source: "assumption tier — wire a feed"),
        Asset(ticker: "NEM", name: "NEM", cls: .stock, spot: 0, vol: 0.35, div: 0.02, sourced: false, tapeCount: 63, source: "assumption tier — wire a feed"),
        Asset(ticker: "LMT", name: "LMT", cls: .stock, spot: 0, vol: 0.22, div: 0.026, sourced: false, tapeCount: 62, source: "assumption tier — wire a feed"),
        Asset(ticker: "CVX", name: "CVX", cls: .stock, spot: 0, vol: 0.22, div: 0.041, sourced: false, tapeCount: 61, source: "assumption tier — wire a feed"),
        Asset(ticker: "SPOT", name: "SPOT", cls: .stock, spot: 0, vol: 0.38, div: 0, sourced: false, tapeCount: 59, source: "assumption tier — wire a feed"),
        Asset(ticker: "ZS", name: "ZS", cls: .stock, spot: 0, vol: 0.42, div: 0, sourced: false, tapeCount: 58, source: "assumption tier — wire a feed"),
        Asset(ticker: "COST", name: "COST", cls: .stock, spot: 0, vol: 0.22, div: 0.005, sourced: false, tapeCount: 57, source: "assumption tier — wire a feed"),
        Asset(ticker: "AAL", name: "AAL", cls: .stock, spot: 0, vol: 0.45, div: 0, sourced: false, tapeCount: 57, source: "assumption tier — wire a feed"),
        Asset(ticker: "TXN", name: "TXN", cls: .stock, spot: 0, vol: 0.28, div: 0.026, sourced: false, tapeCount: 55, source: "assumption tier — wire a feed"),
        Asset(ticker: "AFRM", name: "AFRM", cls: .stock, spot: 0, vol: 0.65, div: 0, sourced: false, tapeCount: 54, source: "assumption tier — wire a feed"),
        Asset(ticker: "HAL", name: "HAL", cls: .stock, spot: 0, vol: 0.32, div: 0.024, sourced: false, tapeCount: 54, source: "assumption tier — wire a feed"),
        Asset(ticker: "DDOG", name: "DDOG", cls: .stock, spot: 0, vol: 0.42, div: 0, sourced: false, tapeCount: 53, source: "assumption tier — wire a feed"),
        Asset(ticker: "CMG", name: "CMG", cls: .stock, spot: 0, vol: 0.3, div: 0, sourced: false, tapeCount: 52, source: "assumption tier — wire a feed"),
        Asset(ticker: "AA", name: "AA", cls: .stock, spot: 0, vol: 0.45, div: 0.01, sourced: false, tapeCount: 52, source: "assumption tier — wire a feed"),
        Asset(ticker: "PWR", name: "PWR", cls: .stock, spot: 0, vol: 0.4, div: 0.005, sourced: false, tapeCount: 52, source: "assumption tier — wire a feed"),
    ]

    public static let byTicker: [String: Asset] =
        Dictionary(catalog.map { ($0.ticker, $0) }, uniquingKeysWith: { a, _ in a })

    public static var indexETF: [Asset] { catalog.filter { $0.cls == .indexETF } }
    public static var stocks: [Asset] { catalog.filter { $0.cls == .stock } }

    public static func asset(_ t: String) -> Asset {
        byTicker[t] ?? Asset(ticker: t, name: t, cls: .stock, spot: 0,
                             vol: 0.40, div: 0.005, sourced: false, tapeCount: 0,
                             source: "not in catalog — defaults")
    }

    public static func assets(for members: [String]) -> [Asset] { members.map(asset) }
}
