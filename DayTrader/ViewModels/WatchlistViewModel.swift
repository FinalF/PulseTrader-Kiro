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

    /// Called on every quote update — used to feed live prices to auto-trading.
    var onQuote: ((String, Double) -> Void)?
    /// Called when a watchlist symbol generates a new signal — routed to the
    /// shared SignalsViewModel (feed, notifications, auto-trading).
    var onSignal: ((TradeSignal) -> Void)?

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

    /// Symbols we already have a live subscription for (avoids duplicates when
    /// startStreaming is called more than once, e.g. on foreground).
    private var subscribedSymbols: Set<String> = []
    private var didLoadInitial = false

    /// Idempotent. Safe to call repeatedly; only does work for new symbols.
    func startStreaming() {
        let symbols = stocks.map(\.symbol)

        // Fetch initial bars once (serial to avoid Alpaca rate limits)
        if !didLoadInitial {
            didLoadInitial = true
            Task {
                for symbol in symbols { await loadInitialBars(for: symbol) }
            }
        }
        // Subscribe only symbols not already streaming
        for symbol in symbols where !subscribedSymbols.contains(symbol) {
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
        subscribedSymbols.insert(symbol)
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

    /// Tear down all live subscriptions (call when the app goes to the background,
    /// NOT when merely navigating between screens).
    func stopStreaming() {
        cancellables.removeAll()
        subscribedSymbols.removeAll()
    }

    func addStock(_ stock: Stock) {
        guard !stocks.contains(where: { $0.symbol == stock.symbol }) else { return }
        guard stocks.count < Configuration.maxWatchlistSymbols else {
            errorMessage = "Watchlist is full (max \(Configuration.maxWatchlistSymbols)). "
                + "Remove a stock before adding another."
            return
        }
        errorMessage = nil
        stocks.append(stock)
        saveWatchlist()
        Task { await loadInitialBars(for: stock.symbol) }
        subscribeLive(for: stock.symbol)
    }

    var isFull: Bool { stocks.count >= Configuration.maxWatchlistSymbols }

    func removeStock(symbol: String) {
        stocks.removeAll { $0.symbol == symbol }
        saveWatchlist()
    }

    // MARK: - Private



    private func updateStock(symbol: String, newBar: Quote?) {
        if let close = newBar?.close { onQuote?(symbol, close) }
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
            onSignal?(signal)   // forward to shared SignalsViewModel + auto-trading
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
