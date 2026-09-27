# PulseTrader

A native iOS app for intra-day stock trading assistance. PulseTrader monitors a watchlist of stocks, computes technical indicators in real time, and fires buy/sell signals based on weighted indicator confluence — helping traders spot setups faster without the noise.

> **Status:** MVP — fully functional with mock market data. Real data provider integration (Alpha Vantage / Polygon.io) coming in v2.

---

## Screenshots

_Coming soon_

---

## Features

- **Live Watchlist** — price ticker, % change, and signal badge per symbol; sort by signal strength, change, or alphabetically
- **Interactive Charts** — candlestick chart with Bollinger Bands, EMA9, and VWAP overlays; MACD and RSI sub-panels; 1/5/15-min timeframes
- **Signal Engine** — weighted confluence scoring across 6 indicator rules; buy/sell signals annotated directly on the chart
- **Signal Feed** — real-time global feed with confidence meter, entry/stop/target prices, and R:R ratio; push notifications for high-confidence signals (≥ 80%)
- **Paper Trading** — simulated Market and Limit orders, ATR-based stop/target pre-fill, real-time unrealized P&L, win rate and profit factor tracking
- **Settings** — all indicator parameters adjustable at runtime; notification threshold configurable

---

## Technical Indicators

| Indicator | Details |
|-----------|---------|
| EMA | 9-period (configurable) |
| SMA | 20-period (configurable) |
| MACD | 12/26/9 (configurable), Wilder smoothing |
| RSI | 14-period (configurable), Wilder smoothing |
| Bollinger Bands | 20-period, 2σ (configurable), %B and bandwidth |
| ATR | 14-period, used for stop/target sizing |
| VWAP | Session-cumulative, resets at 09:30 ET |
| Volume SMA | 20-period spike detection |

## Signal Rules

| Rule | Weight | Buy | Sell |
|------|--------|-----|------|
| RSI extreme | 25% | RSI < 30 | RSI > 70 |
| MACD crossover | 25% | Line crosses above signal | Line crosses below signal |
| Bollinger touch | 20% | Close ≤ lower band | Close ≥ upper band |
| EMA9 cross | 15% | Close crosses above EMA9 | Close crosses below EMA9 |
| VWAP cross | 10% | Close crosses above VWAP | Close crosses below VWAP |
| Volume spike | 5% | Volume > vol SMA | Volume > vol SMA |

Signal fires when confluence score ≥ 60% (configurable). 5-bar cooldown prevents duplicate signals.

---

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 5.9+
- No third-party dependencies (uses Apple Swift Charts + Combine)

---

## Getting Started

### 1. Clone

```bash
git clone https://github.com/flameyufeng/PulseTrader-Kiro.git
cd PulseTrader-Kiro
```

### 2. Generate Xcode project

```bash
brew install xcodegen   # if not already installed
xcodegen generate
```

### 3. Open and run

```bash
open DayTrader.xcodeproj
```

Select your target device (simulator or physical iOS device), set your Team in **Signing & Capabilities**, and press `Cmd+R`.

### 4. (Optional) Connect a real data provider

Edit `DayTrader/Resources/Configuration.swift`:

```swift
static let marketDataProvider: String = "alphavantage"   // or "polygon"
static let alphaVantageAPIKey: String = "YOUR_KEY_HERE"
```

> ⚠️ Never commit real API keys. Store them in iOS Keychain (Settings screen) — Keychain integration is planned for v2.

---

## Project Structure

```
DayTrader/
├── App/                  DayTraderApp.swift, ContentView.swift
├── Models/               Quote, Stock, TradeSignal, Trade, Portfolio
├── Networking/           MarketDataService protocol, MockMarketDataService
├── Indicators/           SMA, EMA, MACD, RSI, BollingerBands, ATR, VWAP, VolumeSMA
├── Signals/              SignalEngine (confluence scoring + cooldown)
├── ViewModels/           WatchlistVM, ChartVM, SignalsVM, TradeVM
├── Views/
│   ├── Watchlist/        WatchlistView, StockRowView, AddStockView
│   ├── Chart/            ChartView (price + MACD + RSI), StockDetailView
│   ├── Signals/          SignalsView, SignalRowView, SignalFilterSheet
│   ├── Trade/            TradeView, PortfolioView, PositionRowView
│   └── Common/           TradingColors, SignalBadgeView, SettingsView
└── Resources/            Configuration.swift, Info.plist
```

---

## Roadmap

- [ ] Alpha Vantage REST integration
- [ ] Polygon.io WebSocket real-time feed
- [ ] Keychain API key storage
- [ ] Backtesting engine
- [ ] iPad split-view layout
- [ ] Live brokerage integration (Alpaca)
- [ ] Additional indicators (Stochastic, VWMA, Supertrend)

---

## Spec & Design Docs

Full product requirements and technical design live in [`.kiro/specs/daytrader-app/`](.kiro/specs/daytrader-app/).

---

## License

MIT — see [LICENSE](LICENSE)
