// Portfolio.swift — paper trading account state
import Foundation

struct Portfolio: Codable {
    var cash: Double
    var openTrades: [Trade]
    var closedTrades: [Trade]

    init(initialCapital: Double = Configuration.paperTradingInitialCapital) {
        self.cash         = initialCapital
        self.openTrades   = []
        self.closedTrades = []
    }

    func totalEquity(prices: [String: Double]) -> Double {
        let positionValue = openTrades.reduce(0.0) { sum, trade in
            let price = prices[trade.symbol] ?? trade.entryPrice
            return sum + trade.unrealizedPnL(currentPrice: price) + Double(trade.quantity) * trade.entryPrice
        }
        return cash + positionValue
    }

    var dailyPnL: Double {
        closedTrades
            .filter { Calendar.current.isDateInToday($0.entryTime) }
            .compactMap { $0.realizedPnL }
            .reduce(0, +)
    }

    var winRate: Double {
        let winners = closedTrades.filter { ($0.realizedPnL ?? 0) > 0 }.count
        return closedTrades.isEmpty ? 0 : Double(winners) / Double(closedTrades.count)
    }

    var profitFactor: Double {
        let gross = closedTrades.compactMap { $0.realizedPnL }
        let wins  = gross.filter { $0 > 0 }.reduce(0, +)
        let loss  = abs(gross.filter { $0 < 0 }.reduce(0, +))
        return loss > 0 ? wins / loss : wins > 0 ? .infinity : 0
    }

    var averageWin: Double {
        let wins = closedTrades.compactMap { $0.realizedPnL }.filter { $0 > 0 }
        return wins.isEmpty ? 0 : wins.reduce(0, +) / Double(wins.count)
    }

    var averageLoss: Double {
        let losses = closedTrades.compactMap { $0.realizedPnL }.filter { $0 < 0 }
        return losses.isEmpty ? 0 : losses.reduce(0, +) / Double(losses.count)
    }
}
