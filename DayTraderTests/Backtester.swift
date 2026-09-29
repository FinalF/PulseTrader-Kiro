// Backtester.swift
// A simple event-driven backtester that replays historical bars through the
// live SignalEngine and simulates taking every signal to its stop or target.
//
// This is a DEV/RESEARCH tool — it is compiled into the test target only,
// never into the shipping app.
//
// IMPORTANT: A profitable backtest does NOT guarantee profitable live trading.
// Results ignore slippage beyond a fixed assumption, commissions, partial fills,
// and survivorship/look-ahead subtleties. Treat output as a sanity check on the
// rule logic, not a promise of returns.

import Foundation
@testable import DayTrader

struct BacktestResult {
    var symbol: String
    var totalBars: Int
    var signalsGenerated: Int
    var tradesClosed: Int
    var wins: Int
    var losses: Int
    var grossProfit: Double
    var grossLoss: Double      // stored as a positive number
    var returnPct: Double      // total P&L / starting equity
    var maxDrawdownPct: Double

    var winRate: Double { tradesClosed == 0 ? 0 : Double(wins) / Double(tradesClosed) }
    var profitFactor: Double { grossLoss == 0 ? (grossProfit > 0 ? .infinity : 0) : grossProfit / grossLoss }
    var avgWin: Double { wins == 0 ? 0 : grossProfit / Double(wins) }
    var avgLoss: Double { losses == 0 ? 0 : grossLoss / Double(losses) }
    var expectancy: Double {
        tradesClosed == 0 ? 0 : (grossProfit - grossLoss) / Double(tradesClosed)
    }

    func report() -> String {
        """
        ═══════════════════════════════════════════
        Backtest — \(symbol)
        ═══════════════════════════════════════════
        Bars processed:    \(totalBars)
        Signals generated: \(signalsGenerated)
        Trades closed:     \(tradesClosed)  (\(wins)W / \(losses)L)
        Win rate:          \(String(format: "%.1f%%", winRate * 100))
        Profit factor:     \(profitFactor == .infinity ? "∞" : String(format: "%.2f", profitFactor))
        Avg win / loss:    \(String(format: "%+.2f", avgWin)) / \(String(format: "%.2f", -avgLoss))
        Expectancy/trade:  \(String(format: "%+.2f", expectancy))
        Total return:      \(String(format: "%+.2f%%", returnPct * 100))
        Max drawdown:      \(String(format: "%.2f%%", maxDrawdownPct * 100))
        ═══════════════════════════════════════════
        """
    }
}

/// One open simulated position during the backtest.
private struct OpenPosition {
    let direction: SignalDirection
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    let shares: Double
}

enum Backtester {

    /// Run the strategy over a series of bars.
    /// - Parameters:
    ///   - bars: chronological 1-min (or aggregated) bars for one symbol
    ///   - startingEquity: notional account size (for % return)
    ///   - riskPerTradePct: fraction of equity risked per trade (position sizing)
    ///   - slippagePerShare: fixed slippage applied to entry and exit fills
    static func run(bars: [Quote],
                    startingEquity: Double = 100_000,
                    riskPerTradePct: Double = 0.01,
                    slippagePerShare: Double = 0.01) -> BacktestResult {

        let symbol = bars.first?.symbol ?? "?"
        var result = BacktestResult(
            symbol: symbol, totalBars: bars.count, signalsGenerated: 0,
            tradesClosed: 0, wins: 0, losses: 0,
            grossProfit: 0, grossLoss: 0, returnPct: 0, maxDrawdownPct: 0
        )

        // Fresh engine per run so cooldown state doesn't leak between symbols
        let engine = SignalEngine()

        var equity = startingEquity
        var peakEquity = startingEquity
        var maxDD = 0.0
        var open: OpenPosition?

        // Minimum bars before indicators are valid
        let minBars = Configuration.Indicators.macdSlow + Configuration.Indicators.macdSignal

        for i in minBars..<bars.count {
            let window = Array(bars[0...i])
            let bar = bars[i]

            // 1) Manage an open position first — check stop / target against this bar
            if let pos = open {
                var exitPrice: Double?
                switch pos.direction {
                case .buy:
                    if bar.low <= pos.stopLoss   { exitPrice = pos.stopLoss }
                    else if bar.high >= pos.takeProfit { exitPrice = pos.takeProfit }
                case .sell:
                    if bar.high >= pos.stopLoss  { exitPrice = pos.stopLoss }
                    else if bar.low <= pos.takeProfit  { exitPrice = pos.takeProfit }
                }
                if let raw = exitPrice {
                    // Apply slippage against us on exit
                    let fill = pos.direction == .buy ? raw - slippagePerShare : raw + slippagePerShare
                    let pnl = (pos.direction == .buy)
                        ? (fill - pos.entryPrice) * pos.shares
                        : (pos.entryPrice - fill) * pos.shares
                    equity += pnl
                    result.tradesClosed += 1
                    if pnl >= 0 { result.wins += 1; result.grossProfit += pnl }
                    else        { result.losses += 1; result.grossLoss += -pnl }

                    peakEquity = max(peakEquity, equity)
                    maxDD = max(maxDD, (peakEquity - equity) / peakEquity)
                    open = nil
                }
            }

            // 2) Only look for a new signal if flat
            guard open == nil else { continue }
            guard let bundle = IndicatorEngine.compute(quotes: window) else { continue }

            if let signal = engine.evaluate(quotes: window, indicators: bundle, barIndex: i) {
                result.signalsGenerated += 1
                // Position sizing: risk `riskPerTradePct` of equity on the stop distance
                let riskPerShare = abs(signal.entryPrice - signal.stopLoss)
                guard riskPerShare > 0 else { continue }
                let dollarRisk = equity * riskPerTradePct
                let shares = (dollarRisk / riskPerShare).rounded(.down)
                guard shares > 0 else { continue }

                let entryFill = signal.direction == .buy
                    ? signal.entryPrice + slippagePerShare
                    : signal.entryPrice - slippagePerShare

                open = OpenPosition(direction: signal.direction,
                                    entryPrice: entryFill,
                                    stopLoss: signal.stopLoss,
                                    takeProfit: signal.takeProfit,
                                    shares: shares)
            }
        }

        result.returnPct = (equity - startingEquity) / startingEquity
        result.maxDrawdownPct = maxDD
        return result
    }
}
