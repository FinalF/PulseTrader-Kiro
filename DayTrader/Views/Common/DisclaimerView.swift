// DisclaimerView.swift — reusable "not financial advice" notice
import SwiftUI

/// Compact inline disclaimer for list headers / footers.
struct DisclaimerBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Signals are educational analysis, **not financial advice**. "
                 + "Backtests show no reliable edge — do not trade real money on these.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Disclaimer: signals are educational analysis, not financial advice.")
    }
}

/// Full disclaimer text for the Settings screen.
struct DisclaimerDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not Financial Advice", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text("""
            PulseTrader is an educational tool. The buy/sell signals it produces are \
            generated from technical indicators and are provided for learning and \
            analysis only.

            Independent backtesting of this strategy on real market data showed no \
            reliable, repeatable edge — results that looked profitable in one period \
            or on some stocks failed to hold up on others (a sign of over-fitting).

            Do not make real trading or investment decisions based on these signals. \
            Past performance and backtest results do not predict future returns. \
            Trading stocks carries risk of loss. Consult a licensed financial advisor \
            before investing.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
