# Architecture

## 1. System context

Nizi is split into two independent repositories/apps:

```text
nizi-web/
nizi-ios/
```

**Nizi Web** owns: accounts, Album, Album editing, sharing, server-side data, uploaded-photo management, and the mobile API.

**Nizi iOS** owns: Photos library access via PhotoKit, on-device metadata survey, event discovery, photo selection, Album Draft creation, and uploading the photos the user selects.

iOS talks to the backend only through the API — it never accesses the server database directly (see [ADR/adr-md-003](ADR/adr-md-003-ios-communicates-via-api-only.md)).

## 2. Module map (nizi-ios)

```text
Nizi Native App
│
├── Account
├── Album Management
├── Album Editor
├── Upload Manager
├── Sharing
├── Memory Discovery
│   ├── Photo Library Access
│   ├── Local Memory Index
│   ├── Event Discovery
│   ├── Photo Analysis
│   ├── Album Suggestions
│   └── Discovery UI
└── Nizi API
```

Each module under `docs/modules/` owns its own spec, architecture, and (where relevant) database/UI docs. See [modules/memory-discovery](../modules/memory-discovery/) for the first module built out this way.

Modules do not reach into each other's infrastructure. For example, Album Management must not call PhotoKit directly — when it needs a photo, it goes through the interfaces Memory Discovery exposes (see [ADR/adr-md-001](ADR/adr-md-001-memory-discovery-independent-module.md)).

## 3. Layered architecture (per module)

Every module follows the same layering, isolating Apple frameworks from application and domain logic:

```text
┌────────────────────────────────────────────┐
│ Presentation                               │
│ SwiftUI Screens, Components, ViewModels    │
├────────────────────────────────────────────┤
│ Application                                │
│ Use Cases, Coordinators, DTOs              │
├────────────────────────────────────────────┤
│ Domain                                     │
│ Entities, Rules, Scoring, Repositories     │
├────────────────────────────────────────────┤
│ Infrastructure                             │
│ PhotoKit, Persistence, Vision, Geocoding   │
├────────────────────────────────────────────┤
│ Apple Frameworks                           │
│ Photos, Vision, CoreLocation, Background   │
└────────────────────────────────────────────┘
```

Rules:

- Presentation never touches a framework or persistence API directly.
- Domain has zero framework imports (no `Photos`, `SwiftUI`, `UIKit`, `SwiftData`) so it can be unit tested off-device.
- Infrastructure is the only layer allowed to speak PhotoKit/Vision/SwiftData directly, and it's isolated behind repository/service protocols defined in Domain.

## 4. Architecture decisions

Formal architecture decision records live in [ADR/](ADR/). Product/process decisions that aren't architecture-level belong in [docs/decisions/](../decisions/) instead.

## 5. Localization

The app ships in English and Vietnamese via a native Apple String Catalog
(`Nizi/Localizable.xcstrings`, `Nizi/InfoPlist.xcstrings`). See [docs/LOCALIZATION.md](../LOCALIZATION.md)
for the key convention, pluralization pattern, and date/number formatting rules.

Guardrail: no new user-facing string literal (`Text`, `Button`, `Label`, `.navigationTitle`,
`.accessibilityLabel`, alert/dialog copy, Info.plist permission strings, etc.) may be hardcoded
directly in a view or in an Infrastructure-layer permission string. It must be added as a key to
the relevant `.xcstrings` catalog (with both `en` and `vi` entries) and referenced by key. Likewise,
no new date formatting may hardcode a fixed component pattern (e.g. `dateFormat = "d/M"`) — use
`Date.FormatStyle` or `EventDateRangeFormatter` so day/month order and separators stay
locale-aware. Debug-only screens (gated behind `#if DEBUG`, never reachable in a release build)
are exempt.
