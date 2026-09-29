// WatchlistView.swift
import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var watchlistVM: WatchlistViewModel
    @EnvironmentObject var signalsVM:   SignalsViewModel
    @EnvironmentObject var tradeVM:     TradeViewModel
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Full-watchlist warning banner
                if let err = watchlistVM.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(watchlistVM.displayedStocks) { stock in
                        NavigationLink {
                            StockDetailView(symbol: stock.symbol)
                                .environmentObject(watchlistVM)
                                .environmentObject(signalsVM)
                                .environmentObject(tradeVM)
                        } label: {
                            StockRowView(stock: stock)
                        }
                        .listRowBackground(Color.panelBackground)
                    }
                    .onDelete { offsets in
                        offsets.forEach {
                            let symbol = watchlistVM.displayedStocks[$0].symbol
                            watchlistVM.removeStock(symbol: symbol)
                        }
                    }
                } header: {
                    Text("\(watchlistVM.stocks.count) of \(Configuration.maxWatchlistSymbols) symbols")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Watchlist")
            .searchable(text: $watchlistVM.searchText, prompt: "Search symbol or name")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(watchlistVM.isFull)
                    .accessibilityLabel("Add stock")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddStockView()
                    .environmentObject(watchlistVM)
            }
        }
        // Streaming lifecycle is managed at the app level (scenePhase),
        // so it keeps running while navigating between screens.
    }

    private var sortMenu: some View {
        Menu {
            ForEach(WatchlistSortOrder.allCases, id: \.self) { order in
                Button {
                    watchlistVM.sortOrder = order
                } label: {
                    if watchlistVM.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort watchlist")
    }
}

// MARK: - Stock row

struct StockRowView: View {
    let stock: Stock

    var body: some View {
        HStack(spacing: 12) {
            // Symbol + name
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.symbol)
                    .font(.headline)
                    .accessibilityLabel("Symbol \(stock.symbol)")
                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Signal badge (if any)
            if let signal = stock.latestSignal {
                SignalBadgeView(signal: signal)
            }

            // Price + change
            VStack(alignment: .trailing, spacing: 2) {
                Text(stock.displayPrice)
                    .font(.headline.monospacedDigit())
                    .accessibilityLabel("Price \(stock.displayPrice)")

                Text(stock.displayChangePercent)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.forChange(stock.changePercent))
                    .accessibilityLabel("Change \(stock.displayChangePercent)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add stock sheet

struct AddStockView: View {
    @EnvironmentObject var watchlistVM: WatchlistViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ticker Symbol") {
                    TextField("e.g. AAPL", text: $symbol)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle("Add Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                        guard !s.isEmpty else { return }
                        watchlistVM.addStock(Stock(symbol: s, name: s))
                        dismiss()
                    }
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
