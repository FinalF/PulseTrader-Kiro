// TradingColors.swift — centralized color palette
import SwiftUI

extension Color {
    static let gain    = Color.green
    static let loss    = Color.red
    static let neutral = Color(.systemGray)

    static let signalBuy  = Color.green
    static let signalSell = Color.red

    static let chartBackground  = Color(.systemBackground)
    static let panelBackground  = Color(.secondarySystemBackground)
    static let macdPositive     = Color.green.opacity(0.8)
    static let macdNegative     = Color.red.opacity(0.8)

    // Indicator line colors — distinct and accessible
    static let indicatorEMA9  = Color.orange          // EMA9
    static let indicatorVWAP  = Color(red: 0.5, green: 0.0, blue: 0.8)  // purple
    static let indicatorBB    = Color(red: 0.0, green: 0.5, blue: 0.9)  // steel blue
    static let indicatorMACD  = Color.blue
    static let indicatorSig   = Color.orange
    static let indicatorRSI   = Color(red: 0.6, green: 0.0, blue: 0.8)  // violet

    static func forChange(_ pct: Double?) -> Color {
        guard let p = pct else { return .neutral }
        return p >= 0 ? .gain : .loss
    }

    static func forSignal(_ direction: SignalDirection) -> Color {
        direction == .buy ? .signalBuy : .signalSell
    }
}
