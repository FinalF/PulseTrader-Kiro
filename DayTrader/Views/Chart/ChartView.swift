// ChartView.swift — Candlestick chart with BB/EMA/VWAP, MACD, RSI
// Fix 1: X-axis time labels shown on bottom panel (RSI)
// Fix 2: Crosshair scrubber shows indicator values at selected bar
import SwiftUI
import Charts

struct ChartView: View {
    @ObservedObject var vm: ChartViewModel

    // Crosshair state — index of the bar the user is hovering/dragging on
    @State private var selectedIndex: Int? = nil

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
                // Indicator tooltip bar — shows values for selected bar
                indicatorTooltip
                    .frame(height: 28)
                    .padding(.horizontal, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 2) {
                        pricePanel
                            .frame(height: 240)
                        macdPanel
                            .frame(height: 80)
                        rsiPanel   // ← X-axis time labels live here
                            .frame(height: 96)
                    }
                    .frame(width: max(CGFloat(vm.bars.count) * 6, UIScreen.main.bounds.width - 16))
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Indicator tooltip

    @ViewBuilder
    private var indicatorTooltip: some View {
        if let idx = selectedIndex, let bar = vm.bars[safe: idx] {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // OHLCV
                    tooltipItem("O", value: bar.open,  color: .primary)
                    tooltipItem("H", value: bar.high,  color: .gain)
                    tooltipItem("L", value: bar.low,   color: .loss)
                    tooltipItem("C", value: bar.close, color: bar.close >= bar.open ? .gain : .loss)
                    tooltipDivider()

                    // EMA9
                    if let v = vm.indicators?.ema9[safe: idx] ?? nil {
                        tooltipItem("EMA9", value: v, color: .orange)
                    }
                    // VWAP
                    if let v = vm.indicators?.vwap[safe: idx] ?? nil {
                        tooltipItem("VWAP", value: v, color: .purple)
                    }
                    // BB
                    if let u = vm.indicators?.bb.upper[safe: idx] ?? nil,
                       let l = vm.indicators?.bb.lower[safe: idx] ?? nil {
                        tooltipItem("BB↑", value: u, color: .blue.opacity(0.7))
                        tooltipItem("BB↓", value: l, color: .blue.opacity(0.7))
                    }
                    tooltipDivider()

                    // MACD
                    if let line = vm.indicators?.macd.line[safe: idx] ?? nil,
                       let sig  = vm.indicators?.macd.signal[safe: idx] ?? nil,
                       let hist = vm.indicators?.macd.histogram[safe: idx] ?? nil {
                        tooltipItem("MACD", value: line, decimals: 4, color: .blue)
                        tooltipItem("Sig",  value: sig,  decimals: 4, color: .orange)
                        tooltipItem("Hist", value: hist, decimals: 4,
                                    color: hist >= 0 ? .macdPositive : .macdNegative)
                    }
                    tooltipDivider()

                    // RSI
                    if let rsi = vm.indicators?.rsi[safe: idx] ?? nil {
                        tooltipItem("RSI", value: rsi, decimals: 1,
                                    color: rsi > 70 ? .loss : rsi < 30 ? .gain : .purple)
                    }

                    // Timestamp
                    Text(bar.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 8)
            }
            .background(Color.panelBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // Default: show latest values
            if let idx = vm.bars.indices.last {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Drag to inspect")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let rsi = vm.indicators?.rsi[safe: idx] ?? nil {
                        tooltipItem("RSI", value: rsi, decimals: 1,
                                    color: rsi > 70 ? .loss : rsi < 30 ? .gain : .purple)
                    }
                    if let line = vm.indicators?.macd.line[safe: idx] ?? nil {
                        tooltipItem("MACD", value: line, decimals: 4, color: .blue)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func tooltipItem(_ label: String, value: Double,
                               decimals: Int = 2, color: Color = .primary) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.\(decimals)f", value))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func tooltipDivider() -> some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 16)
    }

    // MARK: - Price panel

    private var pricePanel: some View {
        Chart {
            // Candlestick bodies + wicks
            ForEach(vm.bars) { bar in
                let isGreen = bar.close >= bar.open
                RectangleMark(
                    x: .value("Time", bar.timestamp),
                    yStart: .value("BodyLow",  min(bar.open, bar.close)),
                    yEnd:   .value("BodyHigh", max(bar.open, bar.close)),
                    width: 4
                )
                .foregroundStyle(isGreen ? Color.gain : Color.loss)

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
                        LineMark(x: .value("Time", bar.timestamp), y: .value("BB↑", upper))
                            .foregroundStyle(Color.blue.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                    if let lower = bb.lower[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp), y: .value("BB↓", lower))
                            .foregroundStyle(Color.blue.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
            }

            // EMA9
            if let ema9 = vm.indicators?.ema9 {
                ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                    if let val = ema9[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp), y: .value("EMA9", val))
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }

            // VWAP
            if let vwap = vm.indicators?.vwap {
                ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                    if let val = vwap[safe: i] ?? nil {
                        LineMark(x: .value("Time", bar.timestamp), y: .value("VWAP", val))
                            .foregroundStyle(Color.purple.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }

            // Crosshair rule line
            if let idx = selectedIndex, let bar = vm.bars[safe: idx] {
                RuleMark(x: .value("Selected", bar.timestamp))
                    .foregroundStyle(Color(.label).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }

            // Signal annotations
            ForEach(vm.signals) { signal in
                PointMark(
                    x: .value("Time", signal.timestamp),
                    y: .value("Price", signal.entryPrice)
                )
                .symbol {
                    Image(systemName: signal.direction == .buy
                          ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
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
        .chartXAxis(.hidden)   // price panel shares X with RSI panel below
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisValueLabel().font(.caption2)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location, proxy: proxy, geo: geo)
                            }
                            .onEnded { _ in
                                // keep last selection visible
                            }
                    )
                    .onTapGesture {
                        selectedIndex = nil
                    }
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
                            y: .value("Hist", hist), width: 3)
                    .foregroundStyle(hist >= 0 ? Color.macdPositive : Color.macdNegative)
                }
                if let line = vm.indicators?.macd.line[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp), y: .value("MACD", line))
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let sig = vm.indicators?.macd.signal[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp), y: .value("Signal", sig))
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            // Crosshair
            if let idx = selectedIndex, let bar = vm.bars[safe: idx] {
                RuleMark(x: .value("Selected", bar.timestamp))
                    .foregroundStyle(Color(.label).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
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

    // MARK: - RSI panel (X-axis time labels shown here)

    private var rsiPanel: some View {
        Chart {
            RuleMark(y: .value("OB", 70))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
                .foregroundStyle(Color.loss.opacity(0.5))
            RuleMark(y: .value("OS", 30))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
                .foregroundStyle(Color.gain.opacity(0.5))
            RuleMark(y: .value("Mid", 50))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.neutral.opacity(0.3))

            ForEach(Array(zip(vm.bars.indices, vm.bars)), id: \.0) { i, bar in
                if let rsi = vm.indicators?.rsi[safe: i] ?? nil {
                    LineMark(x: .value("Time", bar.timestamp), y: .value("RSI", rsi))
                        .foregroundStyle(Color.purple)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            // Crosshair
            if let idx = selectedIndex, let bar = vm.bars[safe: idx] {
                RuleMark(x: .value("Selected", bar.timestamp))
                    .foregroundStyle(Color(.label).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartYScale(domain: 0...100)
        // ← X-axis time labels shown on the bottom panel only
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: xAxisStride)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.system(size: 9))
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                }
            }
        }
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

    // MARK: - Helpers

    /// How many minutes between X-axis labels depending on timeframe + bar count
    private var xAxisStride: Int {
        let count = vm.bars.count
        switch vm.timeframe {
        case .oneMin:
            return count > 200 ? 30 : count > 60 ? 15 : 5
        case .fiveMin:
            return count > 60 ? 15 : 5
        case .fifteenMin:
            return 30
        }
    }

    /// Map a drag location to the nearest bar index
    private func updateSelection(at location: CGPoint,
                                  proxy: ChartProxy,
                                  geo: GeometryProxy) {
        let origin = geo[proxy.plotFrame!].origin
        let relX = location.x - origin.x
        guard let date: Date = proxy.value(atX: relX) else { return }

        // Find nearest bar by timestamp
        let nearest = vm.bars.enumerated().min(by: {
            abs($0.element.timestamp.timeIntervalSince(date)) <
            abs($1.element.timestamp.timeIntervalSince(date))
        })
        selectedIndex = nearest?.offset
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
