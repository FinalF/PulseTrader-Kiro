// TradeViewModel.swift — paper order submission and position management
import Foundation
import Combine

@MainActor
final class TradeViewModel: ObservableObject {

    @Published var portfolio: Portfolio
    @Published var livePrices: [String: Double] = [:]
    @Published var orderError: String?

    // MARK: - Auto-trading (paper only, opt-in)

    /// Master switch. Persisted; default OFF.
    @Published var autoTradingEnabled: Bool {
        didSet { UserDefaults.standard.set(autoTradingEnabled, forKey: autoKey) }
    }
    /// Only auto-trade signals at/above this confidence (0–1). Persisted.
    @Published var autoMinConfidence: Double {
        didSet { UserDefaults.standard.set(autoMinConfidence, forKey: autoConfKey) }
    }
    /// Log of auto actions for display in the UI.
    @Published private(set) var autoLog: [String] = []

    // Risk parameters for auto position sizing
    private let riskPerTradePct = 0.01     // 1% of equity risked per trade
    private let positionCapPct  = 0.10     // 10% of equity max per position

    private let autoKey     = "auto_trading_enabled"
    private let autoConfKey = "auto_trading_min_confidence"

    init(portfolio: Portfolio = Portfolio()) {
        self.portfolio = portfolio
        self.autoTradingEnabled = UserDefaults.standard.bool(forKey: "auto_trading_enabled")
        let savedConf = UserDefaults.standard.double(forKey: "auto_trading_min_confidence")
        self.autoMinConfidence = savedConf > 0 ? savedConf : 0.60
        loadPortfolio()
    }

    // MARK: - Position sizing (min of 1% risk, cash cap, 10% position cap)

    /// Shares to buy given entry and stop, respecting all three constraints.
    func positionSize(entry: Double, stop: Double) -> Int {
        guard entry > 0 else { return 0 }
        let equity = totalEquity

        // ① risk-based: risk at most riskPerTradePct of equity on the stop distance
        let riskPerShare = abs(entry - stop)
        let riskShares = riskPerShare > 0
            ? (equity * riskPerTradePct) / riskPerShare
            : .greatestFiniteMagnitude

        // ② cash cap: can't spend more cash than we have
        let cashShares = portfolio.cash / entry

        // ③ position cap: no single position exceeds positionCapPct of equity
        let capShares = (equity * positionCapPct) / entry

        let shares = Int(min(riskShares, cashShares, capShares).rounded(.down))
        return max(0, shares)
    }

    // MARK: - Order submission

    struct PaperOrder {
        var symbol: String
        var direction: TradeDirection = .long
        var orderType: OrderType      = .market
        var quantity: Int
        var limitPrice: Double?
        var stopLoss: Double
        var takeProfit: Double
    }

    func submitOrder(_ order: PaperOrder, currentPrice: Double) {
        guard order.quantity > 0 else {
            orderError = "Quantity must be > 0"
            return
        }

        let fillPrice: Double = {
            switch order.orderType {
            case .market:
                // Simulate 1-tick slippage
                let tick = currentPrice * 0.0001
                return order.direction == .long
                    ? currentPrice + tick
                    : currentPrice - tick
            case .limit:
                return order.limitPrice ?? currentPrice
            }
        }()

        let cost = fillPrice * Double(order.quantity)
        guard portfolio.cash >= cost else {
            orderError = "Insufficient cash (\(String(format: "$%.2f", portfolio.cash)))"
            return
        }

        let trade = Trade(symbol: order.symbol,
                          direction: order.direction,
                          orderType: order.orderType,
                          entryPrice: fillPrice,
                          quantity: order.quantity,
                          stopLoss: order.stopLoss,
                          takeProfit: order.takeProfit)

        portfolio.cash -= cost
        portfolio.openTrades.append(trade)
        orderError = nil
        savePortfolio()
    }

    func closePosition(_ trade: Trade, at price: Double) {
        guard let idx = portfolio.openTrades.firstIndex(where: { $0.id == trade.id }) else { return }
        var closed = portfolio.openTrades.remove(at: idx)
        closed.exitPrice = price
        closed.exitTime  = Date()

        // Return proceeds to cash
        let proceeds = price * Double(closed.quantity)
        portfolio.cash += proceeds
        portfolio.closedTrades.append(closed)
        savePortfolio()
    }

    func closeAll(prices: [String: Double]) {
        for trade in portfolio.openTrades {
            let price = prices[trade.symbol] ?? trade.entryPrice
            closePosition(trade, at: price)
        }
    }

    // MARK: - Auto-trading handlers

    /// Called when a new signal fires. Opens a paper position automatically
    /// if auto-trading is on, confidence clears the bar, and we're flat on that symbol.
    func handleAutoSignal(_ signal: TradeSignal) {
        guard autoTradingEnabled else { return }
        guard signal.confidence >= autoMinConfidence else { return }
        // v1: long only
        guard signal.direction == .buy else {
            log("Skipped \(signal.symbol) SELL signal (v1 is long-only)")
            return
        }
        // One position per symbol
        guard !portfolio.openTrades.contains(where: { $0.symbol == signal.symbol }) else { return }

        let shares = positionSize(entry: signal.entryPrice, stop: signal.stopLoss)
        guard shares > 0 else {
            log("Skipped \(signal.symbol): position size rounded to 0")
            return
        }
        let order = PaperOrder(symbol: signal.symbol, quantity: shares,
                               stopLoss: signal.stopLoss, takeProfit: signal.takeProfit)
        submitOrder(order, currentPrice: signal.entryPrice)
        if orderError == nil {
            log("BUY \(shares) \(signal.symbol) @ \(String(format: "%.2f", signal.entryPrice)) "
                + "(conf \(signal.displayConfidence), stop \(String(format: "%.2f", signal.stopLoss)), "
                + "target \(String(format: "%.2f", signal.takeProfit)))")
        } else {
            log("Order rejected for \(signal.symbol): \(orderError ?? "")")
        }
    }

    /// Called on each live price update. Closes any open position whose
    /// stop-loss or take-profit has been hit (auto-trading only).
    private func checkStopsAndTargets(symbol: String, price: Double) {
        guard autoTradingEnabled else { return }
        for trade in portfolio.openTrades where trade.symbol == symbol {
            // v1 is long-only
            var hit: String? = nil
            if price <= trade.stopLoss        { hit = "stop-loss" }
            else if price >= trade.takeProfit { hit = "take-profit" }
            if let reason = hit {
                closePosition(trade, at: price)
                let pnl = trade.realizedPnL ?? (Double(trade.quantity) * (price - trade.entryPrice))
                log("CLOSE \(trade.symbol) @ \(String(format: "%.2f", price)) "
                    + "(\(reason), P&L \(String(format: "%+.2f", pnl)))")
            }
        }
    }

    private func log(_ msg: String) {
        let time = Date().formatted(.dateTime.hour().minute().second())
        autoLog.insert("[\(time)] \(msg)", at: 0)
        if autoLog.count > 50 { autoLog.removeLast(autoLog.count - 50) }
    }

    // MARK: - Mark-to-market

    func updatePrice(symbol: String, price: Double) {
        livePrices[symbol] = price
        checkStopsAndTargets(symbol: symbol, price: price)
    }

    func unrealizedPnL(for trade: Trade) -> Double {
        let price = livePrices[trade.symbol] ?? trade.entryPrice
        return trade.unrealizedPnL(currentPrice: price)
    }

    var totalUnrealizedPnL: Double {
        portfolio.openTrades.reduce(0) { $0 + unrealizedPnL(for: $1) }
    }

    var totalEquity: Double {
        portfolio.totalEquity(prices: livePrices)
    }

    // MARK: - Suggested sizing (5% of equity per position)

    func suggestedQuantity(price: Double) -> Int {
        let maxPositionValue = totalEquity * Configuration.Risk.maxPositionSizePct
        return max(1, Int(maxPositionValue / price))
    }

    // MARK: - Persistence

    private let portfolioKey = "paper_portfolio"

    private func savePortfolio() {
        if let data = try? JSONEncoder().encode(portfolio) {
            UserDefaults.standard.set(data, forKey: portfolioKey)
        }
    }

    private func loadPortfolio() {
        guard let data = UserDefaults.standard.data(forKey: portfolioKey),
              let saved = try? JSONDecoder().decode(Portfolio.self, from: data) else { return }
        portfolio = saved
    }

    func resetPortfolio() {
        portfolio = Portfolio()
        UserDefaults.standard.removeObject(forKey: portfolioKey)
    }
}
