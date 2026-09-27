// VWAPCalculator.swift — Volume Weighted Average Price (session-cumulative)
import Foundation

enum VWAPCalculator {
    /// Cumulative VWAP reset at session open.
    /// Aligned to `quotes`; first value equals the first bar's typical price.
    static func calculate(quotes: [Quote]) -> [Double?] {
        guard !quotes.isEmpty else { return [] }

        var result: [Double?] = []
        var cumulativeTPV: Double = 0   // Σ(typical price × volume)
        var cumulativeVol: Double = 0   // Σvolume
        var currentDate: Date?

        for quote in quotes {
            let barDate = Calendar.current.startOfDay(for: quote.timestamp)

            // Reset at new session
            if let last = currentDate, !Calendar.current.isDate(barDate, inSameDayAs: last) {
                cumulativeTPV = 0
                cumulativeVol = 0
            }
            currentDate = barDate

            cumulativeTPV += quote.typicalPrice * Double(quote.volume)
            cumulativeVol += Double(quote.volume)

            result.append(cumulativeVol > 0 ? cumulativeTPV / cumulativeVol : nil)
        }
        return result
    }
}
