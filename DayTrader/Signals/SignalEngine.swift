// SignalEngine.swift
// Evaluates all indicator rules on the latest bar and emits a TradeSignal
// when the weighted confluence score meets the threshold.

import Foundation

// MARK: - Configuration

struct SignalConfiguration {
    var minConfluenceScore: Double = Configuration.Signals.minConfluenceScore
    var rsiOversold: Double        = Configuration.Signals.rsiOversold
    var rsiOverbought: Double      = Configuration.Signals.rsiOverbought
    var atrStopMultiplier: Double  = 1.5
    var atrTargetMultiplier: Double = 3.0
    var cooldownBars: Int          = 5
}

// MARK: - Individual rule vote

private struct RuleVote {
    let name: String
    let weight: Double
    let direction: SignalDirection?   // nil = neutral / no vote
}

// MARK: - Cooldown tracker

final class SignalCooldownTracker {
    // [symbol+direction: lastBarIndex]
    private var lastFired: [String: Int] = [:]

    func canFire(symbol: String, direction: SignalDirection,
                 barIndex: Int, cooldown: Int) -> Bool {
        let key = "\(symbol)_\(direction.rawValue)"
        if let last = lastFired[key], barIndex - last < cooldown { return false }
        return true
    }

    func record(symbol: String, direction: SignalDirection, barIndex: Int) {
        let key = "\(symbol)_\(direction.rawValue)"
        lastFired[key] = barIndex
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

    /// Evaluate the latest bar and return a signal if confluence ≥ threshold.
    /// `barIndex` is the absolute position of the latest bar in the session
    /// (used for cooldown tracking).
    func evaluate(quotes: [Quote],
                  indicators: IndicatorBundle,
                  barIndex: Int) -> TradeSignal? {
        guard let latest = quotes.last else { return nil }
        let i = quotes.count - 1   // last index
        let symbol = latest.symbol

        // Gather votes from each rule
        let votes = [
            rsiVote(indicators: indicators, i: i),
            macdCrossoverVote(indicators: indicators, i: i),
            bollingerTouchVote(indicators: indicators, i: i, close: latest.close),
            ema9CrossVote(indicators: indicators, i: i, close: latest.close, quotes: quotes),
            vwapVote(indicators: indicators, i: i, close: latest.close, quotes: quotes),
            volumeVote(indicators: indicators, i: i),
        ]

        // Tally weighted scores separately for buy and sell
        var buyScore  = 0.0
        var sellScore = 0.0
        var totalWeight = 0.0

        for vote in votes {
            totalWeight += vote.weight
            switch vote.direction {
            case .buy:  buyScore  += vote.weight
            case .sell: sellScore += vote.weight
            case nil:   break
            }
        }

        guard totalWeight > 0 else { return nil }

        let buyConfidence  = buyScore  / totalWeight
        let sellConfidence = sellScore / totalWeight

        // Choose dominant direction
        let (direction, confidence): (SignalDirection, Double) = {
            if buyConfidence >= sellConfidence && buyConfidence >= config.minConfluenceScore {
                return (.buy, buyConfidence)
            } else if sellConfidence > buyConfidence && sellConfidence >= config.minConfluenceScore {
                return (.sell, sellConfidence)
            } else {
                return (.buy, 0)   // placeholder; guarded below
            }
        }()

        guard confidence >= config.minConfluenceScore else { return nil }

        // Cooldown check
        guard cooldown.canFire(symbol: symbol, direction: direction,
                               barIndex: barIndex, cooldown: config.cooldownBars) else {
            return nil
        }

        // ATR-based stop-loss and take-profit
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

        // Guard against degenerate stop (riskReward would be nil)
        guard abs(stopLoss - latest.close) > 0 else { return nil }

        // Collect triggering indicator names
        let triggers = votes
            .filter { $0.direction == direction }
            .map { $0.name }

        cooldown.record(symbol: symbol, direction: direction, barIndex: barIndex)

        return TradeSignal(
            symbol:               symbol,
            timestamp:            latest.timestamp,
            direction:            direction,
            confidence:           confidence,
            triggeringIndicators: triggers,
            entryPrice:           latest.close,
            stopLoss:             stopLoss,
            takeProfit:           takeProfit
        )
    }

    // MARK: - Individual rules

    /// RSI extreme — weight 0.25
    private func rsiVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let name = "RSI"
        let weight = 0.25
        guard let rsi = indicators.rsi[i] else { return RuleVote(name: name, weight: weight, direction: nil) }
        if rsi < config.rsiOversold       { return RuleVote(name: name, weight: weight, direction: .buy) }
        if rsi > config.rsiOverbought     { return RuleVote(name: name, weight: weight, direction: .sell) }
        return RuleVote(name: name, weight: weight, direction: nil)
    }

    /// MACD crossover — weight 0.25
    private func macdCrossoverVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let name = "MACD"
        let weight = 0.25
        guard i > 0,
              let lineCurr = indicators.macd.line[i],
              let sigCurr  = indicators.macd.signal[i],
              let linePrev = indicators.macd.line[i - 1],
              let sigPrev  = indicators.macd.signal[i - 1]
        else { return RuleVote(name: name, weight: weight, direction: nil) }

        let crossedUp   = linePrev <= sigPrev && lineCurr > sigCurr
        let crossedDown = linePrev >= sigPrev && lineCurr < sigCurr

        if crossedUp   { return RuleVote(name: name, weight: weight, direction: .buy) }
        if crossedDown { return RuleVote(name: name, weight: weight, direction: .sell) }
        return RuleVote(name: name, weight: weight, direction: nil)
    }

    /// Bollinger Band touch — weight 0.20
    private func bollingerTouchVote(indicators: IndicatorBundle, i: Int, close: Double) -> RuleVote {
        let name = "BB Touch"
        let weight = 0.20
        guard let lower = indicators.bb.lower[i],
              let upper = indicators.bb.upper[i]
        else { return RuleVote(name: name, weight: weight, direction: nil) }

        if close <= lower { return RuleVote(name: name, weight: weight, direction: .buy) }
        if close >= upper { return RuleVote(name: name, weight: weight, direction: .sell) }
        return RuleVote(name: name, weight: weight, direction: nil)
    }

    /// EMA9 cross — weight 0.15
    private func ema9CrossVote(indicators: IndicatorBundle, i: Int,
                                close: Double, quotes: [Quote]) -> RuleVote {
        let name = "EMA9 Cross"
        let weight = 0.15
        guard i > 0,
              let emaCurr = indicators.ema9[i],
              let emaPrev = indicators.ema9[i - 1]
        else { return RuleVote(name: name, weight: weight, direction: nil) }

        let prevClose = quotes[i - 1].close
        let prevAboveEMA = prevClose > emaPrev
        let currAboveEMA = close     > emaCurr

        if !prevAboveEMA && currAboveEMA { return RuleVote(name: name, weight: weight, direction: .buy) }
        if prevAboveEMA && !currAboveEMA { return RuleVote(name: name, weight: weight, direction: .sell) }
        return RuleVote(name: name, weight: weight, direction: nil)
    }

    /// VWAP cross — weight 0.10
    private func vwapVote(indicators: IndicatorBundle, i: Int,
                           close: Double, quotes: [Quote]) -> RuleVote {
        let name = "VWAP"
        let weight = 0.10
        guard i > 0,
              let vwapCurr = indicators.vwap[i],
              let vwapPrev = indicators.vwap[i - 1]
        else { return RuleVote(name: name, weight: weight, direction: nil) }

        let prevClose    = quotes[i - 1].close
        let prevAboveVWAP = prevClose > vwapPrev
        let currAboveVWAP = close    > vwapCurr

        if !prevAboveVWAP && currAboveVWAP { return RuleVote(name: name, weight: weight, direction: .buy) }
        if prevAboveVWAP && !currAboveVWAP { return RuleVote(name: name, weight: weight, direction: .sell) }
        return RuleVote(name: name, weight: weight, direction: nil)
    }

    /// Volume spike confirmation — weight 0.05
    private func volumeVote(indicators: IndicatorBundle, i: Int) -> RuleVote {
        let name = "Volume"
        let weight = 0.05
        // Volume vote is neutral direction — it only adds weight when paired
        // with another signal. For simplicity in MVP, we skip directional vote here.
        return RuleVote(name: name, weight: weight, direction: nil)
    }
}
