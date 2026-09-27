// MACDCalculator.swift — MACD Line, Signal Line, Histogram
import Foundation

enum MACDCalculator {
    struct Result {
        let line:      [Double?]   // EMA(fast) − EMA(slow)
        let signal:    [Double?]   // EMA(signal) of MACD line
        let histogram: [Double?]   // line − signal
    }

    static func calculate(
        closes: [Double],
        fastPeriod: Int   = Configuration.Indicators.macdFast,
        slowPeriod: Int   = Configuration.Indicators.macdSlow,
        signalPeriod: Int = Configuration.Indicators.macdSignal
    ) -> Result {
        let fastEMA  = EMACalculator.calculate(values: closes, period: fastPeriod)
        let slowEMA  = EMACalculator.calculate(values: closes, period: slowPeriod)

        // MACD line = fastEMA - slowEMA (nil where either EMA is nil)
        let macdLine: [Double?] = zip(fastEMA, slowEMA).map { fast, slow in
            guard let f = fast, let s = slow else { return nil }
            return f - s
        }

        // Signal = EMA of non-nil MACD values, re-aligned to original index
        let nonNilMacd = macdLine.compactMap { $0 }
        let signalRaw  = EMACalculator.calculate(values: nonNilMacd, period: signalPeriod)

        // Re-align signal back to the full array length
        let firstMacdIndex = macdLine.firstIndex(where: { $0 != nil }) ?? macdLine.count
        var signalAligned: [Double?] = Array(repeating: nil, count: macdLine.count)
        for (offset, val) in signalRaw.enumerated() {
            let fullIndex = firstMacdIndex + offset
            if fullIndex < signalAligned.count {
                signalAligned[fullIndex] = val
            }
        }

        let histogram: [Double?] = zip(macdLine, signalAligned).map { line, sig in
            guard let l = line, let s = sig else { return nil }
            return l - s
        }

        return Result(line: macdLine, signal: signalAligned, histogram: histogram)
    }
}
