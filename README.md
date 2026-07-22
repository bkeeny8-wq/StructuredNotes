# Structured Notes — instrument builder (v19, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v19

- **Note / Risk / The math** output tabs with pill selector
- **Call timing distribution** (`PricingResult.callDist` / `CallBucket`) — risk-neutral path frequencies by exit time
- Expandable **glossary** of desk symbols and terms
- Continues v18 hedge sheet and prior economics dials

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
```
