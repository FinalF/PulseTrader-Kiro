// WatchlistViewModel.swift
import Foundation
import Combine

enum WatchlistSortOrder: String, CaseIterable {
    case signal    = "Signal"
    case change    = "% Change"
    case alpha     = "Symbol"
}

@MainActor
final class WatchlistViewModel: ObservableObject {

    @Published var stocks: [Stock] = []
    @Published var sortOrder: WatchlistSortOrder = .signal
    @Published var searchText: String = ""
    @Published var errorMessage: String?

    private let service: MarketDataService
    private let signalEngine: SignalEngine
    private var cancellables = Set<AnyCancellable>()
    private var barCache: [String: [Quote]] = [:]

    init(service: MarketDataService = MockMarketDataService(),
         signalEngine: SignalEngine = SignalEngine()) {
        self.service      = service
        self.signalEngine = signalEngine
        self.stocks       = Stock.defaults
        loadWatchlist()
        // Pre-populate prices immediately on init (avoids "--" on first render)
        if let mock = service as? MockMarketDataService {
            // Mock: use pre-generated cache synchronously
            for i in stocks.indices {
                let sym = stocks[i].symbol
                if let last = mock.barCache[sym]?.last {
                    stocks[i].latestQuote = last
                }
            }
        }
        // Note: price loading for real services happens in startStreaming()
        // (serial, to avoid Alpaca free-tier rate limiting)
    }

    // MARK: - Public API

    var displayedStocks: [Stock] {
        let filtered = searchText.isEmpty
            ? stocks
            : stocks.filter {
                $0.symbol.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
              }
        return filtered.sorted(by: sortComparator)
    }

    func startStreaming() {
        let symbols = stocks.map(\.symbol)
        // Fetch prices serially to avoid Alpaca free-tier rate limits,
        // then subscribe to each live stream.
        Task {
            for symbol in symbols {
                await loadInitialBars(for: symbol)
            }
        }
        for symbol in symbols {
            subscribeLive(for: symbol)
        }
    }

    private func loadInitialBars(for symbol: String) async {
        do {
            var bars = try await service.fetchBars(symbol: symbol, range: .oneDay)
            if bars.isEmpty {
                bars = try await service.fetchBars(symbol: symbol, range: .fiveDay)
            }
            barCache[symbol] = bars
            if let last = bars.last {
                updateStock(symbol: symbol, newBar: last)
                runIndicatorsAndSignal(symbol: symbol)
            }
        } catch {
            errorMessage = "\(symbol): \(error.localizedDescription)"
        }
    }

    private func subscribeLive(for symbol: String) {
        service.quotePublisher(for: symbol)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quote in
                guard let self else { return }
                self.barCache[symbol, default: []].append(quote)
                self.updateStock(symbol: symbol, newBar: quote)
                self.runIndicatorsAndSignal(symbol: symbol)
            }
            .store(in: &cancellables)
    }

    func stopStreaming() {
        cancellables.removeAll()
    }

    func addStock(_ stock: Stock) {
        guard !stocks.contains(where: { $0.symbol == stock.symbol }) else { return }
        stocks.append(stock)
        saveWatchlist()
        Task { await loadInitialBars(for: stock.symbol) }
        subscribeLive(for: stock.symbol)
    }

    func removeStock(symbol: String) {
        stocks.removeAll { $0.symbol == symbol }
        saveWatchlist()
    }

    // MARK: - Private



    private func updateStock(symbol: String, newBar: Quote?) {
        guard let idx = stocks.firstIndex(where: { $0.symbol == symbol }) else { return }
        stocks[idx].latestQuote = newBar
    }

    private func runIndicatorsAndSignal(symbol: String) {
        guard let bars = barCache[symbol],
              let bundle = IndicatorEngine.compute(quotes: bars) else { return }
        let barIndex = bars.count - 1
        if let signal = signalEngine.evaluate(quotes: bars,
                                               indicators: bundle,
                                               barIndex: barIndex) {
            if let idx = stocks.firstIndex(where: { $0.symbol == symbol }) {
                stocks[idx].latestSignal = signal
            }
        }
    }

    private var sortComparator: (Stock, Stock) -> Bool {
        switch sortOrder {
        case .signal:
            return {
                let lhs = $0.latestSignal?.confidence ?? 0
                let rhs = $1.latestSignal?.confidence ?? 0
                return lhs > rhs
            }
        case .change:
            return { ($0.changePercent ?? 0) > ($1.changePercent ?? 0) }
        case .alpha:
            return { $0.symbol < $1.symbol }
        }
    }

    // MARK: - Persistence

    private let watchlistKey = "watchlist_symbols"

    private func saveWatchlist() {
        let symbols = stocks.map { $0.symbol }
        UserDefaults.standard.set(symbols, forKey: watchlistKey)
    }

    private func loadWatchlist() {
        // If the user has a saved watchlist, it REPLACES the defaults entirely
        // (so removed stocks stay removed across launches).
        guard let saved = UserDefaults.standard.stringArray(forKey: watchlistKey) else {
            return   // no saved list yet → keep defaults from init
        }
        // Preserve display names for known default symbols
        let nameLookup = Dictionary(uniqueKeysWithValues:
            Stock.defaults.map { ($0.symbol, $0.name) })
        stocks = saved.map { sym in
            Stock(symbol: sym, name: nameLookup[sym] ?? sym)
        }
    }
}
