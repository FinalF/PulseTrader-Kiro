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

    static func forChange(_ pct: Double?) -> Color {
        guard let p = pct else { return .neutral }
        return p >= 0 ? .gain : .loss
    }

    static func forSignal(_ direction: SignalDirection) -> Color {
        direction == .buy ? .signalBuy : .signalSell
    }
}
