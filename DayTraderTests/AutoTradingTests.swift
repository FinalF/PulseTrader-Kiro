// AutoTradingTests.swift — auto-open on signal, auto-close on stop/target.
import XCTest
@testable import DayTrader

@MainActor
final class AutoTradingTests: XCTestCase {

    private func makeVM(enabled: Bool, minConf: Double = 0.5, cash: Double = 100_000) -> TradeViewModel {
        let t = TradeViewModel(portfolio: Portfolio(initialCapital: cash))
        t.autoTradingEnabled = enabled
        t.autoMinConfidence = minConf
        return t
    }

    private func buySignal(_ symbol: String = "AAPL", conf: Double = 0.7,
                           entry: Double = 100, stop: Double = 95, target: Double = 110) -> TradeSignal {
        TradeSignal(symbol: symbol, timestamp: Date(), direction: .buy,
                    confidence: conf, triggeringIndicators: ["RSI"],
                    entryPrice: entry, stopLoss: stop, takeProfit: target)
    }

    // Auto-trading OFF → no position opened.
    func testDisabled_noPosition() {
        let t = makeVM(enabled: false)
        t.handleAutoSignal(buySignal())
        XCTAssertTrue(t.portfolio.openTrades.isEmpty)
    }

    // Below confidence threshold → skipped.
    func testBelowConfidence_skipped() {
        let t = makeVM(enabled: true, minConf: 0.8)
        t.handleAutoSignal(buySignal(conf: 0.6))
        XCTAssertTrue(t.portfolio.openTrades.isEmpty)
    }

    // Qualifying BUY → opens exactly one position with the signal's stop/target.
    func testQualifyingBuy_opensPosition() {
        let t = makeVM(enabled: true, minConf: 0.5)
        t.handleAutoSignal(buySignal(entry: 100, stop: 95, target: 110))
        XCTAssertEqual(t.portfolio.openTrades.count, 1)
        let tr = t.portfolio.openTrades[0]
        XCTAssertEqual(tr.symbol, "AAPL")
        XCTAssertEqual(tr.stopLoss, 95, accuracy: 1e-9)
        XCTAssertEqual(tr.takeProfit, 110, accuracy: 1e-9)
        XCTAssertGreaterThan(tr.quantity, 0)
    }

    // One position per symbol — a second signal is ignored while one is open.
    func testOnePositionPerSymbol() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal())
        t.handleAutoSignal(buySignal())
        XCTAssertEqual(t.portfolio.openTrades.count, 1)
    }

    // SELL signal ignored (v1 long-only).
    func testSellSignalIgnored() {
        let t = makeVM(enabled: true)
        let sell = TradeSignal(symbol: "AAPL", timestamp: Date(), direction: .sell,
                               confidence: 0.9, triggeringIndicators: ["RSI"],
                               entryPrice: 100, stopLoss: 105, takeProfit: 90)
        t.handleAutoSignal(sell)
        XCTAssertTrue(t.portfolio.openTrades.isEmpty)
    }

    // Price hits stop-loss → position auto-closes with a loss.
    func testAutoCloseOnStop() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal(entry: 100, stop: 95, target: 110))
        XCTAssertEqual(t.portfolio.openTrades.count, 1)
        t.updatePrice(symbol: "AAPL", price: 94)   // below stop
        XCTAssertTrue(t.portfolio.openTrades.isEmpty, "should have closed")
        XCTAssertEqual(t.portfolio.closedTrades.count, 1)
        XCTAssertLessThan(t.portfolio.closedTrades[0].realizedPnL ?? 0, 0, "stop → loss")
    }

    // Price hits take-profit → position auto-closes with a gain.
    func testAutoCloseOnTarget() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal(entry: 100, stop: 95, target: 110))
        t.updatePrice(symbol: "AAPL", price: 111)  // above target
        XCTAssertTrue(t.portfolio.openTrades.isEmpty)
        XCTAssertEqual(t.portfolio.closedTrades.count, 1)
        XCTAssertGreaterThan(t.portfolio.closedTrades[0].realizedPnL ?? 0, 0, "target → gain")
    }

    // Price between stop and target → position stays open.
    func testNoCloseInsideBand() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal(entry: 100, stop: 95, target: 110))
        t.updatePrice(symbol: "AAPL", price: 103)
        XCTAssertEqual(t.portfolio.openTrades.count, 1, "should stay open")
    }

    // Auto-close only runs when auto-trading is on.
    func testNoAutoCloseWhenDisabled() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal(entry: 100, stop: 95, target: 110))
        t.autoTradingEnabled = false               // turn off after opening
        t.updatePrice(symbol: "AAPL", price: 94)   // would hit stop
        XCTAssertEqual(t.portfolio.openTrades.count, 1, "disabled → no auto-close")
    }

    // Activity log records the auto actions.
    func testActivityLogged() {
        let t = makeVM(enabled: true)
        t.handleAutoSignal(buySignal())
        XCTAssertFalse(t.autoLog.isEmpty)
        XCTAssertTrue(t.autoLog.first?.contains("BUY") ?? false)
    }
}
