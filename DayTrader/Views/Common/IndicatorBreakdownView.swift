// IndicatorBreakdownView.swift
// Shows per-rule scores, current values, and overall confluence vs threshold.
import SwiftUI

struct IndicatorBreakdownView: View {
    let breakdown: SignalBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Header: overall score vs threshold ──────────────────
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Signal Analysis")
                    .font(.headline)
                Spacer()
                // Dominant score badge
                HStack(spacing: 4) {
                    Image(systemName: breakdown.dominantDirection == .buy
                          ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.caption)
                    Text(breakdown.dominantDirection == .buy
                         ? breakdown.buyScorePct : breakdown.sellScorePct)
                        .font(.subheadline.bold().monospacedDigit())
                }
                .foregroundStyle(breakdown.meetsThreshold
                                 ? Color.forSignal(breakdown.dominantDirection)
                                 : .secondary)

                Text("/ \(breakdown.thresholdPct) needed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Overall confluence bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    // Buy score
                    Capsule()
                        .fill(Color.gain.opacity(0.8))
                        .frame(width: geo.size.width * breakdown.buyScore, height: 6)
                    // Sell score overlay
                    Capsule()
                        .fill(Color.loss.opacity(0.8))
                        .frame(width: geo.size.width * breakdown.sellScore, height: 6)
                        .offset(x: geo.size.width * breakdown.buyScore)
                    // Threshold line
                    Rectangle()
                        .fill(Color(.label).opacity(0.5))
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * breakdown.threshold - 0.75)
                }
            }
            .frame(height: 12)

            HStack {
                Label("Buy \(breakdown.buyScorePct)", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(Color.gain)
                Spacer()
                Label("Sell \(breakdown.sellScorePct)", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(Color.loss)
                Spacer()
                Text("Threshold \(breakdown.thresholdPct)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()

            // ── Per-rule rows ────────────────────────────────────────
            ForEach(breakdown.rules, id: \.name) { rule in
                RuleRowView(rule: rule)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Single rule row

private struct RuleRowView: View {
    let rule: RuleBreakdown

    var directionColor: Color {
        switch rule.direction {
        case .buy:  return .gain
        case .sell: return .loss
        case nil:   return .secondary
        }
    }

    var directionLabel: String {
        switch rule.direction {
        case .buy:  return "▲ BUY"
        case .sell: return "▼ SELL"
        case nil:   return "— Neutral"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // Rule name + weight
                HStack(spacing: 4) {
                    Text(rule.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(rule.weightPct)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
                Spacer()
                // Direction result
                Text(directionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(directionColor)
            }
            // Detail line
            Text(rule.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name) \(directionLabel): \(rule.detail)")
    }
}
