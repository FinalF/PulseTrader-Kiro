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
    @StateObject private var signalsVM = SignalsViewModel()
    @StateObject private var tradeVM   = TradeViewModel()

    init() {
        _watchlistVM = StateObject(wrappedValue:
            WatchlistViewModel(service: AppServices.marketData,
                               signalEngine: AppServices.signalEngine)
        )
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
