// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("rsiPeriod")           private var rsiPeriod: Int     = Configuration.Indicators.rsiPeriod
    @AppStorage("bbPeriod")            private var bbPeriod: Int      = Configuration.Indicators.bbPeriod
    @AppStorage("bbStdDev")            private var bbStdDev: Double   = Configuration.Indicators.bbStdDev
    @AppStorage("macdFast")            private var macdFast: Int      = Configuration.Indicators.macdFast
    @AppStorage("macdSlow")            private var macdSlow: Int      = Configuration.Indicators.macdSlow
    @AppStorage("macdSignal")          private var macdSignalP: Int   = Configuration.Indicators.macdSignal
    @AppStorage("confluenceThreshold") private var confluenceThreshold: Double = Configuration.Signals.minConfluenceScore
    @AppStorage("notifyThreshold")     private var notifyThreshold: Double = 0.80

    @EnvironmentObject var signalsVM: SignalsViewModel
    @EnvironmentObject var tradeVM:   TradeViewModel

    // Alpaca key entry state
    @State private var apiKey:    String = KeychainService.alpacaAPIKey    ?? ""
    @State private var apiSecret: String = KeychainService.alpacaAPISecret ?? ""
    @State private var showSecret = false
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus { case idle, saved, error }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Alpaca Data Source
                Section {
                    HStack {
                        Image(systemName: KeychainService.hasAlpacaCredentials
                              ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(KeychainService.hasAlpacaCredentials ? .green : .orange)
                        Text(KeychainService.hasAlpacaCredentials
                             ? "Connected — Alpaca (IEX feed)"
                             : "Not connected — using mock data")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Market Data Source")
                } footer: {
                    Text("Enter your Alpaca Paper Trading API keys. Keys are stored securely in the iOS Keychain and never leave your device.")
                }

                Section("Alpaca API Keys") {
                    HStack {
                        Text("API Key")
                            .frame(width: 80, alignment: .leading)
                        TextField("PKXXX…", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Secret")
                            .frame(width: 80, alignment: .leading)
                        if showSecret {
                            TextField("Secret key", text: $apiSecret)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Secret key", text: $apiSecret)
                                .font(.system(.body, design: .monospaced))
                        }
                        Button {
                            showSecret.toggle()
                        } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button("Save Keys") {
                            let k = apiKey.trimmingCharacters(in: .whitespaces)
                            let s = apiSecret.trimmingCharacters(in: .whitespaces)
                            guard !k.isEmpty, !s.isEmpty else { return }
                            let ok = KeychainService.save(k, for: .alpacaAPIKey)
                                  && KeychainService.save(s, for: .alpacaAPISecret)
                            saveStatus = ok ? .saved : .error
                        }
                        .disabled(apiKey.isEmpty || apiSecret.isEmpty)

                        Spacer()

                        switch saveStatus {
                        case .saved:
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        case .error:
                            Label("Failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red).font(.caption)
                        case .idle:
                            EmptyView()
                        }
                    }

                    if KeychainService.hasAlpacaCredentials {
                        Button("Remove Keys", role: .destructive) {
                            KeychainService.delete(.alpacaAPIKey)
                            KeychainService.delete(.alpacaAPISecret)
                            apiKey = ""
                            apiSecret = ""
                            saveStatus = .idle
                        }
                    }
                }

                // MARK: Restart notice
                if saveStatus == .saved {
                    Section {
                        Label("Restart the app to apply the new data source.", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Indicators
                Section("Indicators") {
                    stepperRow("RSI Period", value: $rsiPeriod, range: 2...50)
                    stepperRow("BB Period",  value: $bbPeriod,  range: 5...50)
                    HStack {
                        Text("BB Std Dev")
                        Spacer()
                        Stepper(String(format: "%.1f", bbStdDev),
                                value: $bbStdDev, in: 0.5...4.0, step: 0.5)
                    }
                    stepperRow("MACD Fast",   value: $macdFast,    range: 2...50)
                    stepperRow("MACD Slow",   value: $macdSlow,    range: 5...100)
                    stepperRow("MACD Signal", value: $macdSignalP, range: 2...30)
                }

                // MARK: Signals
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

                // MARK: Paper Trading
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

                // MARK: Disclaimer
                Section {
                    DisclaimerDetail()
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: "1.0 (MVP)")
                    LabeledContent("Data Source", value: Configuration.marketDataProvider.capitalized)
                    LabeledContent("Min iOS", value: "17.0")
                    Link("Alpaca Dashboard",
                         destination: URL(string: "https://app.alpaca.markets/paper/dashboard/overview")!)
                    Link("Get API Keys",
                         destination: URL(string: "https://app.alpaca.markets/paper/dashboard/overview")!)
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
