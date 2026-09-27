// RSICalculator.swift — Relative Strength Index (Wilder smoothing)
import Foundation

enum RSICalculator {
    /// Uses Wilder's smoothing (same as TradingView / most platforms).
    /// Returns values 0–100, aligned to `closes`. Leading nils for warm-up.
    static func calculate(closes: [Double],
                          period: Int = Configuration.Indicators.rsiPeriod) -> [Double?] {
        guard period > 0, closes.count > period else {
            return Array(repeating: nil, count: closes.count)
        }

        var result: [Double?] = Array(repeating: nil, count: closes.count)

        // First average gain/loss over initial period
        var gains: Double = 0, losses: Double = 0
        for i in 1...period {
            let diff = closes[i] - closes[i - 1]
            if diff > 0 { gains  += diff }
            else        { losses -= diff }
        }
        var avgGain = gains  / Double(period)
        var avgLoss = losses / Double(period)

        func rsi(_ g: Double, _ l: Double) -> Double {
            guard l != 0 else { return 100 }
            let rs = g / l
            return 100 - (100 / (1 + rs))
        }

        result[period] = rsi(avgGain, avgLoss)

        // Wilder smoothing for subsequent bars
        for i in (period + 1)..<closes.count {
            let diff = closes[i] - closes[i - 1]
            let gain = max(diff, 0)
            let loss = max(-diff, 0)
            avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
            result[i] = rsi(avgGain, avgLoss)
        }
        return result
    }
}
