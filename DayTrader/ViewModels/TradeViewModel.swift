// TradeViewModel.swift — paper order submission and position management
import Foundation
import Combine

@MainActor
final class TradeViewModel: ObservableObject {

    @Published var portfolio: Portfolio
    @Published var livePrices: [String: Double] = [:]
    @Published var orderError: String?

    init(portfolio: Portfolio = Portfolio()) {
        self.portfolio = portfolio
        loadPortfolio()
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

    // MARK: - Mark-to-market

    func updatePrice(symbol: String, price: Double) {
        livePrices[symbol] = price
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
