// BacktestTests.swift
// Run with Cmd+U in Xcode, or:
//   xcodebuild test -project DayTrader.xcodeproj -scheme DayTrader \
//     -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0"
//
// The report is printed to the test log / console. These tests do not assert
// profitability (a strategy is not "wrong" for losing money) — they assert the
// backtester ran and produced a coherent result, then print the metrics.

import XCTest
@testable import DayTrader

final class BacktestTests: XCTestCase {

    // Symbols to backtest. Uses whatever provider is active:
    //   • No Alpaca key  → MockMarketDataService (synthetic GBM data)
    //   • Alpaca key set → real historical bars from Alpaca
    private let symbols = ["AAPL", "NVDA", "TSLA", "MSFT", "SPY"]

    /// Backtest each symbol over a multi-day window and print a report.
    func testStrategyBacktest() async throws {
        // To use REAL Alpaca data instead of mock, uncomment and paste keys:
        // let service: MarketDataService = AlpacaService(apiKey: "PK...", apiSecret: "...")
        let service: MarketDataService = MockMarketDataService(tickInterval: 1)

        var aggregate = (trades: 0, wins: 0, gp: 0.0, gl: 0.0)

        for symbol in symbols {
            // 1M window gives more trades than a single session
            let bars = try await service.fetchBars(symbol: symbol, range: .oneMonth)
            XCTAssertFalse(bars.isEmpty, "\(symbol) returned no bars")

            let result = Backtester.run(bars: bars)
            print(result.report())

            // Coherence checks (not profitability)
            XCTAssertEqual(result.wins + result.losses, result.tradesClosed)
            XCTAssertGreaterThanOrEqual(result.signalsGenerated, 0)

            aggregate.trades += result.tradesClosed
            aggregate.wins   += result.wins
            aggregate.gp     += result.grossProfit
            aggregate.gl     += result.grossLoss
        }

        // Portfolio-level summary across all symbols
        let winRate = aggregate.trades == 0 ? 0 : Double(aggregate.wins) / Double(aggregate.trades)
        let pf = aggregate.gl == 0 ? Double.infinity : aggregate.gp / aggregate.gl
        print("""

        ╔═══════════════════════════════════════════╗
        ║  AGGREGATE across \(symbols.count) symbols
        ║  Total trades:  \(aggregate.trades)
        ║  Win rate:      \(String(format: "%.1f%%", winRate * 100))
        ║  Profit factor: \(pf == .infinity ? "∞" : String(format: "%.2f", pf))
        ║  Net P&L:       \(String(format: "%+.2f", aggregate.gp - aggregate.gl))
        ╚═══════════════════════════════════════════╝

        NOTE: Synthetic (mock) data has no real market structure, so these
        numbers only validate the backtest mechanics. Swap in AlpacaService
        (see comment at top) for a meaningful result on real history.
        """)
    }
}
