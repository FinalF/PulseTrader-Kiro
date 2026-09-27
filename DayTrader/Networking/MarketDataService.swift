// MarketDataService.swift — protocol all providers must conform to
import Foundation
import Combine

/// Chart range — used to decide intraday vs daily bars
enum ChartRange: String, CaseIterable {
    case oneDay      = "1D"
    case fiveDay     = "5D"
    case oneMonth    = "1M"
    case threeMonth  = "3M"
    case oneYear     = "1Y"

    var isIntraday: Bool { self == .oneDay }

    /// How many calendar days of history to request
    var calendarDays: Int {
        switch self {
        case .oneDay:     return 1
        case .fiveDay:    return 5
        case .oneMonth:   return 30
        case .threeMonth: return 90
        case .oneYear:    return 365
        }
    }

    /// Alpaca timeframe string for each range
    var alpacaTimeframe: String {
        switch self {
        case .oneDay:    return "1Min"
        case .fiveDay:   return "15Min"
        case .oneMonth:  return "1Hour"
        case .threeMonth, .oneYear: return "1Day"
        }
    }

    /// Bar limit to request (approximate)
    var barLimit: Int {
        switch self {
        case .oneDay:     return 390          // full session at 1-min
        case .fiveDay:    return 5 * 26       // 5 days × 26 fifteen-min bars
        case .oneMonth:   return 30 * 7       // ~7 hourly bars/day
        case .threeMonth: return 90
        case .oneYear:    return 252
        }
    }
}

protocol MarketDataService {
    /// Fetch bars for the current/last session (intraday, 1-min)
    func fetchBars(symbol: String, limit: Int) async throws -> [Quote]

    /// Fetch bars for a given range (used by chart)
    func fetchBars(symbol: String, range: ChartRange) async throws -> [Quote]

    /// Publisher that emits a new Quote on each simulated/live bar close
    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never>
}
