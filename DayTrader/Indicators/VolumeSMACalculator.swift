// VolumeSMACalculator.swift — SMA of volume for volume-spike detection
import Foundation

enum VolumeSMACalculator {
    static func calculate(quotes: [Quote],
                          period: Int = Configuration.Indicators.volumeSmaPeriod) -> [Double?] {
        let volumes = quotes.map { Double($0.volume) }
        return SMACalculator.calculate(values: volumes, period: period)
    }
}
