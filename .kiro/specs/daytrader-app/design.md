# DayTrader — Technical Design

## Architecture Overview

DayTrader follows the **MVVM + Combine** pattern across all modules. SwiftUI views observe ViewModels that expose `@Published` state. Business logic (indicator computation, signal evaluation) lives in pure, testable service classes that ViewModels call via `async/await`.

```
┌─────────────────────────────────────────────────────┐
│                     SwiftUI Views                    │
│  WatchlistView · ChartView · SignalsView · TradeView │
└────────────────────────┬────────────────────────────┘
                         │ @StateObject / @ObservedObject
┌────────────────────────▼────────────────────────────┐
│                     ViewModels                       │
│  WatchlistVM · ChartVM · SignalsVM · TradeVM         │
└──────┬──────────────┬──────────────┬────────────────┘
       │              │              │
       ▼              ▼              ▼
 MarketData     Indicator        Signal
 Service        Engine           Engine
       │
       ▼
 API Client (URLSession / WebSocket)
 Alpha Vantage | Polygon.io | Mock
```

---

## Module Design

### 1. Models

#### `Quote` — single OHLCV bar
```swift
struct Quote: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let timestamp: Date
    let open, high, low, close: Double
    let volume: Int
    var previousClose: Double   // for % change on first bar
}
```

#### `IndicatorResult` — union of all indicator outputs
```swift
enum IndicatorResult {
    case sma(period: Int, values: [Double])
    case ema(period: Int, values: [Double])
    case macd(line: [Double], signal: [Double], histogram: [Double])
    case rsi(period: Int, values: [Double])
    case bollingerBands(upper: [Double], middle: [Double], lower: [Double])
    case atr(period: Int, values: [Double])
    case volumeSMA(period: Int, values: [Double])
    case vwap(values: [Double])
}
```

#### `TradeSignal`
```swift
struct TradeSignal: Identifiable {
    let id: UUID
    let symbol: String
    let timestamp: Date
    let direction: SignalDirection      // .buy | .sell
    let confidence: Double              // 0.0 – 1.0
    let triggeringIndicators: [String]
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    var isNotified: Bool
}

enum SignalDirection: String, Codable { case buy, sell }
```

#### `Trade` — paper trade record
```swift
struct Trade: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let direction: TradeDirection       // .long | .short (v1: long only)
    let entryPrice: Double
    let entryTime: Date
    let quantity: Int
    var exitPrice: Double?
    var exitTime: Date?
    var stopLoss: Double
    var takeProfit: Double
    var realizedPnL: Double?

    var isOpen: Bool { exitPrice == nil }
    var unrealizedPnL: (currentPrice: Double) -> Double {
        { current in Double(quantity) * (current - entryPrice) }
    }
}
```

#### `Portfolio`
```swift
struct Portfolio: Codable {
    var cash: Double
    var openTrades: [Trade]
    var closedTrades: [Trade]

    var totalEquity: (prices: [String: Double]) -> Double  // cash + mark-to-market
    var dailyPnL: Double        // sum of realized + unrealized for today
    var winRate: Double         // closed trades only
    var profitFactor: Double    // gross profit / gross loss
}
```

---

### 2. Networking Layer

#### `MarketDataService` protocol
```swift
protocol MarketDataService {
    /// Fetch historical 1-min bars for the current/last session
    func fetchBars(symbol: String, limit: Int) async throws -> [Quote]

    /// Publisher that emits a new Quote whenever a fresh bar closes
    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never>
}
```

Two concrete implementations plus a mock:

| Class | Transport | Notes |
|-------|-----------|-------|
| `AlphaVantageService` | HTTPS REST | Polling; parses `TIME_SERIES_INTRADAY` JSON |
| `PolygonService` | HTTPS REST + WebSocket | REST for history, WS for real-time ticks |
| `MockMarketDataService` | In-process timer | Replays a pre-recorded session at real speed |

#### `APIClient` — generic URLSession wrapper
```swift
final class APIClient {
    func fetch<T: Decodable>(_ request: URLRequest) async throws -> T
    // Handles: rate-limit retry, exponential back-off, error mapping
}
```

API keys are read from the iOS **Keychain** (never UserDefaults). A `KeychainService` helper wraps `SecItemAdd/SecItemCopyMatching`.

---

### 3. Indicator Engine

All functions are **pure** (no side effects), operate on `[Double]` or `[Quote]`, and return aligned arrays (same count as input, with leading `nil`/`nan` for the warm-up period).

```
IndicatorEngine (struct, stateless)
├── SMACalculator
├── EMACalculator
├── MACDCalculator      (uses EMACalculator internally)
├── RSICalculator
├── BollingerBandCalculator (uses SMACalculator)
├── ATRCalculator
├── VolumeSMACalculator
└── VWAPCalculator
```

**VWAP** resets at session open (09:30 ET) — the engine tracks the current session boundary and accumulates `Σ(typical_price × volume) / Σvolume` from bar 0.

**Performance contract:** computing all indicators on 390 bars (full session) must complete in < 50 ms on an iPhone 12. Verified by unit tests with `XCTMeasure`.

---

### 4. Signal Engine

```swift
final class SignalEngine {
    func evaluate(
        bars: [Quote],
        indicators: [IndicatorResult],
        config: SignalConfiguration
    ) -> TradeSignal?
}
```

**Scoring rules (v1):**

| Rule | Weight | Buy condition | Sell condition |
|------|--------|--------------|----------------|
| RSI extreme | 0.25 | RSI < oversold (30) | RSI > overbought (70) |
| MACD crossover | 0.25 | MACD line crosses above signal | MACD line crosses below signal |
| Bollinger touch | 0.20 | Close ≤ lower band | Close ≥ upper band |
| EMA9 cross | 0.15 | Close crosses above EMA9 | Close crosses below EMA9 |
| VWAP relation | 0.10 | Close crosses above VWAP | Close crosses below VWAP |
| Volume confirmation | 0.05 | Volume > vol SMA | Volume > vol SMA |

- Weighted sum → **confluence score** 0–1
- Signal fires when score ≥ `config.minConfluenceScore` (default 0.6)
- Stop-loss = entry − (ATR × 1.5); Take-profit = entry + (ATR × 3.0)
- **Cooldown:** no re-signal for same symbol+direction within 5 bars

---

### 5. ViewModels

#### `WatchlistViewModel`
- `@Published var stocks: [Stock]`
- `@Published var sortOrder: WatchlistSortOrder` (.signal | .change | .alpha)
- Starts/stops a per-symbol Combine pipeline on appear/disappear
- Stores watchlist to UserDefaults on change

#### `ChartViewModel`
- `@Published var bars: [Quote]`
- `@Published var indicatorResults: [IndicatorResult]`
- `@Published var signals: [TradeSignal]`
- `@Published var selectedTimeframe: Timeframe` (._1min | ._5min | ._15min)
- Aggregates 1-min bars to requested timeframe on the fly

#### `SignalsViewModel`
- `@Published var allSignals: [TradeSignal]`
- `@Published var filter: SignalFilter` (symbol, direction, confidence tier)
- Sorted newest-first; triggers `UNUserNotificationCenter` for high-confidence signals

#### `TradeViewModel`
- `@Published var portfolio: Portfolio`
- `func submitOrder(_ order: PaperOrder)` — validates, fills (with slippage), updates portfolio
- `func closePosition(_ trade: Trade, at price: Double)`

---

### 6. View Hierarchy

```
ContentView (TabView)
├── Tab 1: WatchlistView
│   └── StockRowView (per symbol)
│       └── → StockDetailView (push)
│           ├── ChartView
│           │   ├── PriceChartPanel
│           │   ├── MACDPanel
│           │   └── RSIPanel
│           └── SignalListView (per-symbol signals)
├── Tab 2: SignalsView (global feed)
│   └── SignalRowView
│       └── → TradeView (sheet)
├── Tab 3: PortfolioView
│   ├── EquityCurveView
│   ├── PositionsListView
│   └── TradeHistoryView
└── Tab 4: SettingsView
    ├── APIKeySettingsView
    ├── IndicatorSettingsView
    └── NotificationSettingsView
```

---

### 7. Data Flow (per bar arrival)

```
Timer fires (every N seconds)
    │
    ▼
MarketDataService.fetchBars(symbol)
    │ [Quote] appended to bar cache
    ▼
IndicatorEngine.computeAll(bars)
    │ [IndicatorResult]
    ▼
SignalEngine.evaluate(bars, indicators)
    │ TradeSignal? (nil if no confluence)
    ▼
SignalsViewModel.append(signal)
    ├── WatchlistViewModel.updateBadge(signal)
    ├── ChartViewModel.appendAnnotation(signal)
    └── UNUserNotificationCenter (if confidence ≥ 0.8)
```

---

### 8. Persistence

| Data | Storage | Notes |
|------|---------|-------|
| Watchlist (symbols) | `UserDefaults` | Encoded as `[String]` |
| Indicator parameters | `UserDefaults` | Encoded `IndicatorConfig` struct |
| Paper trades | `UserDefaults` | Encoded `[Trade]` |
| API keys | iOS Keychain | `kSecClassGenericPassword` |
| Bar history | In-memory only | Cleared on app background |
| Signal history | In-memory (session) | Not persisted across launches in v1 |

---

### 9. Error Handling

```swift
enum DayTraderError: Error {
    case networkUnavailable
    case apiRateLimited(retryAfter: TimeInterval)
    case apiKeyMissing
    case apiKeyInvalid
    case dataGap(symbol: String, from: Date, to: Date)
    case insufficientBars(required: Int, available: Int)
    case paperOrderRejected(reason: String)
}
```

- All async calls wrap errors in `DayTraderError`
- ViewModels expose `@Published var errorMessage: String?` for in-UI banners
- Rate-limit responses trigger exponential back-off (1 s → 2 s → 4 s → max 60 s)

---

### 10. Testing Strategy

| Layer | Approach |
|-------|---------|
| Indicator calculators | XCTest unit tests with known datasets, compare to reference values |
| Signal engine | XCTest with fixture bar arrays; assert signals fire/don't fire |
| ViewModels | XCTest + `XCTestExpectation` for Combine publishers |
| Networking | Protocol-injected mocks; no live network calls in tests |
| UI | SwiftUI Previews for visual spot-check; no XCUITest in v1 |
