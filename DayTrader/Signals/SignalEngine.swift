// SignalEngine.swift
// Evaluates all indicator rules on the latest bar and emits a TradeSignal
// when the weighted confluence score meets the threshold.
// Also exposes SignalBreakdown for the UI to show per-rule scores.

import Foundation

// MARK: - Configuration

struct SignalConfiguration {
    var minConfluenceScore: Double  = Configuration.Signals.minConfluenceScore
    var rsiOversold: Double         = Configuration.Signals.rsiOversold
    var rsiOverbought: Double       = Configuration.Signals.rsiOverbought
    var atrStopMultiplier: Double   = 1.5
    var atrTargetMultiplier: Double = 3.0
    var cooldownBars: Int           = 5
}

// MARK: - Public breakdown types (used by IndicatorBreakdownView)

struct RuleBreakdown {
    let name: String
    let weight: Double
    let direction: SignalDirection?  // nil = neutral
    let detail: String               // e.g. "RSI 28.3 < 30 (oversold)"

    var weightPct: String { String(format: "%.0f%%", weight * 100) }
    var isNeutral: Bool   { direction == nil }
}

struct SignalBreakdown {
    let symbol: String
    let rules: [RuleBreakdown]
    let buyScore: Double
    let sellScore: Double
    let threshold: Double

    var dominantDirection: SignalDirection { buyScore >= sellScore ? .buy : .sell }
    var dominantScore: Double { max(buyScore, sellScore) }
    var meetsThreshold: Bool  { dominantScore >= threshold }

    var buyScorePct: String  { String(format: "%.0f%%", buyScore  * 100) }
    var sellScorePct: String { String(format: "%.0f%%", sellScore * 100) }
    var thresholdPct: String { String(format: "%.0f%%", threshold * 100) }
}

// MARK: - Internal vote

private struct RuleVote {
    let name: String
    let weight: Double
    let direction: SignalDirection?
    let detail: String

    init(_ name: String, _ weight: Double,
         _ dir: SignalDirection?, _ detail: String = "—") {
        self.name = name; self.weight = weight
        self.direction = dir; self.detail = detail
    }
}

// MARK: - Cooldown tracker

final class SignalCooldownTracker {
    private var lastFired: [String: Int] = [:]

    func canFire(symbol: String, direction: SignalDirection,
                 barIndex: Int, cooldown: Int) -> Bool {
        let key = "\(symbol)_\(direction.rawValue)"
        if let last = lastFired[key], barIndex - last < cooldown { return false }
        return true
    }

    func record(symbol: String, direction: SignalDirection, barIndex: Int) {
        lastFired["\(symbol)_\(direction.rawValue)"] = barIndex
    }
}

// MARK: - Engine

final class SignalEngine {
    private let config: SignalConfiguration
    private let cooldown: SignalCooldownTracker

    init(config: SignalConfiguration = SignalConfiguration(),
         cooldown: SignalCooldownTracker = SignalCooldownTracker()) {
        self.config   = config
        self.cooldown = cooldown
    }

    // MARK: Evaluate + emit signal

    func evaluate(quotes: [Quote],
                  indicators: IndicatorBundle,
                  barIndex: Int) -> TradeSignal? {
        guard let latest = quotes.last else { return nil }
        let i = quotes.count - 1
        let symbol = latest.symbol

        let votes = allVotes(indicators: indicators, i: i, close: latest.close, quotes: quotes)

        var buyScore = 0.0, sellScore = 0.0, totalWeight = 0.0
        for v in votes {
            totalWeight += v.weight
            switch v.direction {
            case .buy:  buyScore  += v.weight
            case .sell: sellScore += v.weight
            case nil:   break
            }
        }
        guard totalWeight > 0 else { return nil }

        let buyConf  = buyScore  / totalWeight
        let sellConf = sellScore / totalWeight

        let (direction, confidence): (SignalDirection, Double) = {
            if buyConf >= sellConf && buyConf >= config.minConfluenceScore {
                return (.buy, buyConf)
            } else if sellConf > buyConf && sellConf >= config.minConfluenceScore {
                return (.sell, sellConf)
            }
            return (.buy, 0)
        }()

        guard confidence >= config.minConfluenceScore else { return nil }
        guard cooldown.canFire(symbol: symbol, direction: direction,
                               barIndex: barIndex,
                               cooldown: config.cooldownBars) else { return nil }

        let atr = indicators.atr[i] ?? (latest.high - latest.low)
        guard atr > 0 else { return nil }

        let stopLoss: Double
        let takeProfit: Double
        switch direction {
        case .buy:
            stopLoss   = latest.close - atr * config.atrStopMultiplier
            takeProfit = latest.close + atr * config.atrTargetMultiplier
        case .sell:
            stopLoss   = latest.close + atr * config.atrStopMultiplier
            takeProfit = latest.close - atr * config.atrTargetMultiplier
        }
        guard abs(stopLoss - latest.close) > 0 else { return nil }

        cooldown.record(symbol: symbol, direction: direction, barIndex: barIndex)

        return TradeSignal(
            symbol: symbol,
            timestamp: latest.timestamp,
            direction: direction,
            confidence: confidence,
            triggeringIndicators: votes.filter { $0.direction == direction }.map(\.name),
            entryPrice: latest.close,
            stopLoss: stopLoss,
            takeProfit: takeProfit
        )
    }

    // MARK: Breakdown (always computed, used by UI regardless of threshold)

    func breakdown(quotes: [Quote],
                   indicators: IndicatorBundle) -> SignalBreakdown? {
        guard let latest = quotes.last else { return nil }
        let i = quotes.count - 1

        let votes = allVotes(indicators: indicators, i: i, close: latest.close, quotes: quotes)

        var buyScore = 0.0, sellScore = 0.0, totalWeight = 0.0
        for v in votes {
            totalWeight += v.weight
            switch v.direction {
            case .buy:  buyScore  += v.weight
            case .sell: sellScore += v.weight
            case nil:   break
            }
        }
        guard totalWeight > 0 else { return nil }

        let rules = votes.map {
            RuleBreakdown(name: $0.name, weight: $0.weight,
                         direction: $0.direction, detail: $0.detail)
        }
        return SignalBreakdown(
            symbol: latest.symbol,
            rules: rules,
            buyScore:  buyScore  / totalWeight,
            sellScore: sellScore / totalWeight,
            threshold: config.minConfluenceScore
        )
    }

    // MARK: - Rules (shared between evaluate and breakdown)

    private func allVotes(indicators: IndicatorBundle, i: Int,
                           close: Double, quotes: [Quote]) -> [RuleVote] {
        [
            rsiVote(indicators: indicators, i: i),
            macdCrossoverVote(indicators: indicators, i: i),
            bollingerTouchVote(indicators: indicators, i: i, close: close),
            ema9CrossVote(indicators: indicators, i: i, close: close, quotes: quotes),
            vwapVote(indicators: indicators, i: i, close: close, quotes: quotes),
            volumeVote(indicators: indicators, i: i),
        ]
    }

    private func rsiVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let w = 0.25
        guard let rsi = indicators.rsi[safe: i] ?? nil else {
            return RuleVote("RSI", w, nil, "Not enough bars")
        }
        let rsiStr = String(format: "%.1f", rsi)
        if rsi < config.rsiOversold {
            return RuleVote("RSI", w, .buy,
                            "RSI \(rsiStr) < \(Int(config.rsiOversold)) (oversold → buy)")
        }
        if rsi > config.rsiOverbought {
            return RuleVote("RSI", w, .sell,
                            "RSI \(rsiStr) > \(Int(config.rsiOverbought)) (overbought → sell)")
        }
        return RuleVote("RSI", w, nil, "RSI \(rsiStr) — neutral zone")
    }

    private func macdCrossoverVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let w = 0.25
        guard i > 0,
              let lineCurr = indicators.macd.line[safe: i]     ?? nil,
              let sigCurr  = indicators.macd.signal[safe: i]   ?? nil,
              let linePrev = indicators.macd.line[safe: i - 1] ?? nil,
              let sigPrev  = indicators.macd.signal[safe: i - 1] ?? nil
        else { return RuleVote("MACD", w, nil, "Not enough bars") }

        let fmt = { (v: Double) in String(format: "%.4f", v) }
        if linePrev <= sigPrev && lineCurr > sigCurr {
            return RuleVote("MACD", w, .buy,
                            "Line \(fmt(lineCurr)) crossed above Signal \(fmt(sigCurr))")
        }
        if linePrev >= sigPrev && lineCurr < sigCurr {
            return RuleVote("MACD", w, .sell,
                            "Line \(fmt(lineCurr)) crossed below Signal \(fmt(sigCurr))")
        }
        let diff = lineCurr - sigCurr
        return RuleVote("MACD", w, nil,
                        "No crossover — diff \(fmt(diff))")
    }

    private func bollingerTouchVote(indicators: IndicatorBundle,
                                     i: Int, close: Double) -> RuleVote {
        let w = 0.20
        guard let lower = indicators.bb.lower[safe: i] ?? nil,
              let upper = indicators.bb.upper[safe: i] ?? nil
        else { return RuleVote("BB Touch", w, nil, "Not enough bars") }

        let fmt = { (v: Double) in String(format: "%.2f", v) }
        if close <= lower {
            return RuleVote("BB Touch", w, .buy,
                            "Close \(fmt(close)) ≤ Lower \(fmt(lower))")
        }
        if close >= upper {
            return RuleVote("BB Touch", w, .sell,
                            "Close \(fmt(close)) ≥ Upper \(fmt(upper))")
        }
        return RuleVote("BB Touch", w, nil,
                        "Close \(fmt(close)) inside bands [\(fmt(lower))–\(fmt(upper))]")
    }

    private func ema9CrossVote(indicators: IndicatorBundle, i: Int,
                                close: Double, quotes: [Quote]) -> RuleVote {
        let w = 0.15
        guard i > 0,
              let emaCurr = indicators.ema9[safe: i]     ?? nil,
              let emaPrev = indicators.ema9[safe: i - 1] ?? nil
        else { return RuleVote("EMA9", w, nil, "Not enough bars") }

        let prevClose = quotes[i - 1].close
        let prevAbove = prevClose > emaPrev
        let currAbove = close     > emaCurr
        let fmt = { (v: Double) in String(format: "%.2f", v) }

        if !prevAbove && currAbove {
            return RuleVote("EMA9", w, .buy,
                            "Close \(fmt(close)) crossed above EMA9 \(fmt(emaCurr))")
        }
        if prevAbove && !currAbove {
            return RuleVote("EMA9", w, .sell,
                            "Close \(fmt(close)) crossed below EMA9 \(fmt(emaCurr))")
        }
        let rel = close > emaCurr ? "above" : "below"
        return RuleVote("EMA9", w, nil,
                        "Close \(fmt(close)) \(rel) EMA9 \(fmt(emaCurr)) — no cross")
    }

    private func vwapVote(indicators: IndicatorBundle, i: Int,
                           close: Double, quotes: [Quote]) -> RuleVote {
        let w = 0.10
        guard i > 0,
              let vwapCurr = indicators.vwap[safe: i]     ?? nil,
              let vwapPrev = indicators.vwap[safe: i - 1] ?? nil
        else { return RuleVote("VWAP", w, nil, "Not enough bars") }

        let prevClose = quotes[i - 1].close
        let prevAbove = prevClose > vwapPrev
        let currAbove = close     > vwapCurr
        let fmt = { (v: Double) in String(format: "%.2f", v) }

        if !prevAbove && currAbove {
            return RuleVote("VWAP", w, .buy,
                            "Close \(fmt(close)) crossed above VWAP \(fmt(vwapCurr))")
        }
        if prevAbove && !currAbove {
            return RuleVote("VWAP", w, .sell,
                            "Close \(fmt(close)) crossed below VWAP \(fmt(vwapCurr))")
        }
        let rel = close > vwapCurr ? "above" : "below"
        return RuleVote("VWAP", w, nil,
                        "Close \(fmt(close)) \(rel) VWAP \(fmt(vwapCurr)) — no cross")
    }

    private func volumeVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let w = 0.05
        guard let volSMA = indicators.volumeSMA[safe: i] ?? nil,
              let bar    = indicators.vwap[safe: i]  // use vwap array to get index bounds
        else { return RuleVote("Volume", w, nil, "No volume SMA") }
        let _ = bar  // silence unused warning
        // Volume spike is directional only when combined with other rules.
        // Here we just report the state.
        let smaStr = String(format: "%.0f", volSMA)
        return RuleVote("Volume", w, nil, "Vol SMA \(smaStr) — used for confirmation")
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
