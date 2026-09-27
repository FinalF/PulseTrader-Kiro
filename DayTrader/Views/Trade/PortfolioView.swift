// PortfolioView.swift — paper account summary
import SwiftUI
import Charts

struct PortfolioView: View {
    @EnvironmentObject var tradeVM: TradeViewModel

    var body: some View {
        NavigationStack {
            List {
                // Equity summary
                Section("Account") {
                    statRow("Total Equity",
                            value: String(format: "$%.2f", tradeVM.totalEquity),
                            color: .primary)
                    statRow("Cash",
                            value: String(format: "$%.2f", tradeVM.portfolio.cash),
                            color: .secondary)
                    statRow("Unrealized P&L",
                            value: String(format: "%+.2f", tradeVM.totalUnrealizedPnL),
                            color: tradeVM.totalUnrealizedPnL >= 0 ? .gain : .loss)
                    statRow("Daily P&L",
                            value: String(format: "%+.2f", tradeVM.portfolio.dailyPnL),
                            color: tradeVM.portfolio.dailyPnL >= 0 ? .gain : .loss)
                }

                // Performance stats
                Section("Performance") {
                    statRow("Win Rate",
                            value: String(format: "%.0f%%", tradeVM.portfolio.winRate * 100))
                    statRow("Profit Factor",
                            value: tradeVM.portfolio.profitFactor == .infinity
                                ? "∞"
                                : String(format: "%.2f", tradeVM.portfolio.profitFactor))
                    statRow("Avg Win",
                            value: String(format: "%+.2f", tradeVM.portfolio.averageWin),
                            color: .gain)
                    statRow("Avg Loss",
                            value: String(format: "%.2f", tradeVM.portfolio.averageLoss),
                            color: .loss)
                    statRow("Total Trades",
                            value: "\(tradeVM.portfolio.closedTrades.count)")
                }

                // Open positions
                if !tradeVM.portfolio.openTrades.isEmpty {
                    Section("Open Positions (\(tradeVM.portfolio.openTrades.count))") {
                        ForEach(tradeVM.portfolio.openTrades) { trade in
                            PositionRowView(trade: trade, tradeVM: tradeVM)
                        }
                    }
                }

                // Trade history
                if !tradeVM.portfolio.closedTrades.isEmpty {
                    Section("Trade History") {
                        ForEach(tradeVM.portfolio.closedTrades.reversed()) { trade in
                            closedTradeRow(trade)
                        }
                    }
                }

                // Reset
                Section {
                    Button("Reset Paper Account", role: .destructive) {
                        tradeVM.resetPortfolio()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Portfolio")
        }
    }

    private func statRow(_ label: String, value: String,
                          color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func closedTradeRow(_ trade: Trade) -> some View {
        let pnl = trade.realizedPnL ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.symbol).font(.subheadline.bold())
                Text("\(trade.quantity) shares @ \(String(format: "%.2f", trade.entryPrice))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%+.2f", pnl))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(pnl >= 0 ? Color.gain : Color.loss)
        }
        .padding(.vertical, 2)
    }
}
