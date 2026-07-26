# Localization

Nizi ships in English and Vietnamese via Apple's native String Catalog. There is no custom
`L10n`/`LocalizationManager` wrapper — `Text`, `Button`, `Label`, etc. take a localization key
literal directly, and Foundation resolves it against the catalog at runtime based on the
device's language setting. There is no in-app language switcher; the app follows the OS.

## Catalogs

- `Nizi/Localizable.xcstrings` — all in-app UI strings (source language: English).
- `Nizi/InfoPlist.xcstrings` — Info.plist permission strings (currently just
  `NSPhotoLibraryUsageDescription`). Xcode merges this automatically into the generated
  Info.plist because the app target uses `GENERATE_INFOPLIST_FILE = YES` with
  `INFOPLIST_KEY_*` build settings — there is no physical `Info.plist` file to localize
  per-locale `.strings`/`.lproj` files instead.
- Supported regions: `en` (development region), `vi`. Declared in the Xcode project's
  `knownRegions`.

## Key convention

Keys are namespaced `<feature>.<screen-or-component>.<meaning>`, lowercase, dot-separated:

```
onboarding.hello.title
scope.section.select_year
event.list.title
event.detail.action_bar.selected_count
common.action.retry
```

`common.*` is for generic, reused actions (Cancel, Close, Retry, Continue) — use it instead of
minting a new per-screen key for the same generic action. Everything else is scoped to the
screen/feature it belongs to, even if the English text happens to duplicate another key's text
elsewhere — screens can and do need to translate the same word differently (see the
`common.action.continue` vs. `scan.progress.action.resume` split: same Vietnamese word, "Tiếp tục",
but a different English word depending on whether the action is *starting forward* or
*resuming after a pause*).

## Static vs. interpolated strings

- **Static text** (`Text`, `Button`, `Label`, `.navigationTitle`, `Section`, `Picker`,
  `.accessibilityLabel` with no interpolation): pass the key literal directly — SwiftUI's
  `Text(_:)`/`LocalizedStringKey`-taking initializers resolve it against the catalog
  automatically. No `String(localized:)` wrapper needed.
- **Interpolated or composed text** (counts, error descriptions, anything built from a variable):
  use `String(localized: "the.key", defaultValue: "... \(value) ...")`. The key is the catalog
  lookup; `defaultValue` both seeds correct interpolation-argument substitution and is what
  renders if the key is ever missing from the catalog. Write `defaultValue` in English, matching
  the catalog's `sourceLanguage`.

## Pluralization

Counts (e.g. "N photos") go through one shared catalog key with plural variations rather than a
manual `count == 1 ? ... : ...` check in Swift:

```swift
Text(String(localized: "event.photo_count.value", defaultValue: "\(count) photos"))
```

`event.photo_count.value` has an English `plural` variation (`one`/`other`) in the catalog;
Vietnamese has no grammatical plural, so its entry is a single un-varied string. Add new plural
keys the same way — a `variations.plural` block for English, a plain `stringUnit` for Vietnamese.

## Dates and numbers

- Never hand-build a date string with a `DateFormatter().dateFormat = "..."` fixed pattern (e.g.
  `"d/M"`, `"HH:mm - d/M"`) — that bakes in one locale's day/month ordering and separators.
  Use `Date.FormatStyle` (`date.formatted(.dateTime.day().month())`, `.formatted(date:time:)`,
  etc.), which lets each locale choose its own component order and separators.
- For a start/end date **range**, use `EventDateRangeFormatter`
  (`Nizi/Core/Formatting/EventDateRangeFormatter.swift`) rather than composing one manually —
  it's the single place range-formatting logic lives, so every screen that shows a range formats
  it the same way. (Not yet consumed by a view as of this pass — see the file's own doc comment
  for why.)
- Counts shown as bare numbers (no surrounding words) should still go through
  `.formatted()` (e.g. `count.formatted()`) instead of `"\(count)"`, so large numbers pick up the
  locale's grouping separator.

## What's intentionally NOT localized (and why)

- **Debug-only screens** (`PhotoLibraryDiagnosticsView`, `LibraryIndexScanView`,
  `PhotoLibraryScanSampleView`, `EventDiscoveryDebugListView`, and anything only reachable
  through the `#if DEBUG` toolbar item in `HomeView`): never compiled into a release build, so
  never seen by a real user.
- **`DiscoveryReason.text`** (`Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryEngine.swift`):
  these are full Vietnamese sentences composed from multiple interpolated values inside pure
  Domain logic, not a static UI string. Properly localizing dynamically-composed,
  data-dependent sentences requires restructuring `DiscoveryReason` to carry structured data
  plus a `kind` and moving sentence composition into the Presentation/localized layer — a real
  domain-model change, not a UI-string swap, and out of scope for this pass.
- **`PhotoEvent.titleSuggestion`** (generated in `EventDiscoveryEngine`): same reasoning as
  above — it's a Domain-generated, already-formatted date-range string
  (`EventDiscoveryEngine.makeTitle`), not a Presentation-layer literal. Retroactively changing
  its format is a Domain change, not a string migration.
- **Brand name "Nizi"** (`HomeView`'s `.navigationTitle("Nizi")`): a proper noun, not translated.
- **`EventDiscoveryDebugListView`'s quoted historical doc title** ("Candidate list debug"): a
  literal citation of a past sprint doc's title, not a UI string.

## Adding a new user-facing string

1. Add the key to `Nizi/Localizable.xcstrings` (English + Vietnamese), following the key
   convention above.
2. Use the key directly in the view (`Text("your.key")`) for static text, or via
   `String(localized:defaultValue:)` for anything interpolated.
3. If it's a count, route it through a plural-variant key rather than manual pluralization logic.
4. If it's a date, use `Date.FormatStyle`/`EventDateRangeFormatter`, never a fixed-pattern
   `DateFormatter`.

See also the guardrail rule in `docs/architecture/ARCHITECTURE.md` § 5.
