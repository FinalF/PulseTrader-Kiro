// ChartViewModel.swift
import Foundation
import Combine

enum Timeframe: String, CaseIterable {
    case oneMin    = "1m"
    case fiveMin   = "5m"
    case fifteenMin = "15m"

    var minuteCount: Int {
        switch self {
        case .oneMin:     return 1
        case .fiveMin:    return 5
        case .fifteenMin: return 15
        }
    }
}

@MainActor
final class ChartViewModel: ObservableObject {

    @Published var bars: [Quote] = []
    @Published var indicators: IndicatorBundle?
    @Published var signals: [TradeSignal] = []
    @Published var timeframe: Timeframe = .oneMin
    @Published var isLoading = true

    let symbol: String
    private let service: MarketDataService
    private let signalEngine: SignalEngine
    private let signalsVM: SignalsViewModel
    private var cancellables = Set<AnyCancellable>()
    private var rawBars: [Quote] = []   // always 1-min

    init(symbol: String,
         service: MarketDataService,
         signalEngine: SignalEngine,
         signalsVM: SignalsViewModel) {
        self.symbol       = symbol
        self.service      = service
        self.signalEngine = signalEngine
        self.signalsVM    = signalsVM
    }

    // MARK: - Lifecycle

    func load() {
        Task {
            do {
                let fetched = try await service.fetchBars(symbol: symbol,
                                                          limit: Configuration.intraDayBarsToFetch)
                rawBars = fetched
                recomputeDisplay()
                isLoading = false
                subscribeToLive()
            } catch {
                isLoading = false
            }
        }
    }

    func changeTimeframe(_ tf: Timeframe) {
        timeframe = tf
        recomputeDisplay()
    }

    // MARK: - Private

    private func subscribeToLive() {
        service.quotePublisher(for: symbol)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quote in
                guard let self else { return }
                self.rawBars.append(quote)
                self.recomputeDisplay()
            }
            .store(in: &cancellables)
    }

    private func recomputeDisplay() {
        let aggregated = aggregate(rawBars, minutesPerBar: timeframe.minuteCount)
        bars = aggregated

        guard let bundle = IndicatorEngine.compute(quotes: aggregated) else { return }
        indicators = bundle

        let barIndex = aggregated.count - 1
        if let signal = signalEngine.evaluate(quotes: aggregated,
                                               indicators: bundle,
                                               barIndex: barIndex) {
            signals.append(signal)
            signalsVM.append(signal)
        }
    }

    /// Aggregate 1-min bars into N-min bars
    private func aggregate(_ oneMins: [Quote], minutesPerBar: Int) -> [Quote] {
        guard minutesPerBar > 1, !oneMins.isEmpty else { return oneMins }
        var result: [Quote] = []
        var i = 0
        while i < oneMins.count {
            let slice = Array(oneMins[i..<min(i + minutesPerBar, oneMins.count)])
            guard let first = slice.first, let last = slice.last else { break }
            let high   = slice.map { $0.high }.max() ?? first.high
            let low    = slice.map { $0.low  }.min() ?? first.low
            let volume = slice.map { $0.volume }.reduce(0, +)
            result.append(Quote(symbol: first.symbol,
                                timestamp: first.timestamp,
                                open: first.open,
                                high: high,
                                low: low,
                                close: last.close,
                                volume: volume,
                                previousClose: first.previousClose))
            i += minutesPerBar
        }
        return result
    }
}
