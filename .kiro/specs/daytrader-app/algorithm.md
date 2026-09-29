# PulseTrader — Algorithm Reference

> Derived directly from the implementation in `DayTrader/Indicators/` and
> `DayTrader/Signals/SignalEngine.swift`. Kept in sync with code.
> Last updated: Sep 28, 2026.

This document describes exactly how every technical indicator is computed and how
the signal engine turns them into buy/sell signals. All formulas match the Swift
source so you can reason about the app's behavior without reading the code.

---

## 1. Conventions

- **Bars** are 1-minute OHLCV candles (`Quote`): open, high, low, close, volume, timestamp.
- Every indicator returns an array **aligned to the bar array** — same length, with
  leading `nil` values during the "warm-up" period before enough data exists.
- **Typical price** `TP = (high + low + close) / 3` — used by VWAP.
- All default parameters live in `Configuration.Indicators` and are user-adjustable in Settings.

---

## 2. Technical Indicators

### 2.1 SMA — Simple Moving Average
`SMACalculator`

```
SMA_t = (P_{t-n+1} + … + P_t) / n
```
- `n` = period, `P` = close price
- Warm-up: first `n-1` values are `nil`
- Implemented with a rolling window sum for O(N) performance
- Default period: 20

### 2.2 EMA — Exponential Moving Average
`EMACalculator`

```
k        = 2 / (n + 1)
EMA_seed = SMA of first n values
EMA_t    = P_t · k + EMA_{t-1} · (1 - k)
```
- Seeded with the SMA of the first `n` closes (standard practice)
- Warm-up: first `n-1` values are `nil`; index `n-1` holds the seed
- Default EMA period (overlay): 9

### 2.3 MACD — Moving Average Convergence Divergence
`MACDCalculator` (defaults 12 / 26 / 9)

```
MACD line = EMA(fast=12) − EMA(slow=26)
Signal    = EMA(9) of the MACD line
Histogram = MACD line − Signal
```
- The signal EMA is computed over the **non-nil** MACD values, then re-aligned back
  to the full bar array so indices stay consistent.

### 2.4 RSI — Relative Strength Index (Wilder smoothing)
`RSICalculator` (default period 14)

```
Initial avg gain = mean of gains over first n bars
Initial avg loss = mean of losses over first n bars

For each subsequent bar:
  avgGain = (avgGain·(n-1) + gain_t) / n      (Wilder smoothing)
  avgLoss = (avgLoss·(n-1) + loss_t) / n
  RS      = avgGain / avgLoss
  RSI     = 100 − 100 / (1 + RS)
```
- If `avgLoss == 0`, RSI is defined as 100.
- Matches TradingView / most broker platforms (Wilder's method, not simple average).
- Range 0–100. Warm-up: first `period` values are `nil`.

### 2.5 Bollinger Bands
`BollingerBandCalculator` (default period 20, 2σ)

```
Middle = SMA(20)
σ      = population standard deviation of the last 20 closes
Upper  = Middle + 2·σ
Lower  = Middle − 2·σ

Bandwidth = (Upper − Lower) / Middle
%B        = (Close − Lower) / (Upper − Lower)
```
- Uses **population** variance (divide by `n`, not `n-1`).

### 2.6 ATR — Average True Range (Wilder smoothing)
`ATRCalculator` (default period 14)

```
True Range_t = max(
    high_t − low_t,
    |high_t − close_{t-1}|,
    |low_t  − close_{t-1}|
)

Seed ATR = mean of first n true ranges
ATR_t    = (ATR_{t-1}·(n-1) + TR_t) / n
```
- ATR drives stop-loss / take-profit distances in the signal engine.

### 2.7 VWAP — Volume Weighted Average Price (session-cumulative)
`VWAPCalculator`

```
VWAP_t = Σ(TP_i · volume_i) / Σ(volume_i)   for i from session open to t
```
- Cumulative from the session open; **resets at each new trading day**.
- `TP` = typical price `(high + low + close)/3`.

### 2.8 Volume SMA
`VolumeSMACalculator` (default period 20)

- Plain SMA applied to the volume series. Used for volume-spike confirmation.

---

## 3. Signal Engine

`SignalEngine.evaluate(quotes:indicators:barIndex:)` runs on the **latest bar** every
time a new bar arrives. It scores six rules, combines them into a weighted confluence
score, and emits a `TradeSignal` only if the score clears the threshold.

### 3.1 The six rules

Each rule casts a **vote**: buy, sell, or neutral. Each has a fixed weight.

| # | Rule | Weight | Buy condition | Sell condition |
|---|------|--------|---------------|----------------|
| 1 | **RSI extreme** | 0.25 | RSI < 30 (oversold) | RSI > 70 (overbought) |
| 2 | **MACD crossover** | 0.25 | MACD line crosses **above** signal | crosses **below** signal |
| 3 | **Bollinger touch** | 0.20 | Close ≤ lower band | Close ≥ upper band |
| 4 | **EMA9 cross** | 0.15 | Close crosses **above** EMA9 | crosses **below** EMA9 |
| 5 | **VWAP cross** | 0.10 | Close crosses **above** VWAP | crosses **below** VWAP |
| 6 | **Volume** | 0.05 | (confirmation only — **never votes**, excluded from score) | — |

Notes on "crossover" rules (2, 4, 5): they compare the **previous bar** and the
**current bar** to detect a genuine cross, not just which side price is on. E.g. EMA9
buy fires only when the previous close was *below* EMA9 and the current close is *above*.

The RSI thresholds (30 / 70) and other periods are configurable in Settings.

### 3.2 Confluence score

The Volume rule is **informational only** — it never votes directionally, so it is
**excluded from the denominator** (otherwise its 0.05 weight would permanently dilute
every score). Only the five directional rules count toward `totalWeight`.

```
totalWeight = Σ (weight of directional rules)         // = 0.95 (RSI+MACD+BB+EMA9+VWAP)
buyScore    = Σ (weight of rules voting BUY)  / totalWeight
sellScore   = Σ (weight of rules voting SELL) / totalWeight
```

The **dominant direction** is whichever of buyScore / sellScore is larger.

A signal is emitted **only if**:
```
dominantScore ≥ minConfluenceScore   (default 0.45)
```
Otherwise no signal fires — the `IndicatorBreakdownView` still shows the live scores so
you can see exactly which rules did or didn't contribute.

> **History:** the original threshold was 0.60 with Volume counted in the denominator,
> which made the maximum achievable score ~0.55 → **the app produced zero signals ever.**
> Backtesting caught this. Fix: exclude Volume from the denominator (max score now 1.0)
> and lower the default threshold to 0.45. See `BACKTEST-FINDINGS.md` (local only).
>
> **The 0.45 value is a calibration to make the feature function — NOT a value that has
> been shown to be profitable.** Out-of-sample testing found no reliable edge.

### 3.3 Confidence tiers

| Tier | Score range |
|------|-------------|
| High   | ≥ 0.80 |
| Medium | 0.60 – 0.79 |
| Low    | < 0.60 (not emitted) |

High-confidence signals (≥ 0.80, configurable) trigger a local push notification.

### 3.4 Stop-loss and take-profit (ATR-based)

Using the current ATR at the signal bar:

```
BUY:
  stopLoss   = entry − ATR · 1.5
  takeProfit = entry + ATR · 3.0

SELL:
  stopLoss   = entry + ATR · 1.5
  takeProfit = entry − ATR · 3.0
```

This gives a fixed **1 : 2 risk-to-reward** ratio by construction (1.5 ATR risk vs
3.0 ATR reward). The `TradeSignal.riskReward` property recomputes the actual R:R and
returns `nil` if the stop equals entry (a malformed signal, which the engine rejects).

### 3.5 Cooldown / de-duplication

`SignalCooldownTracker` prevents signal spam:

```
A signal for (symbol, direction) will not re-fire within 5 bars
of the previous signal for that same symbol + direction.
```

Buy and sell are tracked independently — a sell can still fire during a buy's cooldown.

---

## 4. When does it run?

- **Live (market open):** Alpaca pushes a new 1-minute bar via WebSocket at each minute
  close (IEX feed on the free tier). Each new bar re-runs indicators + signal engine —
  so signals refresh roughly **once per minute** during 09:30–16:00 ET.
- **Market closed:** no new bars arrive; the last computed state is shown, no refresh.
- **Mock mode (no API key):** a simulated bar is generated every second for demo speed.

---

## 5. Parameter defaults (Configuration.swift)

| Parameter | Default | Configurable |
|-----------|---------|--------------|
| RSI period | 14 | ✅ |
| RSI oversold / overbought | 30 / 70 | ✅ |
| MACD fast / slow / signal | 12 / 26 / 9 | ✅ |
| Bollinger period / stdDev | 20 / 2.0 | ✅ |
| EMA period | 9 | ✅ |
| SMA period | 20 | ✅ |
| Volume SMA period | 20 | — |
| ATR period | 14 | — |
| Min confluence score | 0.45 | ✅ |
| Notify threshold | 0.80 | ✅ |
| ATR stop multiplier | 1.5 | — |
| ATR target multiplier | 3.0 | — |
| Cooldown bars | 5 | — |

---

## 6. Limitations of the current algorithm

- **Long-biased scoring:** the volume rule is confirmation-only (neutral vote) in v1.
- **No trend filter:** signals can fire against the prevailing trend; there is no
  higher-timeframe confirmation.
- **Crossover detection uses only 2 bars:** rapid whipsaws can produce quick opposing
  signals (mitigated partly by the 5-bar cooldown).
- **IEX feed gaps:** on the free tier, low-volume minutes may lack a bar, so a rule
  that needs the previous bar may momentarily return neutral.
- **Signals only on 1D intraday:** multi-day ranges (5D/1M/3M/1Y) display indicators
  but do not generate signals.

These are intentional v1 simplifications, not bugs. See `requirements.md` "Known
Limitations" and the v1 out-of-scope list.

---

## 7. Validation status — no demonstrated edge

This strategy was backtested on real Alpaca (IEX) data using a walk-forward
protocol: parameters tuned on an in-sample window, then validated on an unseen
time window AND an unseen set of stocks.

**Result: over-fit, no reliable edge.** Configurations that looked profitable
in-sample dropped to a loss (profit factor 0.89) on different stocks, with 30%+
drawdowns. A single recent week happened to be profitable (+5.8%/symbol), but that
tracked the tech-sector rally (market beta), not a repeatable signal.

**The signals are therefore framed in the app as educational analysis, not trade
advice, with an explicit "not financial advice" disclaimer.** Full results are in
`BACKTEST-FINDINGS.md` (git-ignored, local only).
