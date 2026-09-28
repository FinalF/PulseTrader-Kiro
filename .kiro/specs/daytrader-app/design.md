# DayTrader — Technical Design

## Architecture Overview

> **Last updated:** Sep 28, 2026 — reflects the app as built and running on device.
> For exact indicator/signal formulas see `algorithm.md`.

PulseTrader (codename DayTrader) follows the **MVVM + Combine** pattern. SwiftUI views observe `@MainActor` ViewModels that expose `@Published` state. Business logic (indicator computation, signal evaluation) lives in pure, stateless functions that ViewModels call via `async/await`.

```
┌───────────────────────────────────────────────────────────┐
│                        SwiftUI Views                        │
│  WatchlistView · ChartView · SignalsView · Portfolio ·      │
│  SettingsView · IndicatorBreakdownView                      │
└────────────────────────┬────────────────────────────────────┘
                         │ @StateObject / @EnvironmentObject
┌────────────────────────▼────────────────────────────────────┐
│                        ViewModels (@MainActor)              │
│  WatchlistVM · ChartVM · SignalsVM · TradeVM                │
└──────┬──────────────┬──────────────┬───────────────────────┘
       │              │              │
       ▼              ▼              ▼
 MarketData     IndicatorEngine   SignalEngine
 Service        (8 calculators)   (6 weighted rules)
       │
       ▼
 AlpacaService (REST + WebSocket)  |  MockMarketDataService (GBM)
       │
       ▼
 KeychainService (API key storage)
```

**AppServices** (in `DayTraderApp.swift`) is a global enum that resolves the
`MarketDataService` singleton once at launch: `AlpacaService` if Keychain has
credentials, otherwise `MockMarketDataService`. Both `WatchlistViewModel` and each
`ChartViewModel` share this same instance.

---

## Module Design

### 1. Models

#### `Quote` — single OHLCV bar
```swift
struct Quote: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let timestamp: Date
    let open, high, low, close: Double
    let volume: Int
    var previousClose: Double?   // nil = no prior close (first bar of session)

    var typicalPrice: Double { (high + low + close) / 3 }
    var isGreen: Bool?          // nil for doji (open == close)
}
```

#### `IndicatorBundle` — all indicator outputs for one bar series
Indicators are exposed as a single struct of aligned `[Double?]` arrays (leading nils
for warm-up), NOT an enum. `IndicatorEngine.compute(quotes:)` returns this bundle.
```swift
struct IndicatorBundle {
    let ema9:      [Double?]
    let sma20:     [Double?]
    let macd:      MACDCalculator.Result   // line, signal, histogram
    let rsi:       [Double?]
    let bb:        BollingerBandCalculator.Result  // upper, middle, lower, bandwidth, %B
    let atr:       [Double?]
    let volumeSMA: [Double?]
    let vwap:      [Double?]
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
protocol MarketDataService: AnyObject {   // AnyObject → allows weak refs
    func fetchBars(symbol: String, limit: Int) async throws -> [Quote]
    func fetchBars(symbol: String, range: ChartRange) async throws -> [Quote]
    func fetchLatestQuote(symbol: String) async throws -> Quote?
    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never>
}
```

`ChartRange` is `1D / 5D / 1M / 3M / 1Y`, each mapping to an Alpaca timeframe
(`1Min / 15Min / 1Hour / 1Day`) and a look-back window.

| Class | Transport | Notes |
|-------|-----------|-------|
| `AlpacaService` | HTTPS REST + WebSocket | REST `/v2/stocks/{sym}/bars` for history; WS `stream.data.alpaca.markets/v2/iex` for live 1-min bars. IEX feed (free tier). |
| `MockMarketDataService` | In-process timer | Geometric Brownian Motion; generates intraday + multi-day bars; 1 bar/sec replay for demo. |

**Provider selection:** `AppServices.marketData` chooses Alpaca when
`KeychainService.hasAlpacaCredentials` is true, else Mock. Resolved once at launch.

**Key API details learned in implementation:**
- Alpaca returns `{"bars": null}` (not `[]`) when there is no data → `AlpacaBarsResponse.bars`
  is `[AlpacaBar]?` and treated as empty.
- The `next_page_token` field is snake_case (must match exactly for Codable).
- `1D` fetch uses the **last trading day** (walks back over weekends), and the reliable
  rolling-window `fetchBars(range:)` is used everywhere — `fetchBars(limit:)` with a
  strict 09:30-ET-today start returns empty on the IEX free tier after hours.

API keys are stored in the iOS **Keychain** (`KeychainService`, wrapping
`SecItemAdd/SecItemCopyMatching`), entered by the user in Settings. Never in source
or UserDefaults.

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
    // Emits a signal only if confluence clears the threshold
    func evaluate(quotes: [Quote], indicators: IndicatorBundle,
                  barIndex: Int) -> TradeSignal?

    // Always returns per-rule scores (used by IndicatorBreakdownView),
    // regardless of whether a signal fires
    func breakdown(quotes: [Quote], indicators: IndicatorBundle) -> SignalBreakdown?
}
```

**The full scoring algorithm — rules, weights, confluence math, ATR stops, and
cooldown — is documented in `algorithm.md`.** Summary: 6 weighted rules
(RSI 0.25, MACD 0.25, BB 0.20, EMA9 0.15, VWAP 0.10, Volume 0.05) → weighted confluence
score; signal fires at ≥ 0.60; ATR-based 1.5×/3.0× stop/target; 5-bar cooldown.

`SignalBreakdown` / `RuleBreakdown` are public types so the UI can show live per-rule
results (which indicator voted which way, and why) even when no signal fires.

---

### 5. ViewModels

#### `WatchlistViewModel`
- `@Published var stocks: [Stock]`
- `@Published var sortOrder: WatchlistSortOrder` (.signal | .change | .alpha)
- Starts/stops a per-symbol Combine pipeline on appear/disappear
- Stores watchlist to UserDefaults on change

#### `ChartViewModel`
- `@Published var bars: [Quote]`
- `@Published var indicators: IndicatorBundle?`
- `@Published var signals: [TradeSignal]`
- `@Published var signalBreakdown: SignalBreakdown?` (live per-rule scores)
- `@Published var timeframe: Timeframe` (1m / 5m / 15m — used only on 1D range)
- `@Published var range: ChartRange` (1D / 5D / 1M / 3M / 1Y)
- Aggregates 1-min bars to the requested timeframe; filters to trading hours;
  subscribes to the live WebSocket only when range == 1D

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

---

### 11. Key Implementation Decisions & Gotchas

Lessons captured during development so they aren't re-litigated:

**`Stock` Equatable must compare quote/signal fields.**
SwiftUI uses `==` to decide whether to redraw a row. An early version compared only
`id`, so when a stock's `latestQuote` changed from nil → a real price, SwiftUI saw the
two `Stock` values as "equal" and skipped the redraw — the watchlist price was stuck at
`--` on device (it only worked in the simulator because mock data filled the price at
init). `Stock.==` now also compares `latestQuote.close`, `previousClose`, and
`latestSignal.id`.

**Charts use an integer index X-axis, not `Date`.**
Swift Charts plots real time on a continuous axis, which leaves ugly gaps over weekends
and overnight. All chart marks use the bar's array **index** as X; the timestamp is only
shown in the drag tooltip. This compresses out non-trading time.

**Indicator overlay lines need a `series:` identifier.**
Multiple `LineMark`s that share the same y-value label get coalesced by Swift Charts into
one series and rendered in a single color. Each overlay (BB, EMA9, VWAP) now passes a
distinct `series: .value("s", …)` plus `.chartForegroundStyleScale` to keep colors apart.

**Trading-hours filtering is split by range.**
`filterIntradayHours` (1D) strips weekends AND pre/after-market bars (09:30–16:00 ET).
`stripWeekends` (5D/1M/3M/1Y) only removes weekends — applying the intraday time filter
to hourly/daily bars would delete everything.

**Watchlist persistence replaces, not merges.**
`loadWatchlist()` fully replaces the default list with the saved symbols when one exists,
so stocks the user removed stay removed across launches.

**Serial price fetch on launch.**
Watchlist symbols are fetched serially (not concurrently) to avoid Alpaca free-tier rate
limiting when the list is large.

**Timezone.**
All market-hours logic uses `America/New_York` (DST-aware) via `MarketHours` and the
chart/service filters — never the device's local timezone.
