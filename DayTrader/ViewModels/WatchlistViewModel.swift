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
        } else {
            // Real service (Alpaca): fetch latest quote for all symbols right away
            let symbols = stocks.map(\.symbol)
            Task {
                await withTaskGroup(of: (String, Quote?).self) { group in
                    for sym in symbols {
                        group.addTask { [weak service] in
                            let q = try? await service?.fetchLatestQuote(symbol: sym)
                            return (sym, q)
                        }
                    }
                    for await (sym, quote) in group {
                        if let quote, let idx = self.stocks.firstIndex(where: { $0.symbol == sym }) {
                            self.stocks[idx].latestQuote = quote
                        }
                    }
                }
            }
        }
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
        for symbol in stocks.map(\.symbol) {
            startStream(for: symbol)
        }
    }

    func stopStreaming() {
        cancellables.removeAll()
    }

    func addStock(_ stock: Stock) {
        guard !stocks.contains(where: { $0.symbol == stock.symbol }) else { return }
        stocks.append(stock)
        saveWatchlist()
        startStream(for: stock.symbol)
    }

    func removeStock(symbol: String) {
        stocks.removeAll { $0.symbol == symbol }
        saveWatchlist()
    }

    // MARK: - Private

    private func startStream(for symbol: String) {
        Task {
            do {
                let bars = try await service.fetchBars(symbol: symbol,
                                                       limit: Configuration.intraDayBarsToFetch)
                barCache[symbol] = bars
                if let last = bars.last {
                    updateStock(symbol: symbol, newBar: last)
                } else {
                    // No intraday bars (market closed) — fetch last known price
                    if let latest = try? await service.fetchLatestQuote(symbol: symbol) {
                        updateStock(symbol: symbol, newBar: latest)
                    }
                }
                runIndicatorsAndSignal(symbol: symbol)
            } catch {
                // Still try latest quote so price shows even on error
                if let latest = try? await service.fetchLatestQuote(symbol: symbol) {
                    updateStock(symbol: symbol, newBar: latest)
                }
                errorMessage = "Failed to load \(symbol): \(error.localizedDescription)"
            }
        }

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
        guard let saved = UserDefaults.standard.stringArray(forKey: watchlistKey),
              !saved.isEmpty else { return }
        // Merge saved symbols with defaults
        let existing = Set(stocks.map { $0.symbol })
        for symbol in saved where !existing.contains(symbol) {
            stocks.append(Stock(symbol: symbol, name: symbol))
        }
    }
}
