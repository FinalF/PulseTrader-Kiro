// BollingerBandCalculator.swift — Bollinger Bands (SMA ± k·σ)
import Foundation

enum BollingerBandCalculator {
    struct Result {
        let upper:  [Double?]
        let middle: [Double?]   // SMA
        let lower:  [Double?]
        let bandwidth: [Double?]  // (upper - lower) / middle
        let percentB: [Double?]   // (close - lower) / (upper - lower)
    }

    static func calculate(
        closes: [Double],
        period: Int    = Configuration.Indicators.bbPeriod,
        stdDevMult: Double = Configuration.Indicators.bbStdDev
    ) -> Result {
        let sma = SMACalculator.calculate(values: closes, period: period)
        var upper, lower, bw, pctB: [Double?]
        upper = Array(repeating: nil, count: closes.count)
        lower = Array(repeating: nil, count: closes.count)
        bw    = Array(repeating: nil, count: closes.count)
        pctB  = Array(repeating: nil, count: closes.count)

        for i in (period - 1)..<closes.count {
            guard let mid = sma[i] else { continue }
            let window = closes[(i - period + 1)...i]
            let variance = window.reduce(0) { $0 + pow($1 - mid, 2) } / Double(period)
            let sd = sqrt(variance)
            let u = mid + stdDevMult * sd
            let l = mid - stdDevMult * sd
            upper[i] = u
            lower[i] = l
            bw[i]    = mid > 0 ? (u - l) / mid : nil
            pctB[i]  = (u - l) > 0 ? (closes[i] - l) / (u - l) : nil
        }
        return Result(upper: upper, middle: sma, lower: lower, bandwidth: bw, percentB: pctB)
    }
}
