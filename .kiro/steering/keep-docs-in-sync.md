---
inclusion: always
---

# Keep Docs in Sync With Code

Whenever you change behavior or logic, update the affected spec docs in the SAME
turn — do not defer it. The specs must always match the shipped code.

## Which doc to update

| Change type | Update |
|-------------|--------|
| Indicator formula, signal rule, weight, threshold, scoring math | `algorithm.md` |
| Architecture, module design, data flow, model shapes, key decisions | `design.md` |
| Feature added/removed, user-facing behavior, functional/non-functional reqs | `requirements.md` |
| Any tuned/backtested numbers, strategy performance claims | `BACKTEST-FINDINGS.md` (local, git-ignored) |

## Rules
- If a change touches logic AND docs, edit both before reporting done.
- Never state or imply a strategy is profitable. Backtesting found no reliable edge;
  signals are educational analysis only. Keep the "not financial advice" framing.
- When a default value changes (e.g. a threshold), update every doc that cites it.
- Keep the "Last updated" date at the top of algorithm.md / design.md current.
