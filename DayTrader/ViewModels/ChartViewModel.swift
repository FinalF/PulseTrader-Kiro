// ChartViewModel.swift
import Foundation
import Combine

enum Timeframe: String, CaseIterable {
    case oneMin     = "1m"
    case fiveMin    = "5m"
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
    @Published var range: ChartRange = .oneDay
    @Published var isLoading = true
    @Published var errorMessage: String?

    let symbol: String
    private let service: MarketDataService
    private let signalEngine: SignalEngine
    private let signalsVM: SignalsViewModel
    private var cancellables = Set<AnyCancellable>()
    private var intradayBars: [Quote] = []   // raw 1-min bars for intraday aggregation

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
        loadRange(range)
    }

    func changeTimeframe(_ tf: Timeframe) {
        timeframe = tf
        recomputeDisplay()
    }

    func changeRange(_ newRange: ChartRange) {
        guard newRange != range else { return }
        range = newRange
        // Reset timeframe to sensible default when leaving intraday
        if !newRange.isIntraday { timeframe = .oneMin }
        loadRange(newRange)
    }

    // MARK: - Private

    private func loadRange(_ r: ChartRange) {
        isLoading = true
        errorMessage = nil
        cancellables.removeAll()

        Task {
            do {
                let fetched = try await service.fetchBars(symbol: symbol, range: r)
                print("[Chart] \(symbol) \(r.rawValue): fetched \(fetched.count) bars")

                if r.isIntraday {
                    // 1D — filter to trading hours, then aggregate by timeframe
                    intradayBars = filterIntradayHours(fetched)
                    print("[Chart] after trading-hours filter: \(intradayBars.count) bars")
                    recomputeDisplay()
                    subscribeToLive()
                } else {
                    // 5D/1M/3M/1Y — bars are already at correct granularity,
                    // just strip weekends (no time-of-day filtering)
                    let filtered = stripWeekends(fetched)
                    print("[Chart] after weekend strip: \(filtered.count) bars")
                    bars = filtered
                    if let bundle = IndicatorEngine.compute(quotes: filtered) {
                        indicators = bundle
                    }
                }
                isLoading = false
            } catch {
                print("[Chart] ERROR \(symbol) \(r.rawValue): \(error)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func subscribeToLive() {
        service.quotePublisher(for: symbol)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quote in
                guard let self, self.range.isIntraday else { return }
                if !self.filterIntradayHours([quote]).isEmpty {
                    self.intradayBars.append(quote)
                    self.recomputeDisplay()
                }
            }
            .store(in: &cancellables)
    }

    private func recomputeDisplay() {
        let filtered   = filterIntradayHours(intradayBars)
        let aggregated = aggregate(filtered, minutesPerBar: timeframe.minuteCount)
        bars = aggregated
        computeIndicatorsAndSignals(bars: aggregated)
    }

    // MARK: - Trading hours filters

    private static let easternTZ = TimeZone(identifier: "America/New_York")!

    /// Strip weekends only — used for multi-day ranges (5D/1M/3M/1Y)
    private func stripWeekends(_ quotes: [Quote]) -> [Quote] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.easternTZ
        return quotes.filter {
            let wd = cal.component(.weekday, from: $0.timestamp)
            return wd >= 2 && wd <= 6
        }
    }

    /// Strip weekends AND pre/after-market — used for 1D intraday only
    private func filterIntradayHours(_ quotes: [Quote]) -> [Quote] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.easternTZ
        return quotes.filter { quote in
            let wd = cal.component(.weekday, from: quote.timestamp)
            guard wd >= 2 && wd <= 6 else { return false }
            let comps    = cal.dateComponents([.hour, .minute], from: quote.timestamp)
            let totalMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            return totalMin >= 9 * 60 + 30 && totalMin < 16 * 60
        }
    }

    private func computeIndicatorsAndSignals(bars: [Quote]) {
        guard let bundle = IndicatorEngine.compute(quotes: bars) else { return }
        indicators = bundle
        let barIndex = bars.count - 1
        if let signal = signalEngine.evaluate(quotes: bars,
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
            result.append(Quote(symbol: first.symbol,
                                timestamp: first.timestamp,
                                open: first.open,
                                high: slice.map(\.high).max() ?? first.high,
                                low:  slice.map(\.low ).min() ?? first.low,
                                close: last.close,
                                volume: slice.map(\.volume).reduce(0, +),
                                previousClose: first.previousClose))
            i += minutesPerBar
        }
        return result
    }
}
