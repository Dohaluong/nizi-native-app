# Nizi Layout Studio

An internal, browser-only tool for designing Nizi Album Page Layouts visually and exporting them
as the exact `album-layouts.json` the iOS app already understands. It is **not** part of the iOS
app's runtime or build — a completely independent web project living at `tools/layout-studio/`
inside the same repository. See `docs/specs/SPEC-LAYOUT-STUDIO.md` for the full spec this was
built from.

## Run

```bash
cd tools/layout-studio
npm install
npm run dev
```

## Build

```bash
npm run build
```

## Workflow

1. **Import App JSON** — load the current `Nizi/Features/AlbumLayout/Infrastructure/album-layouts.json`.
2. Create, duplicate, or select a layout in the Layout Library (left column), grouped by photo count.
3. Edit slot geometry on the canvas (center column) — drag to move, drag a handle to resize.
4. Set each slot's Preferred Orientation, Role, Content Mode, and Corner Radius in the Inspector
   (right column).
5. **Select Photos…** in the canvas column to preview real local photos clipped into the slots
   (nothing is ever uploaded — photos exist only as in-browser blob URLs for this tab's session).
6. **Validate** — check the Validation panel under the canvas for errors (block export) and
   warnings (don't).
7. **Export App JSON** — downloads a clean `album-layouts.json` containing only the fields the app
   understands.
8. Replace `Nizi/Features/AlbumLayout/Infrastructure/album-layouts.json` in the iOS project with
   the downloaded file.
9. Build the iOS app (`xcodebuild build` / open in Xcode) to confirm it still decodes/validates.

**The Studio never writes directly into the iOS project.** Every export is a plain file download;
you replace the resource yourself. This is deliberate — it keeps a color-grading/layout-authoring
session from ever silently corrupting the production resource mid-edit.

## Studio project vs. production export

- `album-layouts.json` — production, only fields the iOS app's `AlbumLayoutLibrary`/
  `AlbumPageLayout`/`AlbumLayoutSlot` Swift models decode.
- `nizi-layout-studio.json` (**Save/Open Studio Project**) — the Studio's own session file,
  additionally carrying per-layout notes/favorite/timestamps. Never confuse the two; the Studio
  never merges them.

The Studio also autosaves to your browser's `localStorage` ~400ms after each change, so a reload
doesn't lose in-progress work (loaded photos are the one exception — those are re-selected after
reload, since blobs are never persisted).

## Known limitations (see the completion report for the full list)

- Undo/Redo is not implemented (kept as documented future work per the spec's own § 25).
- Spread Preview (viewing two Page layouts side by side) is not implemented — deferred per § 27.
- The local-photo → slot assignment in the preview is a simple orientation-preferring heuristic,
  not a port of the real Album Planner's scoring (§ 17/§ 28 explicitly rule that out).
