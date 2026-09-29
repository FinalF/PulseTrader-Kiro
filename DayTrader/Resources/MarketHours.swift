// MarketHours.swift — NYSE/NASDAQ regular session helpers (ET)
import Foundation

enum MarketHours {
    private static let easternTZ = TimeZone(identifier: "America/New_York")!

    /// Is the US stock market currently in regular trading hours?
    static var isOpen: Bool { isOpen(at: Date()) }

    /// Testable: regular session Mon–Fri 09:30–16:00 ET (no holiday check in MVP).
    static func isOpen(at date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ
        let weekday = cal.component(.weekday, from: date)
        guard weekday >= 2 && weekday <= 6 else { return false }   // Mon–Fri only
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let totalMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return totalMin >= 9 * 60 + 30 && totalMin < 16 * 60
    }

    /// Human-readable status badge label when market is closed
    static var statusLabel: String { statusLabel(at: Date()) }

    /// Testable variant.
    static func statusLabel(at date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ
        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return "Market Closed · Weekend" }
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let totalMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if totalMin < 9 * 60 + 30  { return "Pre-Market" }
        if totalMin >= 16 * 60     { return "After-Hours" }
        return "Market Closed"
    }
}
