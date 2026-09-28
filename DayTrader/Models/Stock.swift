// Stock.swift — tradeable instrument + live snapshot
import Foundation

struct Stock: Identifiable, Codable, Hashable {

    // Manual Hashable — Quote is not Hashable so we hash on the stable id only.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Equatable must compare the fields that affect rendering, otherwise
    // SwiftUI skips redrawing rows when latestQuote/latestSignal change
    // (e.g. price stays "--" forever even after data arrives).
    static func == (lhs: Stock, rhs: Stock) -> Bool {
        lhs.id == rhs.id &&
        lhs.latestQuote?.close == rhs.latestQuote?.close &&
        lhs.latestQuote?.previousClose == rhs.latestQuote?.previousClose &&
        lhs.latestSignal?.id == rhs.latestSignal?.id
    }
    let id: String
    var symbol: String
    var name: String
    var exchange: String
    var sector: String?
    var isActive: Bool
    var latestQuote: Quote?
    var latestSignal: TradeSignal?

    var displayPrice: String {
        guard let p = latestQuote?.close else { return "--" }
        return String(format: "%.2f", p)
    }

    /// Returns nil when no quote is loaded — distinct from a flat-on-the-day stock (0.0)
    var changePercent: Double? {
        guard let q = latestQuote, let prev = q.previousClose, prev > 0 else { return nil }
        return ((q.close - prev) / prev) * 100
    }

    var displayChangePercent: String {
        guard let pct = changePercent else { return "--" }
        return String(format: "%+.2f%%", pct)
    }

    var isGaining: Bool { (changePercent ?? 0) >= 0 }

    init(symbol: String, name: String, exchange: String = "NASDAQ", sector: String? = nil) {
        self.id       = symbol.uppercased()
        self.symbol   = symbol.uppercased()
        self.name     = name
        self.exchange = exchange
        self.sector   = sector
        self.isActive = true
    }
}

extension Stock {
    static let defaults: [Stock] = [
        Stock(symbol: "AAPL",  name: "Apple Inc.",      exchange: "NASDAQ", sector: "Technology"),
        Stock(symbol: "NVDA",  name: "NVIDIA Corp.",     exchange: "NASDAQ", sector: "Technology"),
        Stock(symbol: "TSLA",  name: "Tesla Inc.",       exchange: "NASDAQ", sector: "Consumer"),
        Stock(symbol: "MSFT",  name: "Microsoft Corp.",  exchange: "NASDAQ", sector: "Technology"),
        Stock(symbol: "SPY",   name: "SPDR S&P 500 ETF", exchange: "NYSE",   sector: "ETF"),
    ]
}
