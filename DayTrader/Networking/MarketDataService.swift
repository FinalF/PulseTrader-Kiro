// MarketDataService.swift — protocol all providers must conform to
import Foundation
import Combine

protocol MarketDataService {
    /// Fetch historical 1-min bars for the current/last session
    func fetchBars(symbol: String, limit: Int) async throws -> [Quote]

    /// Publisher that emits a new Quote on each simulated bar close
    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never>
}
