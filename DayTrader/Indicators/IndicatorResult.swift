// IndicatorResult.swift — typed union of all indicator outputs
import Foundation

enum IndicatorResult {
    case sma(period: Int, values: [Double?])
    case ema(period: Int, values: [Double?])
    case macd(line: [Double?], signal: [Double?], histogram: [Double?])
    case rsi(period: Int, values: [Double?])
    case bollingerBands(upper: [Double?], middle: [Double?], lower: [Double?])
    case atr(period: Int, values: [Double?])
    case volumeSMA(period: Int, values: [Double?])
    case vwap(values: [Double?])

    /// Latest (last) non-nil value for quick access
    var latestValue: Double? {
        switch self {
        case .sma(_, let v),
             .ema(_, let v),
             .rsi(_, let v),
             .atr(_, let v),
             .volumeSMA(_, let v),
             .vwap(let v):          return v.last(where: { $0 != nil }) ?? nil
        case .macd(let line, _, _): return line.last(where: { $0 != nil }) ?? nil
        case .bollingerBands(_, let mid, _): return mid.last(where: { $0 != nil }) ?? nil
        }
    }
}
