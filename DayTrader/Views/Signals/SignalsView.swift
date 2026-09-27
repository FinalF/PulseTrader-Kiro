// SignalsView.swift — global signal feed across all watchlist symbols
import SwiftUI

struct SignalsView: View {
    @EnvironmentObject var signalsVM: SignalsViewModel
    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            Group {
                if signalsVM.filteredSignals.isEmpty {
                    emptyState
                } else {
                    List(signalsVM.filteredSignals) { signal in
                        SignalRowView(signal: signal)
                            .listRowBackground(Color.panelBackground)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Signals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilter.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter signals")
                }
            }
            .sheet(isPresented: $showFilter) {
                SignalFilterSheet()
                    .environmentObject(signalsVM)
                    .presentationDetents([.medium])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Watching for setups…")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Signals appear here when indicator confluence exceeds the threshold.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Signal row

struct SignalRowView: View {
    let signal: TradeSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Direction badge + symbol
                HStack(spacing: 6) {
                    Image(systemName: signal.direction == .buy
                          ? "arrowtriangle.up.fill"
                          : "arrowtriangle.down.fill")
                    .foregroundStyle(Color.forSignal(signal.direction))
                    .accessibilityHidden(true)

                    Text(signal.symbol)
                        .font(.headline)

                    Text(signal.direction.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(Color.forSignal(signal.direction))
                }

                Spacer()

                // Confidence
                VStack(alignment: .trailing, spacing: 2) {
                    Text(signal.displayConfidence)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.forSignal(signal.direction))
                    Text(signal.tier.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Confidence meter
            ConfidenceMeterView(confidence: signal.confidence)

            // Price info
            HStack(spacing: 16) {
                priceItem("Entry",  value: signal.entryPrice)
                priceItem("Stop",   value: signal.stopLoss, color: .loss)
                priceItem("Target", value: signal.takeProfit, color: .gain)
                if let rr = signal.riskReward {
                    Spacer()
                    Text("R:R \(String(format: "%.1f", rr))x")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Triggering indicators
            HStack(spacing: 4) {
                ForEach(signal.triggeringIndicators, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(signal.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(signal.symbol) \(signal.direction.rawValue) signal, \(signal.displayConfidence) confidence, " +
            "entry \(String(format: "%.2f", signal.entryPrice))"
        )
    }

    private func priceItem(_ label: String, value: Double,
                            color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

// MARK: - Filter sheet

struct SignalFilterSheet: View {
    @EnvironmentObject var signalsVM: SignalsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Direction") {
                    Picker("Direction", selection: $signalsVM.filterDirection) {
                        ForEach(SignalFilterDirection.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Confidence") {
                    Picker("Tier", selection: $signalsVM.filterTier) {
                        ForEach(SignalFilterTier.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Clear All Signals", role: .destructive) {
                        signalsVM.clear()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
