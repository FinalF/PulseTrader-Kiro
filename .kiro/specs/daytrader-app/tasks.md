# DayTrader — Implementation Tasks

## Status key
- [ ] Not started
- [~] In progress
- [x] Complete

---

## Phase 1 — Foundation

- [~] **T-01** Scaffold Xcode project (SwiftUI, iOS 17, no storyboards)
- [~] **T-02** Create `Configuration.swift` with all default values
- [ ] **T-03** Implement `KeychainService` for secure API key storage
- [~] **T-04** Define all model types: `Stock`, `Quote`, `IndicatorResult`, `TradeSignal`, `Trade`, `Portfolio`

## Phase 2 — Networking

- [ ] **T-05** Implement generic `APIClient` (async/await, retry, back-off)
- [ ] **T-06** Implement `MockMarketDataService` (replays session data at real speed)
- [ ] **T-07** Implement `AlphaVantageService` (REST, 1-min intraday endpoint)
- [ ] **T-08** Implement `PolygonService` (REST history + WebSocket real-time ticks)
- [ ] **T-09** Write unit tests for networking error paths using mocks

## Phase 3 — Indicators

- [ ] **T-10** `SMACalculator` + unit tests (compare against known values)
- [ ] **T-11** `EMACalculator` + unit tests
- [ ] **T-12** `MACDCalculator` (reuses EMA) + unit tests
- [ ] **T-13** `RSICalculator` + unit tests
- [ ] **T-14** `BollingerBandCalculator` (reuses SMA) + unit tests
- [ ] **T-15** `ATRCalculator` + unit tests
- [ ] **T-16** `VolumeSMACalculator` + unit tests
- [ ] **T-17** `VWAPCalculator` (session-aware reset) + unit tests
- [ ] **T-18** `IndicatorEngine` — aggregate entry point, verify < 50 ms on 390 bars

## Phase 4 — Signal Engine

- [ ] **T-19** `SignalEngine.evaluate()` with all 6 weighted rules
- [ ] **T-20** Cooldown / de-duplication logic (5-bar lockout)
- [ ] **T-21** ATR-based stop-loss and take-profit calculation
- [ ] **T-22** Unit tests: assert signals fire on synthetic bar fixtures; assert cooldown works

## Phase 5 — ViewModels

- [ ] **T-23** `WatchlistViewModel` (quote pipeline, sort, add/remove)
- [ ] **T-24** `ChartViewModel` (bar history, timeframe aggregation, signal annotations)
- [ ] **T-25** `SignalsViewModel` (global feed, filtering, notification trigger)
- [ ] **T-26** `TradeViewModel` + `PortfolioViewModel` (order submission, P&L, equity curve)

## Phase 6 — Views

- [ ] **T-27** `WatchlistView` + `StockRowView` (price ticker, signal badge, sort menu)
- [ ] **T-28** `StockDetailView` shell + navigation
- [ ] **T-29** `ChartView` — price panel (candlestick, BB, EMA, VWAP overlays)
- [ ] **T-30** `ChartView` — MACD sub-panel (line + histogram)
- [ ] **T-31** `ChartView` — RSI sub-panel (with overbought/oversold bands)
- [ ] **T-32** Signal annotation layer (buy/sell triangles on chart)
- [ ] **T-33** `SignalsView` (global feed, filter sheet)
- [ ] **T-34** `TradeView` (order ticket sheet, auto-filled stop/target)
- [ ] **T-35** `PortfolioView` (positions list, equity curve, daily summary)
- [ ] **T-36** `SettingsView` (API key, indicator params, notification prefs)

## Phase 7 — Polish & Hardening

- [ ] **T-37** `UNUserNotificationCenter` integration (request permission, schedule for high-confidence signals)
- [ ] **T-38** Offline / no-data state handling across all views
- [ ] **T-39** VoiceOver accessibility labels on price and signal elements
- [ ] **T-40** iPad layout (two-column split: watchlist + detail)
- [ ] **T-41** Dark-mode audit and color system (`Color+Trading.swift`)
- [ ] **T-42** Performance profiling: indicator pipeline < 500 ms, UI 60 fps

## Phase 8 — Testing & Release Prep

- [ ] **T-43** Full indicator unit-test suite (target: 90% coverage of `Indicators/`)
- [ ] **T-44** Signal engine integration tests with multi-day fixture data
- [ ] **T-45** ViewModel tests with injected mock services
- [ ] **T-46** App Store metadata (screenshots, description, privacy policy)
- [ ] **T-47** TestFlight internal build

---

## Open Questions / Decisions Needed

| # | Question | Default assumption | Owner |
|---|----------|--------------------|-------|
| OQ-1 | Which market data provider to use in production? | Alpha Vantage (free tier) | Product |
| OQ-2 | Should signals persist across app launches? | No (in-memory only, v1) | Product |
| OQ-3 | Add short-selling to paper trading in v1? | No | Product |
| OQ-4 | Support pre-market / after-hours data? | No (regular session only) | Product |
| OQ-5 | Include a backtester in v1? | No | Product |
| OQ-6 | Minimum number of watchlist symbols? | 1 (no max enforced) | Engineering |
| OQ-7 | Should 5-min and 15-min charts also trigger signals independently? | No — signals from 1-min only | Engineering |
| OQ-8 | Target a specific App Store category? | Finance | Product |
