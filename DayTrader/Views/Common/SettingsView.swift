// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("rsiPeriod")          private var rsiPeriod: Int    = Configuration.Indicators.rsiPeriod
    @AppStorage("bbPeriod")           private var bbPeriod: Int     = Configuration.Indicators.bbPeriod
    @AppStorage("bbStdDev")           private var bbStdDev: Double  = Configuration.Indicators.bbStdDev
    @AppStorage("macdFast")           private var macdFast: Int     = Configuration.Indicators.macdFast
    @AppStorage("macdSlow")           private var macdSlow: Int     = Configuration.Indicators.macdSlow
    @AppStorage("macdSignal")         private var macdSignalP: Int  = Configuration.Indicators.macdSignal
    @AppStorage("confluenceThreshold") private var confluenceThreshold: Double = Configuration.Signals.minConfluenceScore
    @AppStorage("notifyThreshold")    private var notifyThreshold: Double = 0.80

    @EnvironmentObject var signalsVM: SignalsViewModel
    @EnvironmentObject var tradeVM:   TradeViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Indicators") {
                    stepperRow("RSI Period", value: $rsiPeriod, range: 2...50)
                    stepperRow("BB Period", value: $bbPeriod, range: 5...50)
                    HStack {
                        Text("BB Std Dev")
                        Spacer()
                        Stepper(String(format: "%.1f", bbStdDev),
                                value: $bbStdDev, in: 0.5...4.0, step: 0.5)
                    }
                    stepperRow("MACD Fast", value: $macdFast, range: 2...50)
                    stepperRow("MACD Slow", value: $macdSlow, range: 5...100)
                    stepperRow("MACD Signal", value: $macdSignalP, range: 2...30)
                }

                Section("Signals") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confluence Threshold: \(Int(confluenceThreshold * 100))%")
                        Slider(value: $confluenceThreshold, in: 0.4...0.95, step: 0.05)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notify Above: \(Int(notifyThreshold * 100))%")
                        Slider(value: $notifyThreshold, in: 0.6...1.0, step: 0.05)
                    }
                    Button("Request Notification Permission") {
                        signalsVM.requestNotificationPermission()
                    }
                }

                Section("Paper Trading") {
                    HStack {
                        Text("Starting Capital")
                        Spacer()
                        Text(String(format: "$%.0f", Configuration.paperTradingInitialCapital))
                            .foregroundStyle(.secondary)
                    }
                    Button("Reset Paper Account", role: .destructive) {
                        tradeVM.resetPortfolio()
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0 (MVP)")
                    LabeledContent("Data Source", value: "Mock (GBM)")
                    LabeledContent("Min iOS", value: "17.0")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>,
                              range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
        }
    }
}
