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
        _chartVM = StateObject(wrappedValue: ChartViewModel(
            symbol: symbol,
            service: AppServices.marketData,
            signalEngine: AppServices.signalEngine,
            signalsVM: SignalsViewModel()
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stock.displayPrice)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    Text(stock.displayChangePercent)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Color.forChange(stock.changePercent))
                }
                // Live date + time + market status badge
                HStack(spacing: 6) {
                    // Full date and time, ticking every second via .timer style
                    Text(Date(), format: .dateTime
                            .month(.abbreviated).day()
                            .hour(.defaultDigits(amPM: .abbreviated)).minute().second())
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)

                    // Status badge — only shown when market is NOT open
                    if !MarketHours.isOpen {
                        Text(MarketHours.statusLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    } else {
                        // Green dot when market is live
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Market Open")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.green)
                        }
                    }
                }
                .accessibilityLabel(MarketHours.isOpen ? "Market is open" : MarketHours.statusLabel)
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

            // ── Live indicator breakdown ─────────────────────────────
            if let breakdown = chartVM.signalBreakdown {
                IndicatorBreakdownView(breakdown: breakdown)
                    .padding(.horizontal)
                Divider().padding(.vertical, 8)
            }

            // ── Recent signals ───────────────────────────────────────
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
