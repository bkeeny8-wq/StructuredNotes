# Structured Notes — instrument builder (v16, always-price)

iPad SwiftUI **framework** for experienced users. Every dial is an input; the output is the note's **model value as a percentage of par**.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — models, always-price engine, builder UI |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v16

- **Call premium** (p.a.) — paid at call on top of par; nothing at maturity (unlike snowball)
- PricingResult **`premiumLeg`** in the decomposition, algebra, and coupon/premium pie slice
- Continues v14/v13: digital strike, digi-plus leverage, UF fee, daily KI bridge, event risk

## Layout

```
Sources/StructuredNotesDesk/   # framework
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
```
