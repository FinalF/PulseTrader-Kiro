// SignalBadgeView.swift — compact signal indicator used in watchlist rows
import SwiftUI

struct SignalBadgeView: View {
    let signal: TradeSignal

    var body: some View {
        HStack(spacing: 3) {
            Text(signal.direction.emoji)
                .font(.caption2)
            Text(signal.displayConfidence)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.forSignal(signal.direction).opacity(0.15))
        .foregroundStyle(Color.forSignal(signal.direction))
        .clipShape(Capsule())
        .accessibilityLabel("\(signal.direction.rawValue) signal \(signal.displayConfidence) confidence")
    }
}

struct ConfidenceMeterView: View {
    let confidence: Double   // 0–1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                Capsule()
                    .fill(meterColor)
                    .frame(width: geo.size.width * confidence)
            }
        }
        .frame(height: 4)
        .accessibilityValue("\(Int(confidence * 100)) percent confidence")
    }

    private var meterColor: Color {
        if confidence >= 0.80 { return .green }
        if confidence >= 0.60 { return .orange }
        return .red
    }
}
