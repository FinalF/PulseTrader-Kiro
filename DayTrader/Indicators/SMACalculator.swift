// SMACalculator.swift — Simple Moving Average
import Foundation

enum SMACalculator {
    /// Returns an array aligned to `values`. Leading nils fill the warm-up period.
    static func calculate(values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else {
            return Array(repeating: nil, count: values.count)
        }
        var result: [Double?] = Array(repeating: nil, count: period - 1)
        var windowSum = values[0..<period].reduce(0, +)
        result.append(windowSum / Double(period))

        for i in period..<values.count {
            windowSum += values[i] - values[i - period]
            result.append(windowSum / Double(period))
        }
        return result
    }
}
