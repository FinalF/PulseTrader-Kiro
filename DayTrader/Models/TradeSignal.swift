// TradeSignal.swift — buy/sell signal produced by SignalEngine
import Foundation

enum SignalDirection: String, Codable, CaseIterable, Hashable {
    case buy  = "BUY"
    case sell = "SELL"

    var emoji: String { self == .buy ? "▲" : "▼" }
}

/// Codable + Hashable so it can be used in sorted collections and persisted
enum ConfidenceTier: String, Codable, CaseIterable, Hashable {
    case high   = "High"    // ≥ 0.80
    case medium = "Medium"  // ≥ 0.60
    case low    = "Low"     // < 0.60 (not normally emitted)

    init(score: Double) {
        if score >= 0.80      { self = .high }
        else if score >= 0.60 { self = .medium }
        else                  { self = .low }
    }
}

struct TradeSignal: Identifiable, Codable, Hashable {
    let id: UUID
    let symbol: String
    let timestamp: Date
    let direction: SignalDirection
    /// Weighted confluence score 0.0 – 1.0
    let confidence: Double
    let triggeringIndicators: [String]
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    var isNotified: Bool = false

    var tier: ConfidenceTier { ConfidenceTier(score: confidence) }

    /// Returns nil when risk == 0 (malformed signal — stop equals entry).
    /// Signal engine must ensure stopLoss ≠ entryPrice before emitting.
    var riskReward: Double? {
        let risk = abs(entryPrice - stopLoss)
        guard risk > 0 else { return nil }
        let reward = abs(takeProfit - entryPrice)
        return reward / risk
    }

    var displayConfidence: String { String(format: "%.0f%%", confidence * 100) }

    init(symbol: String, timestamp: Date, direction: SignalDirection,
         confidence: Double, triggeringIndicators: [String],
         entryPrice: Double, stopLoss: Double, takeProfit: Double) {
        self.id                   = UUID()
        self.symbol               = symbol
        self.timestamp            = timestamp
        self.direction            = direction
        self.confidence           = confidence
        self.triggeringIndicators = triggeringIndicators
        self.entryPrice           = entryPrice
        self.stopLoss             = stopLoss
        self.takeProfit           = takeProfit
    }
}
