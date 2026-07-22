# Structured Notes — instrument builder (v13, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v13

- **Underwriting fee (UF)** dial — advisor + wholesaler; dealer offer stack shows issuer net proceeds and structuring margin vs offer
- **Daily KI monitoring** via Brownian bridge (`ProtectionObs.daily`)
- **Event risk** card — value/delta tabs around the first call observation and near-maturity KI cliff
- Desk book split into **exposure** vs **hedging the market risk**

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
```
