// IndicatorTests.swift — verify indicator math against known values.
import XCTest
@testable import DayTrader

final class IndicatorTests: XCTestCase {

    // Helper: build quotes from close prices (OHLC all = close, fixed volume)
    private func quotes(_ closes: [Double], symbol: String = "TEST") -> [Quote] {
        let start = Date(timeIntervalSince1970: 0)
        return closes.enumerated().map { i, c in
            Quote(symbol: symbol, timestamp: start.addingTimeInterval(Double(i) * 60),
                  open: c, high: c, low: c, close: c, volume: 1000, previousClose: nil)
        }
    }

    // MARK: SMA

    func testSMA_basic() {
        let v = [1.0, 2, 3, 4, 5]
        let sma = SMACalculator.calculate(values: v, period: 3)
        XCTAssertNil(sma[0]); XCTAssertNil(sma[1])
        XCTAssertEqual(sma[2]!, 2.0, accuracy: 1e-9)   // (1+2+3)/3
        XCTAssertEqual(sma[3]!, 3.0, accuracy: 1e-9)   // (2+3+4)/3
        XCTAssertEqual(sma[4]!, 4.0, accuracy: 1e-9)   // (3+4+5)/3
    }

    func testSMA_tooFewValues() {
        let sma = SMACalculator.calculate(values: [1, 2], period: 5)
        XCTAssertEqual(sma.count, 2)
        XCTAssertTrue(sma.allSatisfy { $0 == nil })
    }

    // MARK: EMA

    func testEMA_seedIsSMA() {
        let v = [1.0, 2, 3, 4, 5, 6]
        let ema = EMACalculator.calculate(values: v, period: 3)
        // First non-nil (index 2) is the seed = SMA of first 3 = 2.0
        XCTAssertEqual(ema[2]!, 2.0, accuracy: 1e-9)
        // Next: 4*k + 2*(1-k), k = 2/4 = 0.5 → 4*.5 + 2*.5 = 3.0
        XCTAssertEqual(ema[3]!, 3.0, accuracy: 1e-9)
    }

    // MARK: RSI

    func testRSI_allGainsIs100() {
        let rising = quotes((1...20).map(Double.init))
        let rsi = RSICalculator.calculate(closes: rising.map(\.close), period: 14)
        // Steadily rising → avgLoss 0 → RSI defined as 100
        XCTAssertEqual(rsi.last!!, 100.0, accuracy: 1e-6)
    }

    func testRSI_rangeBounds() {
        let noisy = quotes([10,11,10.5,12,11,13,12.5,14,13,15,14,16,15,17,16,18])
        let rsi = RSICalculator.calculate(closes: noisy.map(\.close), period: 14)
        for v in rsi.compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 100)
        }
    }

    // MARK: MACD

    func testMACD_lineIsFastMinusSlow() {
        let closes = (1...60).map { Double($0) }
        let macd = MACDCalculator.calculate(closes: closes, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        // Where both EMAs exist, line should be finite and, for a steadily
        // rising series, positive (fast EMA above slow EMA).
        let lastLine = macd.line.compactMap { $0 }.last!
        XCTAssertGreaterThan(lastLine, 0)
        XCTAssertEqual(macd.line.count, closes.count)
    }

    // MARK: Bollinger Bands

    func testBB_upperAboveLower() {
        let closes = [10.0,11,10,12,11,13,12,14,13,15,14,16,15,17,16,18,17,19,18,20,19]
        let bb = BollingerBandCalculator.calculate(closes: closes, period: 20, stdDevMult: 2)
        let i = closes.count - 1
        XCTAssertNotNil(bb.upper[i]); XCTAssertNotNil(bb.lower[i]); XCTAssertNotNil(bb.middle[i])
        XCTAssertGreaterThan(bb.upper[i]!, bb.middle[i]!)
        XCTAssertGreaterThan(bb.middle[i]!, bb.lower[i]!)
    }

    func testBB_constantSeriesZeroWidth() {
        let flat = Array(repeating: 100.0, count: 25)
        let bb = BollingerBandCalculator.calculate(closes: flat, period: 20, stdDevMult: 2)
        let i = flat.count - 1
        // No variance → upper == lower == middle == 100
        XCTAssertEqual(bb.upper[i]!, 100, accuracy: 1e-9)
        XCTAssertEqual(bb.lower[i]!, 100, accuracy: 1e-9)
    }

    // MARK: ATR

    func testATR_positive() {
        let start = Date(timeIntervalSince1970: 0)
        let qs = (0..<20).map { i in
            Quote(symbol: "T", timestamp: start.addingTimeInterval(Double(i)*60),
                  open: 100, high: 102, low: 98, close: 100 + Double(i % 3),
                  volume: 1000, previousClose: nil)
        }
        let atr = ATRCalculator.calculate(quotes: qs, period: 14)
        XCTAssertGreaterThan(atr.last!!, 0)
    }

    // MARK: VWAP

    func testVWAP_equalsTypicalWhenConstantVolume() {
        // Constant price → VWAP equals that price
        let qs = quotes(Array(repeating: 50.0, count: 10))
        let vwap = VWAPCalculator.calculate(quotes: qs)
        XCTAssertEqual(vwap.last!!, 50.0, accuracy: 1e-9)
    }
}
