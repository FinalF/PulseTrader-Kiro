// IndicatorEngine.swift — aggregate entry point, computes all indicators in one call
import Foundation

struct IndicatorBundle {
    let ema9:     [Double?]
    let sma20:    [Double?]
    let macd:     MACDCalculator.Result
    let rsi:      [Double?]
    let bb:       BollingerBandCalculator.Result
    let atr:      [Double?]
    let volumeSMA:[Double?]
    let vwap:     [Double?]
}

enum IndicatorEngine {
    /// Compute the full indicator suite on a bar series.
    /// Returns nil if fewer than `slowPeriod + signalPeriod` bars are available.
    static func compute(quotes: [Quote]) -> IndicatorBundle? {
        let minBars = Configuration.Indicators.macdSlow + Configuration.Indicators.macdSignal
        guard quotes.count >= minBars else { return nil }

        let closes = quotes.map { $0.close }

        return IndicatorBundle(
            ema9:      EMACalculator.calculate(values: closes,
                                               period: Configuration.Indicators.emaPeriod),
            sma20:     SMACalculator.calculate(values: closes,
                                               period: Configuration.Indicators.smaPeriod),
            macd:      MACDCalculator.calculate(closes: closes),
            rsi:       RSICalculator.calculate(closes: closes),
            bb:        BollingerBandCalculator.calculate(closes: closes),
            atr:       ATRCalculator.calculate(quotes: quotes),
            volumeSMA: VolumeSMACalculator.calculate(quotes: quotes),
            vwap:      VWAPCalculator.calculate(quotes: quotes)
        )
    }
}
