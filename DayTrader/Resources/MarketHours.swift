// MarketHours.swift — NYSE/NASDAQ regular session helpers (ET)
import Foundation

enum MarketHours {
    private static let easternTZ = TimeZone(identifier: "America/New_York")!

    /// Is the US stock market currently in regular trading hours?
    /// Regular session: Mon–Fri 09:30–16:00 ET (no holiday check in MVP)
    static var isOpen: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        let now     = Date()
        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }   // Mon–Fri only

        let comps   = cal.dateComponents([.hour, .minute], from: now)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let totalMin = h * 60 + m
        return totalMin >= 9 * 60 + 30 && totalMin < 16 * 60
    }

    /// Human-readable status badge label when market is closed
    static var statusLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ

        let now     = Date()
        let weekday = cal.component(.weekday, from: now)

        // Weekend
        if weekday == 1 || weekday == 7 { return "Market Closed · Weekend" }

        let comps   = cal.dateComponents([.hour, .minute], from: now)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let totalMin = h * 60 + m

        if totalMin < 9 * 60 + 30  { return "Pre-Market" }
        if totalMin >= 16 * 60     { return "After-Hours" }
        return "Market Closed"
    }
}
