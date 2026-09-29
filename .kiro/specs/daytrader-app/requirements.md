# PulseTrader — Product Requirements

> **Last updated:** Sep 27, 2026 — reflects MVP as built and running on device.

## Introduction

PulseTrader (project codename: DayTrader) is a native iOS application for retail intra-day and short-term stock traders. It streams real-time market data via Alpaca Markets, computes technical indicators automatically, and surfaces weighted buy/sell signals so traders can focus on decisions rather than data wrangling. Paper trading is built in for risk-free practice. The app does not route live brokerage orders in v1.

---

## Problem Statement

Intra-day traders must simultaneously watch multiple stocks, compute indicators, and time entries/exits within narrow windows. Most retail tools either overwhelm with data or lack mobile-first speed and customization. PulseTrader automates indicator computation and surfaces high-confidence signals in a clean, touch-optimized interface.

---

## Target Users

| Persona | Description |
|---------|-------------|
| **Active retail day trader** | Trades 2–5 stocks per day, already understands MACD/RSI/BB, wants faster signal confirmation |
| **Semi-active swing trader** | Monitors stocks during market hours, wants alerts when setups form |
| **Beginner learning technicals** | Wants to see indicators visually and understand why a signal fired |

---

## User Stories

### Watchlist Management
- **US-01** ✅ As a trader, I want to add/remove stocks from my watchlist so I can focus only on my universe.
- **US-02** ✅ As a trader, I want to see live price, % change, and a signal badge for each stock at a glance.
- **US-03** ✅ As a trader, I want to sort my watchlist by signal strength, % change, or alphabetically.
- **US-04** ✅ As a trader, I want to search for any ticker and add it to my watchlist.

### Charting
- **US-05** ✅ As a trader, I want to see a candlestick chart with 1-min, 5-min, 15-min timeframes for intraday view.
- **US-06** ✅ As a trader, I want MACD, RSI, and Bollinger Bands overlaid on/below the chart.
- **US-07** ✅ As a trader, I want buy/sell signal markers shown directly on the chart at the bar they fired.
- **US-08** ✅ As a trader, I want to drag/scrub the chart and see indicator values for the selected bar in a tooltip.
- **US-09** ✅ As a trader, I want to switch between 1D, 5D, 1M, 3M, and 1Y chart ranges.
- **US-10** ✅ As a trader, I want the chart Y-axis to fit the visible price range, not start from zero.
- **US-11** ✅ As a trader, I want to see the current date, time, and market status (open/pre-market/after-hours) on the stock detail screen.
- **US-12** ✅ As a trader, I want the chart to only show trading-session bars (09:30–16:00 ET) so there are no overnight gaps.

### Signal Feed
- **US-13** ✅ As a trader, I want a real-time feed of all signals across my watchlist, newest first.
- **US-14** ✅ As a trader, I want each signal to show the triggering indicators, direction, confidence score, entry/stop/target prices, and R:R ratio.
- **US-15** ✅ As a trader, I want to receive a push notification when a high-confidence signal fires (≥ 80%, configurable).
- **US-16** ✅ As a trader, I want to filter the signal feed by symbol, direction (buy/sell), or confidence tier.

### Paper Trading
- **US-17** ✅ As a trader, I want to place simulated market and limit orders.
- **US-18** ✅ As a trader, I want auto-filled stop-loss and take-profit levels (ATR-based) on every order.
- **US-19** ✅ As a trader, I want to see my open positions with unrealized P&L updating in real time.
- **US-20** ✅ As a trader, I want to close a position with one tap.
- **US-21** ✅ As a trader, I want a P&L summary with win rate, profit factor, average win/loss.
- **US-22** ✅ As a trader, I want to reset my paper account to the starting balance at any time.

### Settings & Data Source
- **US-23** ✅ As a trader, I want to enter my Alpaca API key and secret directly in the app, stored securely in iOS Keychain.
- **US-24** ✅ As a trader, I want the app to automatically use Alpaca live data when keys are present, and fall back to mock data when they are not.
- **US-25** ✅ As a trader, I want to adjust indicator parameters (RSI period, BB std dev, MACD fast/slow/signal) at runtime.
- **US-26** ✅ As a trader, I want to set my own signal confluence threshold and notification threshold.

---

## Functional Requirements

### FR-01 Market Data
- FR-01.1 ✅ Fetch 1-minute OHLCV bars for watchlist symbols via Alpaca REST API (`/v2/stocks/{symbol}/bars`).
- FR-01.2 ✅ Stream real-time 1-min bars via Alpaca WebSocket (`wss://stream.data.alpaca.markets/v2/iex`).
- FR-01.3 ✅ Support multi-day ranges: 5D (15-min bars), 1M (1-hour bars), 3M and 1Y (daily bars).
- FR-01.4 ✅ Provide a fully functional mock data provider (GBM simulation) for offline/demo use.
- FR-01.5 ✅ Auto-select data provider at launch: Alpaca if Keychain has credentials, Mock otherwise.
- FR-01.6 ✅ For 1D range, automatically fetch the most recent trading day (skip weekends/holidays).
- FR-01.7 ✅ Filter all intraday bars to 09:30–16:00 ET; strip weekends from multi-day ranges.
- FR-01.8 ✅ Persist watchlist symbols to UserDefaults; API keys to iOS Keychain.
- FR-01.9 Handle `"bars": null` response from Alpaca gracefully (market closed, holiday).

### FR-02 Technical Indicators
- FR-02.1 ✅ Compute: SMA(20), EMA(9), MACD(12/26/9), RSI(14), Bollinger Bands(20, 2σ), ATR(14), Volume SMA(20), VWAP (session-cumulative).
- FR-02.2 ✅ All indicator periods configurable in Settings with sensible defaults.
- FR-02.3 ✅ All indicators return `[Double?]` arrays aligned to the bar array (leading nils for warm-up).
- FR-02.4 ✅ VWAP resets at session open (09:30 ET).

### FR-03 Signal Engine
- FR-03.1 ✅ Evaluate 6 weighted rules per bar: RSI extreme (25%), MACD crossover (25%), BB touch (20%), EMA9 cross (15%), VWAP cross (10%), volume spike (5%).
- FR-03.2 ✅ Compute weighted confluence score (0–1); emit signal when score ≥ threshold (default 0.45). Volume rule is confirmation-only and excluded from the score denominator.
- FR-03.3 ✅ Each signal includes: symbol, direction, confidence, triggering indicators, entry price, ATR-based stop-loss, ATR-based take-profit, R:R ratio.
- FR-03.4 ✅ 5-bar cooldown prevents duplicate signals for same symbol + direction.
- FR-03.5 ✅ Local push notification for signals with confidence ≥ 0.8 (configurable threshold).
- FR-03.6 ✅ Signals are presented as educational analysis, NOT trade advice. A "not financial advice" disclaimer is shown in the Signals feed and Settings (see `DisclaimerView`). Backtesting demonstrated no reliable edge — see `algorithm.md` §7.

### FR-04 Charting
- FR-04.1 ✅ Candlestick chart using Apple Swift Charts with integer index X-axis (no weekend gaps).
- FR-04.2 ✅ Intraday timeframes: 1-min, 5-min, 15-min (aggregated from 1-min raw bars).
- FR-04.3 ✅ Chart ranges: 1D, 5D, 1M, 3M, 1Y.
- FR-04.4 ✅ Price panel overlays: Bollinger Bands (dashed), EMA9 (orange), VWAP (purple).
- FR-04.5 ✅ Sub-panels: MACD (line + signal + histogram), RSI (with 30/70 reference lines).
- FR-04.6 ✅ Signal annotations: green ▲ for buy, red ▼ for sell, on price panel.
- FR-04.7 ✅ Drag/scrub gesture on price panel shows crosshair + full indicator tooltip (O/H/L/C, EMA9, VWAP, BB, MACD, RSI) for selected bar.
- FR-04.8 ✅ Dynamic Y-axis scale: fits visible price range with 5% padding; includes BB bands.
- FR-04.9 ✅ Horizontal scroll; chart scrolled to latest bar by default.
- FR-04.10 X-axis: no static labels (clutter-free); selected bar's timestamp shown in tooltip only.

### FR-05 Paper Trading
- FR-05.1 ✅ Market and Limit order types.
- FR-05.2 ✅ Position sizing: configurable max % of portfolio (default 5%).
- FR-05.3 ✅ Slippage simulation: 1 tick on market orders.
- FR-05.4 ✅ Real-time mark-to-market unrealized P&L per position.
- FR-05.5 ✅ Realized P&L, win rate, profit factor, average win/loss in Portfolio view.
- FR-05.6 ✅ Persist paper account to UserDefaults across app launches.
- FR-05.7 ✅ Reset paper account to initial capital ($100,000 default) at any time.

### FR-06 Auto-Trading (Paper, opt-in)
- FR-06.1 ✅ Off by default; user enables it in Settings.
- FR-06.2 ✅ When on, automatically opens a paper position on each qualifying BUY signal (confidence ≥ configurable threshold, default 60%).
- FR-06.3 ✅ Position sizing takes the minimum of three constraints: 1% equity risk on the stop distance, available cash, and a 10% max position size.
- FR-06.4 ✅ One open position per symbol; long-only in v1.
- FR-06.5 ✅ Automatically closes a position when its ATR stop-loss or take-profit is hit (checked on every live price update).
- FR-06.6 ✅ Maintains an activity log of auto open/close actions shown in Settings.
- FR-06.7 ✅ Simulated money only — never connected to a brokerage. Carries the same "not financial advice" framing.

### FR-07 Testing
- FR-07.1 ✅ Unit tests for all indicator calculators against known reference values (88–100% coverage).
- FR-07.2 ✅ Unit tests for the signal engine: confluence score range, Volume excluded from denominator, valid stop/target with 1:2 R:R, 5-bar cooldown.
- FR-07.3 ✅ Unit tests for position sizing (1% risk / cash / 10% cap constraints, including the over-cash and tight-stop edge cases) and portfolio P&L / win-rate / profit-factor.
- FR-07.4 ✅ Unit tests for auto-trading: auto-open on qualifying BUY, one-per-symbol, SELL ignored, auto-close on stop/target, disabled = no-op, activity logging.
- FR-07.5 ✅ Unit tests for `MarketHours` session boundaries (09:30/16:00 ET, weekends) via injectable date variants.
- FR-07.6 ⚠️ Backtest harness (`Backtester` + `BacktestTests`) requires live Alpaca data and is excluded from the core coverage run.

---

## Non-Functional Requirements

| ID | Category | Requirement | Status |
|----|----------|-------------|--------|
| NFR-01 | Performance | Indicator computation < 500 ms per symbol per bar | ✅ |
| NFR-02 | Performance | UI remains responsive during live quote updates | ✅ |
| NFR-03 | Reliability | API errors shown with retry button; graceful degradation to mock | ✅ |
| NFR-04 | Reliability | Null/empty bar responses handled without crash | ✅ |
| NFR-05 | Security | API keys in iOS Keychain only, never in source code | ✅ |
| NFR-06 | Usability | All primary actions reachable within 2 taps from watchlist | ✅ |
| NFR-07 | Accessibility | VoiceOver labels on price, signal, and chart elements | ✅ |
| NFR-08 | Compatibility | Minimum iOS 17; iPhone and iPad supported | ✅ |
| NFR-09 | Offline | Mock data provider available when no API keys configured | ✅ |
| NFR-10 | Timezone | All market-hours logic uses America/New_York (ET), DST-aware | ✅ |

---

## Known Limitations — v1

- **1D on weekends/holidays:** shows "no data" message with hint to switch to 5D (last session data visible there)
- **IEX feed only:** Alpaca free tier uses IEX exchange data, not full SIP consolidated tape — some low-volume stocks may have sparse bars
- **No holiday calendar:** weekend detection only; US market holidays (e.g. Thanksgiving) not handled
- **Signal generation on 1D only:** multi-day ranges (5D/1M/3M/1Y) display indicators but do not generate signals
- **Long-only paper trading:** short-selling UI not exposed in v1 (model supports it for schema stability)
- **No demonstrated trading edge:** walk-forward backtesting (in-sample tuning + out-of-sample validation on unseen time and unseen stocks) showed the signal strategy is over-fit with no reliable edge. Signals are shipped strictly as educational analysis with a disclaimer, never as trade recommendations.

---

## Out of Scope — v1

- Live brokerage order routing (Alpaca live trading, IBKR, etc.)
- Options, futures, or crypto instruments
- Backtesting / strategy optimization engine
- Social / copy-trading features
- Machine-learning signal models
- Multi-device sync (CloudKit / iCloud)
- Android / web versions
- US market holiday calendar
- Pre-market / after-hours data display
