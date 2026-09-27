// Configuration.swift
// DayTrader
//
// Central configuration — replace API keys before building.

import Foundation

enum Configuration {

    // MARK: - Market Data Provider
    // "alpaca" when Keychain has credentials, otherwise falls back to "mock"
    // Do NOT hardcode real keys here — use Settings in the app to enter them.
    static var marketDataProvider: String {
        KeychainService.hasAlpacaCredentials ? "alpaca" : "mock"
    }

    // Alpaca endpoints
    static let alpacaDataBaseURL  = "https://data.alpaca.markets"
    static let alpacaStreamURL    = "wss://stream.data.alpaca.markets/v2/iex"   // free tier: IEX feed
    static let alpacaPaperBaseURL = "https://paper-api.alpaca.markets"

    // MARK: - Polling / refresh
    /// Intra-day quote refresh interval in seconds (minimum 15 for free tiers)
    static let quoteRefreshInterval: TimeInterval = 15

    /// Number of intra-day bars to fetch per symbol (e.g. 1-min bars for the session)
    static let intraDayBarsToFetch: Int = 390   // full session at 1-min resolution

    // MARK: - Indicator defaults
    struct Indicators {
        static let rsiPeriod: Int       = 14
        static let macdFast: Int        = 12
        static let macdSlow: Int        = 26
        static let macdSignal: Int      = 9
        static let bbPeriod: Int        = 20
        static let bbStdDev: Double     = 2.0
        static let emaPeriod: Int       = 9
        static let smaPeriod: Int       = 20
        static let volumeSmaPeriod: Int = 20
        static let atrPeriod: Int       = 14
    }

    // MARK: - Signal thresholds
    struct Signals {
        static let rsiOversold: Double  = 30.0
        static let rsiOverbought: Double = 70.0
        /// Minimum confluence score (0–1) before a signal fires
        static let minConfluenceScore: Double = 0.6
    }

    // MARK: - Risk defaults
    struct Risk {
        static let defaultStopLossPct: Double  = 0.01   // 1 %
        static let defaultTakeProfitPct: Double = 0.02  // 2 %
        static let maxPositionSizePct: Double   = 0.05  // 5 % of portfolio
    }

    // MARK: - Paper trading
    static let paperTradingEnabled: Bool      = true
    static let paperTradingInitialCapital: Double = 100_000.0
}
