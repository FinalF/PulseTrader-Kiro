// Trade.swift — paper trade record
import Foundation

enum TradeDirection: String, Codable { case long }   // v1: long only

enum OrderType: String, Codable { case market, limit }

struct Trade: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let direction: TradeDirection
    let orderType: OrderType
    let entryPrice: Double
    let entryTime: Date
    let quantity: Int
    var stopLoss: Double
    var takeProfit: Double
    var exitPrice: Double?
    var exitTime: Date?

    var isOpen: Bool { exitPrice == nil }

    func unrealizedPnL(currentPrice: Double) -> Double {
        Double(quantity) * (currentPrice - entryPrice)
    }

    var realizedPnL: Double? {
        guard let exit = exitPrice else { return nil }
        return Double(quantity) * (exit - entryPrice)
    }

    var displayPnL: String {
        guard let pnl = realizedPnL else { return "--" }
        return String(format: "%+.2f", pnl)
    }

    init(symbol: String, direction: TradeDirection = .long, orderType: OrderType = .market,
         entryPrice: Double, quantity: Int, stopLoss: Double, takeProfit: Double) {
        self.id          = UUID()
        self.symbol      = symbol
        self.direction   = direction
        self.orderType   = orderType
        self.entryPrice  = entryPrice
        self.entryTime   = Date()
        self.quantity    = quantity
        self.stopLoss    = stopLoss
        self.takeProfit  = takeProfit
    }
}
