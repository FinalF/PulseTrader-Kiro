// ContentView.swift — root TabView
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var watchlistVM: WatchlistViewModel
    @EnvironmentObject var signalsVM:   SignalsViewModel
    @EnvironmentObject var tradeVM:     TradeViewModel

    // Badge count for unread high-confidence signals
    @State private var signalBadge: Int = 0

    var body: some View {
        TabView {
            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "list.bullet")
                }

            SignalsView()
                .tabItem {
                    Label("Signals", systemImage: "waveform.path.ecg")
                }
                .badge(signalBadge)

            PortfolioView()
                .tabItem {
                    Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onChange(of: signalsVM.allSignals.count) { _, newCount in
            // Badge = number of high-confidence signals today
            signalBadge = signalsVM.allSignals
                .filter { $0.tier == .high && Calendar.current.isDateInToday($0.timestamp) }
                .count
        }
    }
}

#Preview {
    let mockService = MockMarketDataService()
    let watchlistVM = WatchlistViewModel(service: mockService, signalEngine: SignalEngine())
    let signalsVM   = SignalsViewModel()
    let tradeVM     = TradeViewModel()

    return ContentView()
        .environmentObject(watchlistVM)
        .environmentObject(signalsVM)
        .environmentObject(tradeVM)
}
