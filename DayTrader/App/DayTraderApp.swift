// DayTraderApp.swift
import SwiftUI

// Global shared service — resolved once at launch, accessible everywhere
enum AppServices {
    static let marketData: MarketDataService = {
        if KeychainService.hasAlpacaCredentials,
           let key    = KeychainService.alpacaAPIKey,
           let secret = KeychainService.alpacaAPISecret {
            return AlpacaService(apiKey: key, apiSecret: secret)
        }
        return MockMarketDataService(tickInterval: 1.0)
    }()

    static let signalEngine = SignalEngine()
}

@main
struct DayTraderApp: App {

    @StateObject private var watchlistVM: WatchlistViewModel
    @StateObject private var signalsVM: SignalsViewModel
    @StateObject private var tradeVM: TradeViewModel

    init() {
        let wl = WatchlistViewModel(service: AppServices.marketData,
                                    signalEngine: AppServices.signalEngine)
        let sig = SignalsViewModel()
        let trade = TradeViewModel()

        // Route new signals → auto-trading (opens positions if enabled)
        sig.onNewSignal = { [weak trade] signal in
            trade?.handleAutoSignal(signal)
        }
        // Route live prices → auto-trading (checks stops/targets if enabled)
        wl.onQuote = { [weak trade] symbol, price in
            trade?.updatePrice(symbol: symbol, price: price)
        }
        // Forward watchlist-generated signals to the shared feed (+ notifications + auto-trade)
        wl.onSignal = { [weak sig] signal in
            sig?.append(signal)
        }

        _watchlistVM = StateObject(wrappedValue: wl)
        _signalsVM   = StateObject(wrappedValue: sig)
        _tradeVM     = StateObject(wrappedValue: trade)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchlistVM)
                .environmentObject(signalsVM)
                .environmentObject(tradeVM)
                .onAppear {
                    signalsVM.requestNotificationPermission()
                }
        }
    }
}
