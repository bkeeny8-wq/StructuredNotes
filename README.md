# Structured Notes — instrument builder (v6, always-price)

iPad SwiftUI app for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**. No solving, no presets, no tabs — build the instrument, read the price, iterate the levers. The feature ledger reads in **points of par**: each row re-prices the build with one more feature, so the deltas are each feature's price directly.

## Builder blocks

| Block | Controls |
|---|---|
| Underlying | **Two add buttons — ＋ Index/ETF and ＋ Stock** — over a tape-ranked catalog: the **top 50 index/ETF underliers and top 100 single stocks** by 1H26 issuance count (150 entries, each showing its tape print count). Sourced entries (18) carry real quotes; the rest carry flagged assumption-tier vol/div ("σ est") until a feed is wired — pricing runs in ratios, so only vol/div/ρ enter the model. Decrement indices (SPXFD series) carry the decrement as their dividend. Baskets: worst-of or weighted (equal-share default, normalized sliders) · pairwise ρ |
| Tenor & final valuation | Term in **monthly increments, 1m–7y** · final valuation: close, or Asian tail averaging **the last 5 or 21 daily fixings** (daily sub-steps in the engine) |
| Coupon | None / guaranteed / contingent · **coupon rate is an input** · own observation schedule: **daily accrual** / M / Q / S / A / **European (single payment at maturity)** · barrier with **observation style: on payment date, or daily-monitored** (any breach kills that period's coupon; grid-approximated) · memory |
| Callability | None / autocall / issuer call · **own observation schedule** (M/Q/S/A) · trigger · step-down · **non-call in months (0–24)** · **snowball with its own accrual-rate input** · **lock-in (Memorizer)**: touch the lock level on an observation and par redemption locks for good |
| Upside at maturity | None / linear (optional cap) / digital / digi-plus / absolute — all levels are inputs |
| Downside at maturity | Par / buffer (plain or geared) / knock-in put · protection observation (European or monitored) · **second chance (Elite)**: a monitored knock is forgiven if the final level recovers above the second-chance level · min-redemption floor |
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
| Daily-observed coupon barrier | 97.75 | one-touch coupons cost the holder ~1.1 pts (grid-approx; true daily is larger) |
| Snowball at its own 8% / 14% rate | 92.81 / 98.65 | the accrual rate is a separate dial |
| Lock-in ≥90% (Memorizer), 100% trigger | 102.10 | one touch kills the KI while coupons keep paying — desk would re-lever |
| Second chance ≥60% (Elite) on monthly-monitored KI | 96.94 → 98.88 | recovers nearly the whole monitoring penalty — the knock pulled back toward European |

## Market snapshot

Indices ≈ Jul 20 2026 close: SPX 7,478 · NDX 28,604 · RTY 2,942 · UST 4.60%. Stocks/ETFs Jul 21 close: NVDA 207.29 · AMZN 247.55 · MSFT 397.64 (0.92% yld) · AAPL 326.59 (0.32% yld) · GOOGL 351.99 · TSLA 369.57 · AVGO 386.50 (0.68% yld) · META 643.81 · AMD 503.57 (derived from CNN's 7/21 open/prior-close) · ORCL 127.05 (1.61% yld) · QQQ 740.62 · SPY 746.74. The full catalog now includes MU, SMH, XLU, KRE, XLE, IWM and 120+ more at assumption-tier vol/div — regenerate or extend `Market.catalog` when a quote feed is available (one Asset line per name; no enum edits needed). **Single-stock vols are analyst assumptions — replace with listed implieds.** Index vols are 30-day proxies.

## Conventions and honest simplifications

Funding-rate discounting · risk-neutral GBM, 4,000 paths (1,600 ladder/ledger), fixed seed, CRN — legs are exactly additive and the printed identity ties · up to 4 assets, equal pairwise ρ via Cholesky, weighted baskets normalize weights · monitored barriers check at observation dates · the Asian tail runs 21 daily sub-steps inside the final month and averages the last 5 or 21 fixings · daily coupon accrual is approximated at the simulation grid · **issuer call is rule-based, so the holder value shown is an upper bound** (optimal LSMC exercise is worth less to the holder) · flat vol, no skew — a vol surface is the highest-impact upgrade.

## Files & Xcode

`StructuredNotesApp.swift` (iOS 17+, Charts) · `Models.swift` · `MarketData.swift` · `PricingEngine.swift` · `Components.swift` · `DeskView.swift`. New iOS App project → drop the six files in, delete `ContentView.swift`, Display Name "Structured Notes". Pair with the AppIcon deliverable.
