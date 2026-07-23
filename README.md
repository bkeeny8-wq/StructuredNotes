# Structured Notes — instrument builder (v21, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v21

- **Vol shift** moved into the Underlying block (next to basket / ρ) — keeps market risk dials with the underliers
- Continues v20: parallel Monte Carlo, debounced reprice, mark-consistent greeks, refreshed tape marks

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
```
