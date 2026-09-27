// EMACalculator.swift — Exponential Moving Average
import Foundation

enum EMACalculator {
    /// Standard EMA using multiplier k = 2/(period+1).
    /// Returns array aligned to `values`; leading nils for warm-up.
    static func calculate(values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else {
            return Array(repeating: nil, count: values.count)
        }
        let k = 2.0 / Double(period + 1)
        var result: [Double?] = Array(repeating: nil, count: period - 1)

        // Seed with SMA of first `period` values
        let seed = values[0..<period].reduce(0, +) / Double(period)
        result.append(seed)

        var prev = seed
        for i in period..<values.count {
            let ema = values[i] * k + prev * (1 - k)
            result.append(ema)
            prev = ema
        }
        return result
    }
}
