// MockMarketDataService.swift
// Generates realistic intra-day OHLCV bars using geometric Brownian motion.
// Replays one bar every `tickInterval` seconds so the UI updates visibly in the simulator.

import Foundation
import Combine

final class MockMarketDataService: MarketDataService {

    // How fast to replay: 1 s per bar in simulator (real session = 1 min/bar)
    private let tickInterval: TimeInterval
    private var subjects: [String: PassthroughSubject<Quote, Never>] = [:]
    private var timers:   [String: AnyCancellable] = [:]
    private var barCache: [String: [Quote]] = [:]

    // Seed prices for each default symbol
    private static let seedPrices: [String: Double] = [
        "AAPL": 189.50,
        "NVDA": 875.20,
        "TSLA": 248.30,
        "MSFT": 415.60,
        "SPY":  524.10,
    ]

    init(tickInterval: TimeInterval = 1.0) {
        self.tickInterval = tickInterval
    }

    // MARK: - MarketDataService

    func fetchBars(symbol: String, limit: Int) async throws -> [Quote] {
        if let cached = barCache[symbol], !cached.isEmpty {
            return Array(cached.suffix(limit))
        }
        let bars = generateHistoricalBars(symbol: symbol, count: limit)
        barCache[symbol] = bars
        return bars
    }

    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never> {
        if let existing = subjects[symbol] {
            return existing.eraseToAnyPublisher()
        }
        let subject = PassthroughSubject<Quote, Never>()
        subjects[symbol] = subject

        // Pre-generate session bars if not cached
        if barCache[symbol] == nil {
            barCache[symbol] = generateHistoricalBars(symbol: symbol, count: Configuration.intraDayBarsToFetch)
        }

        var barIndex = barCache[symbol]!.count
        let seed = MockMarketDataService.seedPrices[symbol] ?? 100.0

        let timer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let lastClose = self.barCache[symbol]?.last?.close ?? seed
                let newBar    = self.generateNextBar(symbol: symbol,
                                                     previousClose: lastClose,
                                                     index: barIndex)
                self.barCache[symbol]?.append(newBar)
                barIndex += 1
                subject.send(newBar)
            }
        timers[symbol] = timer
        return subject.eraseToAnyPublisher()
    }

    // MARK: - Private helpers

    /// Generate `count` historical 1-min bars using GBM starting from seed price
    private func generateHistoricalBars(symbol: String, count: Int) -> [Quote] {
        let seed      = MockMarketDataService.seedPrices[symbol] ?? 100.0
        let sessionStart = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(9.5 * 3600)   // 09:30 ET

        var bars: [Quote] = []
        var price = seed

        for i in 0..<count {
            let timestamp   = sessionStart.addingTimeInterval(Double(i) * 60)
            let (o, h, l, c, v) = nextOHLCV(previousClose: price, symbol: symbol)
            let prevClose   = i == 0 ? seed : bars[i - 1].close

            bars.append(Quote(
                symbol: symbol,
                timestamp: timestamp,
                open: o, high: h, low: l, close: c,
                volume: v,
                previousClose: prevClose
            ))
            price = c
        }
        return bars
    }

    private func generateNextBar(symbol: String, previousClose: Double, index: Int) -> Quote {
        let sessionStart = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(9.5 * 3600)
        let timestamp = sessionStart.addingTimeInterval(Double(index) * 60)
        let (o, h, l, c, v) = nextOHLCV(previousClose: previousClose, symbol: symbol)
        return Quote(symbol: symbol, timestamp: timestamp,
                     open: o, high: h, low: l, close: c,
                     volume: v, previousClose: previousClose)
    }

    /// Geometric Brownian Motion step to generate a realistic OHLCV bar
    private func nextOHLCV(previousClose: Double,
                            symbol: String) -> (Double, Double, Double, Double, Int) {
        // Annualised vol ≈ 30% → daily vol ≈ 30%/√252 → per-minute vol
        let annualVol: Double = 0.30
        let minuteVol = annualVol / sqrt(252.0 * 390.0)
        let drift     = 0.0  // zero drift for intra-day

        let z     = gaussianRandom()
        let open  = previousClose * exp(drift + minuteVol * z)
        let range = open * minuteVol * abs(gaussianRandom()) * 3.0
        let high  = open + range
        let low   = max(open - range, open * 0.995)   // clamp floor

        let zClose = gaussianRandom()
        let close  = (low + (high - low) * (0.5 + 0.4 * zClose / 3.0))
            .clamped(to: low...high)

        // Volume: base + noise, slightly higher near open/close
        let baseVolume = baseVol(for: symbol)
        let volume = Int(Double(baseVolume) * (0.7 + 0.6 * abs(gaussianRandom())))

        return (open, high, low, close, volume)
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

    /// Box-Muller transform → standard normal sample
    private func gaussianRandom() -> Double {
        let u1 = Double.random(in: Double.leastNormalMagnitude...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}

// MARK: - Comparable clamping helper
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
