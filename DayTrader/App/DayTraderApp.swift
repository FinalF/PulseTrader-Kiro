// DayTraderApp.swift — app entry point
import SwiftUI

@main
struct DayTraderApp: App {

    // Shared service instances (single source of truth)
    private let marketDataService: MarketDataService = MockMarketDataService(tickInterval: 1.0)
    private let signalEngine = SignalEngine()

    // Shared ViewModels injected as environment objects
    @StateObject private var watchlistVM: WatchlistViewModel
    @StateObject private var signalsVM  = SignalsViewModel()
    @StateObject private var tradeVM    = TradeViewModel()

    init() {
        // Use Alpaca if credentials are stored in Keychain, otherwise fall back to Mock
        let service: MarketDataService = KeychainService.hasAlpacaCredentials
            ? AlpacaService(apiKey: KeychainService.alpacaAPIKey!,
                            apiSecret: KeychainService.alpacaAPISecret!)
            : MockMarketDataService(tickInterval: 1.0)

        let engine = SignalEngine()
        _watchlistVM = StateObject(wrappedValue:
            WatchlistViewModel(service: service, signalEngine: engine)
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
