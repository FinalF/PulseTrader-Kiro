# DayTrader — Product Requirements

## Introduction

DayTrader is a native iOS application designed for retail intra-day stock traders. It provides real-time market data, automated technical analysis, and actionable buy/sell signals to help traders make faster, more informed decisions within a single trading session. The app does not execute live orders in v1 — it focuses on signal quality and trade planning via paper trading.

---

## Problem Statement

Intra-day traders must simultaneously watch multiple stocks, compute indicators, and time entries/exits — all within narrow windows. Most retail tools either overwhelm with data or lack the speed and customization serious traders need. DayTrader solves this by automating indicator computation and surfacing high-confidence signals in a clean, mobile-first interface.

---

## Target Users

| Persona | Description |
|---------|-------------|
| **Active retail day trader** | Trades 2-5 stocks per day, already understands MACD/RSI/BB, wants faster signal confirmation |
| **Semi-active swing trader** | Monitors stocks during market hours, wants alerts when setups form |
| **Beginner learning technicals** | Wants to see indicators visually and understand why a signal fired |

---

## User Stories

### Watchlist Management
- **US-01** As a trader, I want to add/remove stocks from my watchlist so I can focus only on my universe.
- **US-02** As a trader, I want to see live price, % change, and a signal badge for each stock at a glance.
- **US-03** As a trader, I want to reorder my watchlist by signal strength so the hottest setups surface first.
- **US-04** As a trader, I want to search for any US-listed ticker and add it to my watchlist.

### Charting
- **US-05** As a trader, I want to see an intra-day candlestick chart (1-min, 5-min, 15-min timeframes) for any stock.
- **US-06** As a trader, I want MACD, RSI, and Bollinger Bands overlaid on/below the chart.
- **US-07** As a trader, I want buy/sell signal markers shown directly on the chart at the bar they fired.
- **US-08** As a trader, I want to pinch-zoom and scrub the chart to inspect historical bars within the session.

### Signal Feed
- **US-09** As a trader, I want a real-time feed of all signals across my watchlist, newest first.
- **US-10** As a trader, I want each signal to show the triggering indicators, direction, and a confidence score.
- **US-11** As a trader, I want to receive a push notification when a high-confidence signal fires (≥ 80%).
- **US-12** As a trader, I want to filter the signal feed by symbol, direction (buy/sell), or confidence tier.

### Paper Trading
- **US-13** As a trader, I want to place simulated market and limit orders directly from a signal.
- **US-14** As a trader, I want auto-filled stop-loss and take-profit levels (ATR-based) on every order.
- **US-15** As a trader, I want to see my open positions with unrealized P&L updating in real time.
- **US-16** As a trader, I want to close a position partially or fully with one tap.
- **US-17** As a trader, I want a daily P&L summary and equity curve for my paper account.

### Settings & Customization
- **US-18** As a trader, I want to enter my own API key for the market data provider.
- **US-19** As a trader, I want to adjust indicator parameters (e.g., RSI period, BB stdDev) globally or per symbol.
- **US-20** As a trader, I want to set my own signal confluence threshold and notification preferences.
- **US-21** As a trader, I want to reset my paper account to the starting balance at any time.

---

## Functional Requirements

### FR-01 Market Data
- FR-01.1 Fetch 1-minute OHLCV bars for all watchlist symbols during market hours (09:30–16:00 ET).
- FR-01.2 Refresh quotes at a configurable interval (default 15 s; minimum 15 s for free API tiers).
- FR-01.3 Support at least two live data providers: Alpha Vantage and Polygon.io.
- FR-01.4 Provide a fully functional mock data provider for offline development and demo use.
- FR-01.5 Cache the current session's bars in memory; persist the watchlist to disk.

### FR-02 Technical Indicators
- FR-02.1 Compute the following indicators on the bar series: SMA, EMA, MACD, RSI, Bollinger Bands, ATR, Volume SMA, VWAP.
- FR-02.2 All indicator parameters must be user-configurable with sensible defaults.
- FR-02.3 Indicators must be recomputed on every new bar arrival, within 500 ms.
- FR-02.4 Indicator values must be exposed as time-series arrays aligned to the bar array.

### FR-03 Signal Engine
- FR-03.1 Evaluate every indicator on the latest bar and assign a directional vote: bullish (+1), bearish (−1), or neutral (0).
- FR-03.2 Compute a weighted confluence score (0–1) across all votes.
- FR-03.3 Emit a `TradeSignal` when confluence ≥ threshold (default 0.6).
- FR-03.4 Each signal must include: symbol, direction, confidence score, list of triggering indicators, timestamp, suggested stop-loss price, suggested take-profit price.
- FR-03.5 Do not re-emit the same signal within 5 bars of the previous signal for the same symbol and direction.
- FR-03.6 Send a local push notification for signals with confidence ≥ 0.8 (configurable).

### FR-04 Charting
- FR-04.1 Render an intra-day candlestick chart using Apple Swift Charts.
- FR-04.2 Support 1-min, 5-min, and 15-min bar aggregation (computed from 1-min data).
- FR-04.3 Overlay Bollinger Bands, EMA, and VWAP on the price panel.
- FR-04.4 Render MACD (line + histogram) and RSI in sub-panels below the price chart.
- FR-04.5 Annotate buy signals with a green upward triangle and sell signals with a red downward triangle on the chart.
- FR-04.6 Support pinch-to-zoom and horizontal scroll within the current session window.

### FR-05 Paper Trading
- FR-05.1 Support Market and Limit order types.
- FR-05.2 Calculate position sizing based on configurable max position size (default 5% of portfolio).
- FR-05.3 Track open positions with real-time mark-to-market P&L.
- FR-05.4 Apply slippage simulation (default: 1 tick) on paper fills.
- FR-05.5 Record all trades with entry/exit prices, timestamps, quantity, and realized P&L.
- FR-05.6 Compute and display daily metrics: total P&L, win rate, average win/loss, profit factor.

---

## Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-01 | Performance | Indicator computation must complete in < 500 ms per symbol per bar |
| NFR-02 | Performance | UI must remain at 60 fps during live quote updates |
| NFR-03 | Reliability | App must handle API errors gracefully and retry with exponential back-off |
| NFR-04 | Reliability | Market data gaps (missing bars) must be flagged, not silently ignored |
| NFR-05 | Security | API keys stored in iOS Keychain, never in source code or UserDefaults |
| NFR-06 | Usability | All primary actions reachable within 2 taps from the watchlist |
| NFR-07 | Accessibility | VoiceOver labels on all price and signal elements |
| NFR-08 | Compatibility | Minimum iOS 17; iPhone and iPad layouts supported |
| NFR-09 | Offline | App launches and shows cached data when offline; disables signal generation |

---

## Out of Scope — v1

- Live brokerage order routing (IBKR, Alpaca, TD Ameritrade, etc.)
- Options, futures, or crypto instruments
- Backtesting / strategy optimization engine
- Social/copy-trading features
- Machine-learning signal models
- Multi-device sync (CloudKit / iCloud)
- Android / web versions
- Short-selling simulation in paper trading
