// Quote.swift — single OHLCV bar
import Foundation

struct Quote: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
    // nil = no prior close available (e.g. first bar of session)
    var previousClose: Double?

    init(symbol: String, timestamp: Date, open: Double, high: Double,
         low: Double, close: Double, volume: Int, previousClose: Double? = nil) {
        self.id            = UUID()
        self.symbol        = symbol
        self.timestamp     = timestamp
        self.open          = open
        self.high          = high
        self.low           = low
        self.close         = close
        self.volume        = volume
        self.previousClose = previousClose
    }

    var typicalPrice: Double { (high + low + close) / 3.0 }

    /// nil when open == close (doji), true for green, false for red
    var isGreen: Bool? {
        if close == open { return nil }
        return close > open
    }
}
