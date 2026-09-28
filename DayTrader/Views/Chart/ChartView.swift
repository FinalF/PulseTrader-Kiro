// ChartView.swift
// X-axis: fully hidden to avoid date gaps on weekends.
// Drag interaction: shows selected bar's timestamp + indicator values in top tooltip.
// Index-based X so weekend/holiday gaps are naturally compressed out.
import SwiftUI
import Charts

struct ChartView: View {
    @ObservedObject var vm: ChartViewModel
    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {

            // ── Range selector ──────────────────────────────────────────
            rangeSelector
                .padding(.horizontal)
                .padding(.top, 8)

            // ── Timeframe picker (1D only) ──────────────────────────────
            if vm.range.isIntraday {
                Picker("Timeframe", selection: Binding(
                    get: { vm.timeframe },
                    set: { vm.changeTimeframe($0) }
                )) {
                    ForEach(Timeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            // ── Content ─────────────────────────────────────────────────
            if vm.isLoading {
                ProgressView("Loading chart…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    ScrollView {
                        Text(err)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    Button("Retry") { vm.load() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if vm.bars.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Tooltip (always visible; shows latest when nothing selected)
                tooltipBar
                    .frame(height: 32)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)

                let chartWidth = max(CGFloat(vm.bars.count) * 6,
                                     UIScreen.main.bounds.width - 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 2) {
                        pricePanel.frame(height: 240)
                        macdPanel .frame(height: 80)
                        rsiPanel  .frame(height: 80)
                    }
                    .frame(width: chartWidth)
                    .padding(.horizontal, 8)
                }
                .defaultScrollAnchor(.trailing)
            }
        }
    }

    // MARK: - Range selector

    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(ChartRange.allCases, id: \.self) { r in
                Button { vm.changeRange(r) } label: {
                    Text(r.rawValue)
                        .font(.system(size: 13, weight: vm.range == r ? .bold : .regular))
                        .foregroundStyle(vm.range == r ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(vm.range == r ? Color.accentColor.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tooltip bar

    private var tooltipBar: some View {
        let idx = selectedIndex ?? (vm.bars.count - 1)
        let bar = vm.bars[safe: idx]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {

                // Date/time — only shown when user is dragging
                if let bar, selectedIndex != nil {
                    Text(formattedTimestamp(bar.timestamp))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.trailing, 4)
                    divider()
                } else {
                    // Hint when not dragging
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.caption2)
                        Text("Drag to inspect")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
                }

                // OHLC
                if let bar {
                    tipVal("O", bar.open,  .primary)
                    tipVal("H", bar.high,  .gain)
                    tipVal("L", bar.low,   .loss)
                    tipVal("C", bar.close, bar.close >= bar.open ? .gain : .loss)
                }
                divider()

                // Overlay indicators
                if let v = vm.indicators?.ema9[safe: idx] ?? nil { tipVal("EMA9", v, .orange) }
                if let v = vm.indicators?.vwap[safe: idx] ?? nil { tipVal("VWAP", v, .purple) }
                if let u = vm.indicators?.bb.upper[safe: idx] ?? nil { tipVal("BB↑", u, .blue) }
                if let l = vm.indicators?.bb.lower[safe: idx] ?? nil { tipVal("BB↓", l, .blue) }
                divider()

                // MACD
                if let line = vm.indicators?.macd.line[safe: idx] ?? nil,
                   let sig  = vm.indicators?.macd.signal[safe: idx] ?? nil,
                   let hist = vm.indicators?.macd.histogram[safe: idx] ?? nil {
                    tipVal("MACD", line, .blue,   4)
                    tipVal("Sig",  sig,  .orange, 4)
                    tipVal("Hist", hist, hist >= 0 ? .macdPositive : .macdNegative, 4)
                }
                divider()

                // RSI
                if let rsi = vm.indicators?.rsi[safe: idx] ?? nil {
                    tipVal("RSI", rsi, rsi > 70 ? .loss : rsi < 30 ? .gain : .purple, 1)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Color.panelBackground.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func tipVal(_ label: String, _ value: Double,
                         _ color: Color, _ dec: Int = 2) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(String(format: "%.\(dec)f", value))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func divider() -> some View {
        Rectangle().fill(Color(.separator)).frame(width: 0.5, height: 14)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        switch vm.range {
        case .oneDay:
            return date.formatted(.dateTime.month().day().hour().minute())
        case .fiveDay:
            return date.formatted(.dateTime.month().day().hour().minute())
        case .oneMonth, .threeMonth, .oneYear:
            return date.formatted(.dateTime.year().month().day())
        }
    }

    // MARK: - Chart legend

    private var chartLegend: some View {
        HStack(spacing: 8) {
            legendItem("BB", Color.indicatorBB)
            legendItem("EMA9", Color.indicatorEMA9)
            legendItem("VWAP", Color.indicatorVWAP)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(4)
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 12, height: 2)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Price panel (index X-axis → no weekend gaps)

    private var pricePanel: some View {
        Chart {
            // Candles
            ForEach(Array(vm.bars.enumerated()), id: \.offset) { i, bar in
                let isGreen = bar.close >= bar.open
                RectangleMark(
                    x: .value("i", i),
                    yStart: .value("Lo", min(bar.open, bar.close)),
                    yEnd:   .value("Hi", max(bar.open, bar.close)),
                    width: 4
                )
                .foregroundStyle(isGreen ? Color.gain : Color.loss)

                RuleMark(x: .value("i", i),
                         yStart: .value("WL", bar.low),
                         yEnd:   .value("WH", bar.high))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(isGreen ? Color.gain : Color.loss)
            }

            // BB — light fill + distinct steel-blue border lines
            if let bb = vm.indicators?.bb {
                let pairs: [(Int, Double, Double)] = vm.bars.indices.compactMap { i in
                    guard let u = bb.upper[safe: i] ?? nil,
                          let l = bb.lower[safe: i] ?? nil else { return nil }
                    return (i, u, l)
                }
                ForEach(pairs, id: \.0) { i, upper, lower in
                    AreaMark(x: .value("i", i), yStart: .value("BBL", lower), yEnd: .value("BBU", upper))
                        .foregroundStyle(Color.indicatorBB.opacity(0.06))
                }
                ForEach(pairs, id: \.0) { i, upper, _ in
                    LineMark(x: .value("i", i), y: .value("price", upper),
                             series: .value("s", "BB Upper"))
                        .foregroundStyle(by: .value("s", "BB Upper"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(pairs, id: \.0) { i, _, lower in
                    LineMark(x: .value("i", i), y: .value("price", lower),
                             series: .value("s", "BB Lower"))
                        .foregroundStyle(by: .value("s", "BB Lower"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            // EMA9 — orange
            if let ema9 = vm.indicators?.ema9 {
                ForEach(Array(vm.bars.enumerated()), id: \.offset) { i, _ in
                    if let v = ema9[safe: i] ?? nil {
                        LineMark(x: .value("i", i), y: .value("price", v),
                                 series: .value("s", "EMA9"))
                            .foregroundStyle(by: .value("s", "EMA9"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            // VWAP — purple
            if let vwap = vm.indicators?.vwap {
                ForEach(Array(vm.bars.enumerated()), id: \.offset) { i, _ in
                    if let v = vwap[safe: i] ?? nil {
                        LineMark(x: .value("i", i), y: .value("price", v),
                                 series: .value("s", "VWAP"))
                            .foregroundStyle(by: .value("s", "VWAP"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            // Crosshair
            if let idx = selectedIndex {
                RuleMark(x: .value("i", idx))
                    .foregroundStyle(Color(.label).opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            // Signals
            ForEach(vm.signals) { signal in
                if let idx = vm.bars.firstIndex(where: {
                    abs($0.timestamp.timeIntervalSince(signal.timestamp)) < 60
                }) {
                    PointMark(x: .value("i", idx), y: .value("P", signal.entryPrice))
                        .symbol {
                            Image(systemName: signal.direction == .buy
                                  ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption)
                            .foregroundStyle(Color.forSignal(signal.direction))
                        }
                }
            }
        }
        .chartForegroundStyleScale([
            "BB Upper": Color.indicatorBB.opacity(0.6),
            "BB Lower": Color.indicatorBB.opacity(0.6),
            "EMA9":     Color.indicatorEMA9,
            "VWAP":     Color.indicatorVWAP,
        ])
        .chartLegend(.hidden)   // we render our own legend overlay
        .chartXAxis(.hidden)
        .chartYScale(domain: vm.yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisValueLabel().font(.caption2)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { updateSelection($0.location, proxy, geo) }
                        .onEnded { _ in } // keep selection after lift
                    )
                    .onTapGesture { selectedIndex = nil }
            }
        }
        .background(Color.chartBackground)
        .overlay(alignment: .topLeading) { chartLegend }
        .accessibilityLabel("Price chart for \(vm.symbol)")
    }

    // MARK: - MACD panel

    private var macdPanel: some View {
        Chart {
            ForEach(Array(vm.bars.enumerated()), id: \.offset) { i, _ in
                if let h = vm.indicators?.macd.histogram[safe: i] ?? nil {
                    BarMark(x: .value("i", i), y: .value("H", h), width: 3)
                        .foregroundStyle(h >= 0 ? Color.macdPositive : Color.macdNegative)
                }
                if let l = vm.indicators?.macd.line[safe: i] ?? nil {
                    LineMark(x: .value("i", i), y: .value("M", l))
                        .foregroundStyle(Color.indicatorMACD)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                }
                if let s = vm.indicators?.macd.signal[safe: i] ?? nil {
                    LineMark(x: .value("i", i), y: .value("S", s))
                        .foregroundStyle(Color.indicatorSig)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            if let idx = selectedIndex {
                RuleMark(x: .value("i", idx))
                    .foregroundStyle(Color(.label).opacity(0.25))
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
            Text("MACD").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary).padding(4)
        }
        .background(Color.panelBackground)
    }

    // MARK: - RSI panel

    private var rsiPanel: some View {
        Chart {
            RuleMark(y: .value("OB", 70)).foregroundStyle(Color.loss.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
            RuleMark(y: .value("OS", 30)).foregroundStyle(Color.gain.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4]))
            ForEach(Array(vm.bars.enumerated()), id: \.offset) { i, _ in
                if let r = vm.indicators?.rsi[safe: i] ?? nil {
                    LineMark(x: .value("i", i), y: .value("RSI", r))
                        .foregroundStyle(Color.indicatorRSI)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            if let idx = selectedIndex {
                RuleMark(x: .value("i", idx))
                    .foregroundStyle(Color(.label).opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
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
            Text("RSI").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary).padding(4)
        }
        .background(Color.panelBackground)
    }

    // MARK: - Drag helper

    private func updateSelection(_ location: CGPoint,
                                  _ proxy: ChartProxy,
                                  _ geo: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let relX = location.x - geo[frame].origin.x
        guard let idx: Int = proxy.value(atX: relX) else { return }
        selectedIndex = max(0, min(idx, vm.bars.count - 1))
    }
}

// MARK: - Safe subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
