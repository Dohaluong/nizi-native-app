# Photo Editor — Preset Guide

Required by `docs/modules/photo-editor/ADDEDUM.md` § 14.15. Read that document first — it's the
authoritative spec for preset architecture; this is the practical "how do I actually change
something" companion to it.

**Every preset shipped today is a prototype** (`isPrototype: true` in `presets.json`), built purely
from Core Image tone adjustments — no licensed `.cube` LUT is embedded yet. Nothing here should be
mistaken for final, tuned color grading (ADDEDUM § 12: don't over-invest in prototype color).

---

## 1. Where everything lives

```text
Nizi/Features/PhotoEditor/
├── Domain/
│   ├── PresetDefinition.swift      the schema (~26 fields)
│   ├── PresetValidator.swift       pure validation rules (no crash on a bad preset)
│   └── PresetRepository.swift      protocol
├── Infrastructure/
│   ├── presets.json                the catalog itself — edit this to add/remove/retune a preset
│   ├── BundlePresetRepository.swift  loads + validates + caches presets.json
│   ├── CubeFileParser.swift        pure .cube text → RGBA Float32 buffer
│   ├── CubeLUTLoader.swift         reads a .cube from the bundle, caches the parsed result
│   ├── PhotoToneAdjuster.swift     shared exposure/contrast/highlights/shadows/warmth/saturation → Core Image
│   └── PresetRenderer.swift        base tone → LUT (if any) → blend by intensity → grain/bloom/vignette
└── Presentation/
    └── PresetStripView.swift       the horizontal thumbnail strip + intensity slider
```

`presets.json` is not compiled Swift — it's a bundle resource, loaded once and cached by
`BundlePresetRepository`. Nothing about adding/removing/retuning a preset ever touches
`PhotoEditorView`, `PresetStripView`, or `PhotoRenderEngine`.

## 2. Adding a new preset

1. Open `Nizi/Features/PhotoEditor/Infrastructure/presets.json`.
2. Copy an existing entry (pick one close to what you want — e.g. `soft` for something gentle,
   `film` for something with grain).
3. Change:
   - `id` — a new, unique lowercase-hyphenated string. This is a permanent identifier: it gets
     written into every `PhotoEditRecipe`/`CollectionEditStyle` that ever selects this preset, so
     once it ships, **never rename or reuse it** for a different preset later.
   - `name`/`shortName` — Vietnamese fallback text only (see § 6, localization).
   - `nameKey`/`shortNameKey` — new catalog keys, e.g. `photoEditor.preset.<id_with_underscores>.name`.
     Add both to `Nizi/Localizable.xcstrings` with `en` and `vi` values — **do not skip this**;
     ARCHITECTURE.md § 5 forbids any user-facing string without a catalog entry, and a preset's
     display name is exactly that, even though it comes from JSON, not a Swift literal.
   - `sortOrder` — where it appears in the strip (ascending, `Original` is always `0`).
   - `isPrototype` — `true` until this preset ships a real `.cube` (see § 3).
4. Tune the tone/texture offsets (§ 4, § 5).
5. Build and open the standalone Photo Editor preview (`Home → Diagnostics → Photo Editor →
   Standalone Preview`, DEBUG builds only) to see it in the strip and try the intensity slider.

You do **not** need to touch `PresetValidator`, `PresetRenderer`, or any Swift file to add a
preset — only `presets.json` and (if it's LUT-based) one `.cube` file.

## 3. Swapping in a real (licensed) LUT

1. Confirm the LUT is licensed for use in a commercial app and is meant for **still photos**, not
   a Log/video LUT (ADDEDUM § 3.1). Never embed a LUT of unclear license, and never download one
   from the internet as a substitute for a real license.
2. The `.cube` file must be **for stills**, in sRGB or Display P3, 3D size 17, 33, or 64 (33 is the
   safest default — see ADDEDUM § 13, Bước 3).
3. Add the file directly under `Nizi/Features/PhotoEditor/Infrastructure/` (same flat-bundle
   convention as `presets.json` and `album-layouts.json` — no `Resources/` subfolder, since this
   project's Xcode target uses a synchronized file-system group that copies everything to the
   bundle root regardless of source subfolder).
4. In `presets.json`, set that preset's `lutResource` to the file name (e.g. `"warm-memory.cube"`)
   and `lutDimension` to its declared `LUT_3D_SIZE`.
5. Set `isPrototype: false` once you've compared before/after on real photos (§ 5) and are
   satisfied — this is the "gắn nhãn rõ" bookkeeping ADDEDUM § 14.10 requires.
6. **Do not change the preset's `id`.** Every already-saved `PhotoEditRecipe` referencing this
   preset should pick up the new look automatically, not silently fall back to Original.
7. Only the LUT resource/dimension change here — never bake grain/bloom/vignette into the `.cube`
   itself (ADDEDUM § 3.2: "LUT chỉ nên chứa phần màu và tone chính").

`CubeLUTLoader` parses and caches the file the first time it's used; nothing needs to be told to
"reload" — the app process just needs a fresh launch to pick up a changed `.cube` file during
development (the cache is in-memory only, never on disk).

## 4. Adjusting default intensity

Change `defaultIntensity` (`0...1`) in `presets.json` for that preset. This is what the intensity
slider jumps to the first time a user selects that preset (§ 7.4) — it does not retroactively
change any already-saved recipe's `presetIntensity`.

`original`'s `defaultIntensity` must always stay `0` — `PresetValidator` drops the whole catalog
entry for `original` (logged, not a crash) if it's ever anything else.

## 5. Adjusting grain, bloom, and vignette

All three live in `presets.json` per-preset and are applied in `PresetRenderer.applyTexture`:

| Field | Effect | Typical range |
|---|---|---|
| `grainAmount` / `grainSize` | Desaturated noise, soft-light blended | `0` (none) to `~0.25` (visible) |
| `bloomAmount` / `bloomRadius` | `CIBloom` — soft highlight glow | `0` to `~0.1` amount, `4`–`10` radius |
| `vignetteAmount` / `vignetteRadius` | `CIVignette` — darkened corners | `0` to `~0.15` amount, `1.0`–`1.4` radius |

Texture strength does **not** fade linearly with the user's intensity slider the way color does
(ADDEDUM § 8.2) — `PresetRenderer.applyTexture` scales each one by its own coefficient:

```swift
let grainIntensity = min(preset.grainAmount * (0.4 + intensity * 0.6), preset.grainAmount)
let bloomIntensity = preset.bloomAmount * intensity
let vignetteIntensity = preset.vignetteAmount * intensity
```

So grain never fully disappears until intensity actually reaches `0` (it stays at 40% of its
amount even at very low intensity), while bloom/vignette fade linearly. Retune the JSON fields, not
this formula, unless you're deliberately changing the *shape* of the fade curve for every preset.

Grain is a Core Image `CIRandomGenerator` → desaturate → soft-light blend, not a real film-grain
algorithm — it's an honest placeholder (ADDEDUM § 12), not something to spend V1 time perfecting.

## 6. Testing a LUT

Since no `.cube` ships yet, this is written ahead of actually having one to test:

1. Add the `.cube` + JSON changes from § 3.
2. Open the standalone Photo Editor preview and select the preset — the render pipeline is the
   same one used for real photos, so this is a real end-to-end test, not a mock.
3. Compare a photo of each required test category from ADDEDUM § 13 Bước 1 (outdoor/indoor
   portrait, child, landscape, beach, greenery, sunset, night, low-light, HDR, varied skin tones,
   multiple iPhone generations) — at minimum, run through a handful of these manually before
   calling a LUT ready.
4. Compare `renderPreview` (what the editor shows live) against `renderFullResolution` (what
   export/share/save-a-copy would use) on the same photo — they should look the same; if they
   diverge, the bug is almost certainly in how the source pixels are loaded (bounded `PHImageManager`
   request vs. `requestImageDataAndOrientation`), not in `PresetRenderer` itself, since both paths
   share the exact same `applyRecipe`/`PresetRenderer` call.
5. Add/update a `BundlePresetRepositoryTests` case if the change affects catalog-level invariants
   (count, sort order, Original's intensity) — it runs against the *real* bundled `presets.json`,
   not a synthetic fixture, so it catches a broken shipped catalog directly.

## 7. Disabling a preset

Set `"isActive": false` in `presets.json`. `PresetValidator` filters it out entirely before it
reaches the repository's cached result — it will not appear in the strip, cannot be selected, and
is not logged as an error (inactive is an intentional, quiet exclusion; a genuinely malformed
preset is logged as skipped instead — see `PresetValidator.SkippedPreset`).

Do not delete an inactive preset's JSON entry if any already-saved `PhotoEditRecipe` might still
reference its `id` — `preset(id:)` returning `nil` for a saved recipe's preset id means that photo
silently renders as if it had no preset at all (falls through to Original in
`PhotoRenderEngine.applyRecipe`), which is a worse outcome for an existing user than "just
disabled, not selectable for new edits."

## 8. Color space limits

- `CIColorCubeWithColorSpace` (what applies a `.cube` LUT) is given `CGColorSpaceCreateDeviceRGB()`
  by `CubeLUTLoader` — the LUT itself must be authored for standard RGB (sRGB or Display P3), not
  a Log color space intended for video grading (ADDEDUM § 3.1's "không phải LUT Log video").
- The rest of the pipeline (`PhotoToneAdjuster`, grain/bloom/vignette) runs in whatever working
  color space `CIContext` uses by default for the source image — no explicit wide-gamut/HDR
  handling exists yet. HDR photos are out of scope for V1 (PHOTO-EDITOR.md § 17.4's RAW note
  applies here too: use whatever Photos framework already hands back, don't build custom
  colorimetry).
- If a future LUT is authored in Display P3 specifically, pass the matching `CGColorSpace` through
  `LUTCube.colorSpace` — `CubeLUTLoader` would need a small change to accept a color-space
  parameter per preset rather than always assuming device RGB. Not needed for any preset shipping
  today.
