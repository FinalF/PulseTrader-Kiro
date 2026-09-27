// TradeView.swift — paper order ticket sheet
import SwiftUI

struct TradeView: View {
    let symbol: String

    @EnvironmentObject var tradeVM:     TradeViewModel
    @EnvironmentObject var watchlistVM: WatchlistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var orderType: OrderType = .market
    @State private var quantity: Int = 1
    @State private var limitPrice: Double = 0
    @State private var stopLoss: Double = 0
    @State private var takeProfit: Double = 0

    private var currentPrice: Double {
        watchlistVM.stocks.first(where: { $0.symbol == symbol })?.latestQuote?.close ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current price header
                Section {
                    HStack {
                        Text("Last Price")
                        Spacer()
                        Text(String(format: "$%.2f", currentPrice))
                            .font(.headline.monospacedDigit())
                    }
                    HStack {
                        Text("Available Cash")
                        Spacer()
                        Text(String(format: "$%.2f", tradeVM.portfolio.cash))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // Order type
                Section("Order") {
                    Picker("Type", selection: $orderType) {
                        Text("Market").tag(OrderType.market)
                        Text("Limit").tag(OrderType.limit)
                    }
                    .pickerStyle(.segmented)

                    if orderType == .limit {
                        HStack {
                            Text("Limit Price")
                            Spacer()
                            TextField("0.00", value: $limitPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }

                // Risk management
                Section("Risk Management") {
                    HStack {
                        Text("Stop Loss")
                        Spacer()
                        TextField("0.00", value: $stopLoss, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Take Profit")
                        Spacer()
                        TextField("0.00", value: $takeProfit, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Suggested Qty")
                        Spacer()
                        Text("\(tradeVM.suggestedQuantity(price: currentPrice)) shares")
                            .foregroundStyle(.secondary)
                    }
                }

                // Order summary
                Section("Summary") {
                    let fill = orderType == .market ? currentPrice : limitPrice
                    let cost = fill * Double(quantity)
                    HStack {
                        Text("Estimated Cost")
                        Spacer()
                        Text(String(format: "$%.2f", cost))
                            .monospacedDigit()
                            .foregroundStyle(cost > tradeVM.portfolio.cash ? .red : .primary)
                    }
                }

                // Error
                if let err = tradeVM.orderError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Open positions
                if !tradeVM.portfolio.openTrades.filter({ $0.symbol == symbol }).isEmpty {
                    Section("Open Positions") {
                        ForEach(tradeVM.portfolio.openTrades.filter { $0.symbol == symbol }) { trade in
                            PositionRowView(trade: trade, tradeVM: tradeVM)
                        }
                    }
                }
            }
            .navigationTitle("Trade \(symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Buy") {
                        let order = TradeViewModel.PaperOrder(
                            symbol: symbol,
                            quantity: quantity,
                            limitPrice: orderType == .limit ? limitPrice : nil,
                            stopLoss: stopLoss,
                            takeProfit: takeProfit
                        )
                        tradeVM.submitOrder(order, currentPrice: currentPrice)
                        if tradeVM.orderError == nil { dismiss() }
                    }
                    .disabled(currentPrice == 0)
                }
            }
            .onAppear { prefillRiskLevels() }
        }
    }

    private func prefillRiskLevels() {
        guard currentPrice > 0 else { return }
        quantity  = tradeVM.suggestedQuantity(price: currentPrice)
        stopLoss  = currentPrice * (1 - Configuration.Risk.defaultStopLossPct)
        takeProfit = currentPrice * (1 + Configuration.Risk.defaultTakeProfitPct)
        limitPrice = currentPrice
    }
}

// MARK: - Position row

struct PositionRowView: View {
    let trade: Trade
    @ObservedObject var tradeVM: TradeViewModel

    var body: some View {
        let pnl = tradeVM.unrealizedPnL(for: trade)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trade.quantity) shares @ \(String(format: "%.2f", trade.entryPrice))")
                    .font(.subheadline)
                Text("Stop: \(String(format: "%.2f", trade.stopLoss))  Target: \(String(format: "%.2f", trade.takeProfit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%+.2f", pnl))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(pnl >= 0 ? Color.gain : Color.loss)
                Button("Close") {
                    let price = tradeVM.livePrices[trade.symbol] ?? trade.entryPrice
                    tradeVM.closePosition(trade, at: price)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
