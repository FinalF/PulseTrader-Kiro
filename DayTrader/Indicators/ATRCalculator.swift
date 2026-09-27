// ATRCalculator.swift — Average True Range (Wilder smoothing)
import Foundation

enum ATRCalculator {
    /// True Range = max(high-low, |high-prevClose|, |low-prevClose|)
    static func calculate(quotes: [Quote],
                          period: Int = Configuration.Indicators.atrPeriod) -> [Double?] {
        guard quotes.count > period else {
            return Array(repeating: nil, count: quotes.count)
        }
        var result: [Double?] = Array(repeating: nil, count: quotes.count)

        func trueRange(_ i: Int) -> Double {
            let q = quotes[i]
            let prevClose = i > 0 ? quotes[i - 1].close : q.open
            return max(q.high - q.low,
                       abs(q.high - prevClose),
                       abs(q.low  - prevClose))
        }

        // Seed ATR = simple average of first `period` TR values
        let seedSlice = (1...period).map { trueRange($0) }
        var atr = seedSlice.reduce(0, +) / Double(period)
        result[period] = atr

        for i in (period + 1)..<quotes.count {
            atr = (atr * Double(period - 1) + trueRange(i)) / Double(period)
            result[i] = atr
        }
        return result
    }
}
