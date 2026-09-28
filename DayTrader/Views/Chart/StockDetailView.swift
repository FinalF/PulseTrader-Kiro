// StockDetailView.swift — chart + per-symbol signal feed + trade button
import SwiftUI

struct StockDetailView: View {
    let symbol: String

    @EnvironmentObject var watchlistVM: WatchlistViewModel
    @EnvironmentObject var signalsVM:   SignalsViewModel
    @EnvironmentObject var tradeVM:     TradeViewModel
    @StateObject private var chartVM: ChartViewModel

    @State private var showTradeSheet = false

    init(symbol: String) {
        self.symbol = symbol
        // ChartViewModel needs to be created here; injected service from environment
        // We use a temporary placeholder and wire it in .task below via environment
        _chartVM = StateObject(wrappedValue: ChartViewModel(
            symbol: symbol,
            service: MockMarketDataService(),
            signalEngine: SignalEngine(),
            signalsVM: SignalsViewModel()   // replaced in onAppear
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Price header
                if let stock = watchlistVM.stocks.first(where: { $0.symbol == symbol }) {
                    priceHeader(stock: stock)
                }

                // Chart
                ChartView(vm: chartVM)
                    .frame(minHeight: 440)

                Divider().padding(.vertical, 8)

                // Signal feed for this symbol
                symbolSignalFeed

                Spacer(minLength: 80)
            }
        }
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTradeSheet = true
                } label: {
                    Label("Trade", systemImage: "cart")
                }
                .accessibilityLabel("Open trade ticket for \(symbol)")
            }
        }
        .sheet(isPresented: $showTradeSheet) {
            TradeView(symbol: symbol)
                .environmentObject(tradeVM)
                .environmentObject(watchlistVM)
        }
        .task { chartVM.load() }
    }

    // MARK: - Sub-views

    private func priceHeader(stock: Stock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stock.displayPrice)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    Text(stock.displayChangePercent)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Color.forChange(stock.changePercent))
                }
                // Live clock
                Text(Date(), style: .time)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let signal = stock.latestSignal {
                SignalBadgeView(signal: signal)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var symbolSignalFeed: some View {
        let symbolSignals = signalsVM.allSignals
            .filter { $0.symbol == symbol }
            .prefix(10)

        return VStack(alignment: .leading, spacing: 0) {
            Text("Recent Signals")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if symbolSignals.isEmpty {
                Text("No signals yet — watching for setups…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(Array(symbolSignals)) { signal in
                    SignalRowView(signal: signal)
                        .padding(.horizontal)
                    Divider().padding(.leading)
                }
            }
        }
    }
}
