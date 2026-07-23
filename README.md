# Structured Notes — instrument builder (v20, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v20

- **Parallel Monte Carlo** — path chunks via `DispatchQueue.concurrentPerform`
- **Debounced reprice** — cancels in-flight work and coalesces slider/curve ticks (~120ms)
- Greeks take the headline **full-path mark** so level and diffs stay consistent; ladder/event deltas use one-sided bumps
- Refreshed market snapshot (UST pillars, SPX/NDX/QQQ/NVDA as-of ~Jul 22–23 2026)

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
```
