# Structured Notes — instrument builder (v22, teaching build)

iPad-first SwiftUI **framework** that builds a structured note feature by feature, prices it, and explains itself. On iPhone the builder stacks above the work-through instead of squeezing into a 336pt rail.

**Local path:** `/Users/brandonkeeny/Projects/Structured Notes`  
**Remote:** https://github.com/bkeeny8-wq/StructuredNotes

## Xcode project

Open **`StructuredNotesDesk.xcodeproj`** → scheme **StructuredNotesDeskExample**.

| Target | Type |
|---|---|
| `StructuredNotesDesk` | Framework — engine, builder UI, teaching layer |
| `StructuredNotesDeskExample` | Host app (`import StructuredNotesDesk` → `DeskView()`) |

## What’s new in v22

- **You changed** explainer on every lever move (cause, measured Δ in points of par, mechanism)
- **ⓘ help** on builder/output cards; protection-observation inline explainer
- **Learn** pill — 11 guided lessons, term-sheet translation, two-register glossary
- **The math** as a numbered derivation with substituted numbers + plain English
- Risk tab: what the Greeks mean for a note; model limitations honesty card
- New `Teach.swift` (teaching copy kept apart from layout)

Also: pin-and-compare two builds, lesson progress, share the term sheet, solve coupon to par (calendar-correct Q). Issuer call uses a small Longstaff–Schwartz exercise (not autocall-at-100%). Optional local-vol leverage function (default off) so a barrier can see a smile in the paths.

Continues v21/v20: vol shift on Underlying, parallel MC, debounced reprice.

## Layout

```
Sources/StructuredNotesDesk/   # framework (incl. Teach.swift)
Example/                       # demo app + AppIcon
StructuredNotesDesk.xcodeproj
generate_xcodeproj.py          # regenerates pbxproj (stable hashed IDs)
Tests/StructuredNotesDeskTests # engine golden tests (`swift test` via Package.swift)
```
