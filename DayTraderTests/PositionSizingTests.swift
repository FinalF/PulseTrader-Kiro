// PositionSizingTests.swift — the three-constraint auto-trade sizing + P&L.
import XCTest
@testable import DayTrader

@MainActor
final class PositionSizingTests: XCTestCase {

    private func vm(cash: Double = 100_000) -> TradeViewModel {
        // Fresh portfolio; clear any persisted state influence by resetting.
        let t = TradeViewModel(portfolio: Portfolio(initialCapital: cash))
        return t
    }

    // Position cap (10%) binds when the stop is very tight.
    func testPositionCapBindsOnTightStop() {
        let t = vm(cash: 100_000)
        // entry 185, stop 183.80 → risk/share 1.20.
        // ① risk: 1000/1.20 = 833 sh ($154k) — would exceed cash & cap
        // ② cash: 100000/185 = 540 sh
        // ③ 10% cap: 10000/185 = 54 sh  ← smallest
        let shares = t.positionSize(entry: 185, stop: 183.80)
        XCTAssertEqual(shares, 54)
    }

    // Risk constraint binds when the stop is wide (so 1% risk allows few shares).
    func testRiskBindsOnWideStop() {
        let t = vm(cash: 100_000)
        // entry 100, stop 50 → risk/share 50.
        // ① risk: 1000/50 = 20 sh   ← smallest
        // ② cash: 100000/100 = 1000 sh
        // ③ cap: 10000/100 = 100 sh
        let shares = t.positionSize(entry: 100, stop: 50)
        XCTAssertEqual(shares, 20)
    }

    // Never returns shares that exceed available cash.
    func testNeverExceedsCash() {
        let t = vm(cash: 500)          // tiny account
        let shares = t.positionSize(entry: 185, stop: 184.9)
        XCTAssertLessThanOrEqual(Double(shares) * 185, 500)
    }

    // Zero/invalid entry → zero shares (no crash, no negative).
    func testZeroEntryReturnsZero() {
        let t = vm()
        XCTAssertEqual(t.positionSize(entry: 0, stop: 0), 0)
    }

    // Realized P&L sign is correct for a long trade.
    func testRealizedPnLLong() {
        var trade = Trade(symbol: "T", entryPrice: 100, quantity: 10,
                          stopLoss: 98, takeProfit: 106)
        trade.exitPrice = 106
        XCTAssertEqual(trade.realizedPnL!, 60, accuracy: 1e-9)   // (106-100)*10
    }

    // Portfolio win rate & profit factor.
    func testPortfolioMetrics() {
        var p = Portfolio(initialCapital: 100_000)
        var win = Trade(symbol: "A", entryPrice: 100, quantity: 10, stopLoss: 98, takeProfit: 110)
        win.exitPrice = 110                              // +100
        var loss = Trade(symbol: "B", entryPrice: 100, quantity: 10, stopLoss: 95, takeProfit: 110)
        loss.exitPrice = 95                              // -50
        p.closedTrades = [win, loss]
        XCTAssertEqual(p.winRate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.profitFactor, 2.0, accuracy: 1e-9)   // 100 / 50
    }
}
