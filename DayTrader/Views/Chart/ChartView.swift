// ChartView.swift — Candlestick price chart with BB/EMA/VWAP overlays
// and MACD + RSI sub-panels
import SwiftUI
import Charts

struct ChartView: View {
    @ObservedObject var vm: ChartViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Timeframe picker
            Picker("Timeframe", selection: Binding(
                get: { vm.timeframe },
                set: { vm.changeTimeframe($0) }
            )) {
                ForEach(Timeframe.allCases, id: \.self) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if vm.isLoading {
                ProgressView("Loading chart…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.bars.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 4) {
                        pricePanel
                            .frame(height: 240)
                        macdPanel
                            .frame(height: 80)
                        rsiPanel
                            .frame(height: 80)
                    }
                    .frame(width: max(CGFloat(vm.bars.count) * 6, UIScreen.main.bounds.width))
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Price panel

    private var pricePanel: some View {
        Chart {
            // Candlestick bodies
            ForEach(vm.bars) { bar in
                let isGreen = bar.close >= bar.open
                RectangleMark(
                    x: .value("Time", bar.timestamp),
                    yStart: .value("Low",  min(bar.open, bar.close)),
                    yEnd:   .value("High", max(bar.open, bar.close)),
                    width: 4
                )
                .foregroundStyle(isGreen ? Color.gain : Color.loss)

                // Wick
                RuleMark(
                    x: .value("Time", bar.timestamp),
                    yStart: .value("WickLow",  bar.low),
                    yEnd:   .value("WickHigh", bar.high)
                )
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(isGreen ? Color.gain : Color.loss)
            }

            // Bollinger Bands
            if let bb = vm.indicators?.bb {
                ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                    if let upper = bb.upper[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp),
                                 y: .value("BB Upper", upper))
                        .foregroundStyle(Color.blue.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                    if let lower = bb.lower[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp),
                                 y: .value("BB Lower", lower))
                        .foregroundStyle(Color.blue.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
            }

            // EMA9
            if let ema9 = vm.indicators?.ema9 {
                ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                    if let val = ema9[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp),
                                 y: .value("EMA9", val))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }

            // VWAP
            if let vwap = vm.indicators?.vwap {
                ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                    if let val = vwap[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp),
                                 y: .value("VWAP", val))
                        .foregroundStyle(Color.purple.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }

            // Signal annotations
            ForEach(vm.signals) { signal in
                PointMark(
                    x: .value("Time", signal.timestamp),
                    y: .value("Price", signal.entryPrice)
                )
                .symbol {
                    Image(systemName: signal.direction == .buy
                          ? "arrowtriangle.up.fill"
                          : "arrowtriangle.down.fill")
                    .font(.caption)
                    .foregroundStyle(Color.forSignal(signal.direction))
                }
                .annotation(position: signal.direction == .buy ? .bottom : .top) {
                    Text(signal.direction.rawValue)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.forSignal(signal.direction))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisValueLabel().font(.caption2)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .background(Color.chartBackground)
        .accessibilityLabel("Price chart for \(vm.symbol)")
    }

    // MARK: - MACD panel

    private var macdPanel: some View {
        Chart {
            ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                if let hist = vm.indicators?.macd.histogram[safe: i] ?? nil {
                    BarMark(x: .value("Time", bar.timestamp),
                            y: .value("MACD Hist", hist),
                            width: 3)
                    .foregroundStyle(hist >= 0 ? Color.macdPositive : Color.macdNegative)
                }
                if let line = vm.indicators?.macd.line[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp),
                             y: .value("MACD", line))
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let sig = vm.indicators?.macd.signal[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp),
                             y: .value("Signal", sig))
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().font(.system(size: 8))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .overlay(alignment: .topLeading) {
            Text("MACD")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(4)
        }
        .background(Color.panelBackground)
        .accessibilityLabel("MACD panel")
    }

    // MARK: - RSI panel

    private var rsiPanel: some View {
        Chart {
            // Overbought / oversold reference lines
            RuleMark(y: .value("Overbought", 70))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
                .foregroundStyle(Color.loss.opacity(0.5))
            RuleMark(y: .value("Oversold", 30))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
                .foregroundStyle(Color.gain.opacity(0.5))
            RuleMark(y: .value("Mid", 50))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.neutral.opacity(0.3))

            ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                if let rsi = vm.indicators?.rsi[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp),
                             y: .value("RSI", rsi))
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [30, 50, 70]) { _ in
                AxisValueLabel().font(.system(size: 8))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .overlay(alignment: .topLeading) {
            Text("RSI")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(4)
        }
        .background(Color.panelBackground)
        .accessibilityLabel("RSI panel, overbought at 70, oversold at 30")
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
