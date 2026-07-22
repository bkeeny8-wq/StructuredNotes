# Structured Notes — instrument builder (v5, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**. No solving, no presets, no tabs — build the instrument, read the price, iterate the levers. The feature ledger reads in **points of par**: each row re-prices the build with one more feature, so the deltas are each feature's price directly.

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## Builder blocks

| Block | Controls |
|---|---|
| Underlying | Start with one asset, **add underliers one at a time** (up to 4): SPX · NDX · RTY · NVDA · AMZN · MSFT · AAPL · GOOGL · TSLA · AVGO · QQQ · SPY. With 2+: **worst-of or weighted basket** (per-member weight sliders, normalized) · pairwise ρ |
| Tenor & final valuation | Term in **monthly increments, 1m–7y** · final valuation: close, or Asian tail averaging **the last 5 or 21 daily fixings** (daily sub-steps in the engine) |
| Coupon | None / guaranteed / contingent · **coupon rate is an input** · own observation schedule: **daily accrual** (grid-approximated) / M / Q / S / A / **European (single payment at maturity)** · barrier · memory (periodic contingent only) |
| Callability | None / autocall / issuer call · **own observation schedule** (M/Q/S/A, independent of the coupon) · trigger · step-down (−X%/yr) · **non-call in months (0–24 slider)** · **snowball** lives here: coupons accrue and pay at call |
| Upside at maturity | None / linear (optional cap) / digital / digi-plus / absolute — all levels are inputs |
| Downside at maturity | Par / buffer (plain or geared) / knock-in put · protection observation (European or monitored) · min-redemption floor |
| Economics | Funding spread · vol shift |

## The work-through (unchanged in structure)

Model value (% of par, with the implied issue-at-par embedded fee) → payoff → trader decomposition → the algebra with numbers substituted (df, Q, coupon leg = c·Q, upside = p·U, the value identity) → **feature ledger in par points** → risk block → spot ladder → desk book composed from active features.

## Validated behaviors (Python replica, index phoenix at the tape-median 11.8% coupon)

| Configuration | Value (% of par) | Read |
|---|---|---|
| Base (worst-of ×3, 3y, qtrly, 70/60, autocall 6m NC) | 98.84 | tape-median coupon prices ~1.2 rich vs a 96.9 offer on index worst-ofs |
| Weighted basket, same terms | 103.67 | above par — no issuer prints this; the correlation premium made visible |
| Monthly call obs, quarterly coupons | 98.39 | schedules are independent; more call dates → called sooner → worth less |
| Daily-accrual coupon | 99.20 | accrual credits partial periods a point-observation misses |
| European coupon (single payment at maturity, no call) | 99.11 | |
| Snowball accrual, same rate | 95.38 | deferred and conditioned — worth less at the same coupon |
| Asian tail 5 fixings / 21 fixings | 99.07 / 98.34 | two-sided: less final variance helps; a slightly lower expected average level under positive drift hurts — net small either way |
| Non-call 12m vs 6m | 99.80 | locked coupon periods add value |
| 18-month term | 101.60 | 11.8% for 1.5y at a 60% KI is rich |

## Market snapshot

Indices ≈ Jul 20 2026 close: SPX 7,478 · NDX 28,604 · RTY 2,942 · UST 4.60%. Stocks/ETFs Jul 21 close: NVDA 207.29 · AMZN 247.55 · MSFT 397.64 (0.92% yld) · AAPL 326.59 (0.32% yld) · GOOGL 351.99 · TSLA 369.57 · AVGO 386.50 (0.68% yld) · QQQ 740.62 · SPY 746.74. **Single-stock vols are analyst assumptions — replace with listed implieds.** Index vols are 30-day proxies.

## Conventions and honest simplifications

Funding-rate discounting · risk-neutral GBM, 4,000 paths (1,600 ladder/ledger), fixed seed, CRN — legs are exactly additive and the printed identity ties · up to 4 assets, equal pairwise ρ via Cholesky, weighted baskets normalize weights · monitored barriers check at observation dates · the Asian tail runs 21 daily sub-steps inside the final month and averages the last 5 or 21 fixings · daily coupon accrual is approximated at the simulation grid · **issuer call is rule-based, so the holder value shown is an upper bound** (optimal LSMC exercise is worth less to the holder) · flat vol, no skew — a vol surface is the highest-impact upgrade.

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
```
