// MockMarketDataService.swift
// Generates realistic OHLCV bars using Geometric Brownian Motion.
// Supports both intraday (1-min) and multi-day (daily/hourly) ranges.

import Foundation
import Combine

final class MockMarketDataService: MarketDataService {

    private let tickInterval: TimeInterval
    private var subjects:  [String: PassthroughSubject<Quote, Never>] = [:]
    private var timers:    [String: AnyCancellable] = [:]
    var barCache:  [String: [Quote]] = [:]    // intraday 1-min cache (internal for VM pre-load)

    static let seedPrices: [String: Double] = [
        "AAPL": 189.50, "NVDA": 875.20, "TSLA": 248.30,
        "MSFT": 415.60, "SPY":  524.10,
    ]

    init(tickInterval: TimeInterval = 1.0) {
        self.tickInterval = tickInterval
        // Pre-generate intraday bars immediately so Watchlist shows prices on first render
        for symbol in Stock.defaults.map(\.symbol) {
            barCache[symbol] = generateIntradayBars(symbol: symbol,
                                                     count: Configuration.intraDayBarsToFetch)
        }
    }

    // MARK: - MarketDataService

    func fetchBars(symbol: String, limit: Int) async throws -> [Quote] {
        if let cached = barCache[symbol], !cached.isEmpty {
            return Array(cached.suffix(limit))
        }
        let bars = generateIntradayBars(symbol: symbol, count: limit)
        barCache[symbol] = bars
        return bars
    }

    func fetchBars(symbol: String, range: ChartRange) async throws -> [Quote] {
        switch range {
        case .oneDay:
            return try await fetchBars(symbol: symbol, limit: range.barLimit)
        case .fiveDay:
            return generateMultiDayBars(symbol: symbol, days: 5, barsPerDay: 26,
                                         minutesPerBar: 15)
        case .oneMonth:
            return generateMultiDayBars(symbol: symbol, days: 22, barsPerDay: 7,
                                         minutesPerBar: 60)
        case .threeMonth:
            return generateDailyBars(symbol: symbol, days: 63)
        case .oneYear:
            return generateDailyBars(symbol: symbol, days: 252)
        }
    }

    func fetchLatestQuote(symbol: String) async throws -> Quote? {
        return barCache[symbol]?.last
    }

    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never> {
        if let existing = subjects[symbol] { return existing.eraseToAnyPublisher() }

        let subject = PassthroughSubject<Quote, Never>()
        subjects[symbol] = subject

        if barCache[symbol] == nil {
            barCache[symbol] = generateIntradayBars(symbol: symbol,
                                                     count: Configuration.intraDayBarsToFetch)
        }

        var barIndex = barCache[symbol]!.count
        let seed = MockMarketDataService.seedPrices[symbol] ?? 100.0

        let timer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let lastClose = self.barCache[symbol]?.last?.close ?? seed
                let newBar = self.nextBar(symbol: symbol, previousClose: lastClose, index: barIndex)
                self.barCache[symbol]?.append(newBar)
                barIndex += 1
                subject.send(newBar)
            }
        timers[symbol] = timer
        return subject.eraseToAnyPublisher()
    }

    // MARK: - Bar generation

    private func generateIntradayBars(symbol: String, count: Int) -> [Quote] {
        let seed = MockMarketDataService.seedPrices[symbol] ?? 100.0
        let sessionStart = todaySessionStart()
        var price = seed
        var bars: [Quote] = []
        for i in 0..<count {
            let ts = sessionStart.addingTimeInterval(Double(i) * 60)
            let (o, h, l, c, v) = ohlcv(prev: price, symbol: symbol, minuteVol: minuteVol())
            let prev = i == 0 ? seed : bars[i - 1].close
            bars.append(Quote(symbol: symbol, timestamp: ts,
                              open: o, high: h, low: l, close: c,
                              volume: v, previousClose: prev))
            price = c
        }
        return bars
    }

    /// Multi-day intraday bars (e.g. 5D×15min, 1M×1H)
    private func generateMultiDayBars(symbol: String, days: Int,
                                       barsPerDay: Int, minutesPerBar: Int) -> [Quote] {
        let seed = MockMarketDataService.seedPrices[symbol] ?? 100.0
        let cal  = Calendar.current
        var bars: [Quote] = []
        var price = seed * 0.85  // start a bit lower for visual movement

        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            // Skip weekends
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }

            let sessionStart = cal.startOfDay(for: day).addingTimeInterval(9.5 * 3600)
            let vol = minuteVol() * sqrt(Double(minutesPerBar))
            for i in 0..<barsPerDay {
                let ts = sessionStart.addingTimeInterval(Double(i * minutesPerBar) * 60)
                let (o, h, l, c, v) = ohlcv(prev: price, symbol: symbol, minuteVol: vol)
                let prev = bars.last?.close ?? seed
                bars.append(Quote(symbol: symbol, timestamp: ts,
                                  open: o, high: h, low: l, close: c,
                                  volume: v * minutesPerBar, previousClose: prev))
                price = c
            }
        }
        return bars
    }

    /// Daily bars for 3M / 1Y views
    private func generateDailyBars(symbol: String, days: Int) -> [Quote] {
        let seed = MockMarketDataService.seedPrices[symbol] ?? 100.0
        let cal  = Calendar.current
        var bars: [Quote] = []
        var price = seed * (1 - Double(days) * 0.0003)  // slight uptrend over time

        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }

            let ts = cal.startOfDay(for: day).addingTimeInterval(9.5 * 3600)
            let dailyVol = minuteVol() * sqrt(390.0)
            let (o, h, l, c, v) = ohlcv(prev: price, symbol: symbol, minuteVol: dailyVol)
            let prev = bars.last?.close ?? seed
            bars.append(Quote(symbol: symbol, timestamp: ts,
                              open: o, high: h, low: l, close: c,
                              volume: v * 390, previousClose: prev))
            price = c
        }
        return bars
    }

    private func nextBar(symbol: String, previousClose: Double, index: Int) -> Quote {
        let ts = todaySessionStart().addingTimeInterval(Double(index) * 60)
        let (o, h, l, c, v) = ohlcv(prev: previousClose, symbol: symbol, minuteVol: minuteVol())
        return Quote(symbol: symbol, timestamp: ts,
                     open: o, high: h, low: l, close: c,
                     volume: v, previousClose: previousClose)
    }

    // MARK: - Math helpers

    private func minuteVol() -> Double {
        0.30 / sqrt(252.0 * 390.0)
    }

    private func ohlcv(prev: Double, symbol: String,
                        minuteVol: Double) -> (Double, Double, Double, Double, Int) {
        let z     = gaussianRandom()
        let open  = prev * exp(minuteVol * z)
        let range = open * minuteVol * abs(gaussianRandom()) * 3.0
        let high  = open + range
        let low   = max(open - range, open * 0.995)
        let zc    = gaussianRandom()
        let close = (low + (high - low) * (0.5 + 0.4 * zc / 3.0)).clamped(to: low...high)
        let vol   = Int(Double(baseVol(for: symbol)) * (0.7 + 0.6 * abs(gaussianRandom())))
        return (open, high, low, close, vol)
    }

    private func todaySessionStart() -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(9.5 * 3600)
    }

    private func baseVol(for symbol: String) -> Int {
        switch symbol {
        case "AAPL": return 600_000
        case "NVDA": return 400_000
        case "TSLA": return 500_000
        case "MSFT": return 300_000
        case "SPY":  return 1_000_000
        default:     return 200_000
        }
    }

    private func gaussianRandom() -> Double {
        let u1 = Double.random(in: Double.leastNormalMagnitude...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
