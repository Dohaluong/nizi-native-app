import { create } from "zustand";
import type {
  AlbumLayoutFrame,
  AlbumLayoutSlot,
  AlbumPageFormat,
  AlbumPageLayout,
  AlbumSlotOrientation,
  AlbumTextBlock,
} from "../domain/albumLayout";
import { DEFAULT_REFERENCE_CANVAS } from "../domain/albumLayout";
import type { StudioLayout, StudioProject } from "../domain/studioLayout";
import { makeStudioLayoutKey, makeStudioMeta, STUDIO_PROJECT_FILENAME } from "../domain/studioLayout";
import { importLayoutLibrary } from "../services/importLayoutLibrary";
import { classifyOrientationFromSize } from "../services/classifyOrientation";
import { clampFrame } from "../services/normalizeGeometry";
import { validateLibrary, type ValidationIssue } from "../services/validateLayout";
import type { PreviewPhoto } from "../preview/LocalPhotoProvider";
import { revokePreviewPhotos } from "../preview/LocalPhotoProvider";

const AUTOSAVE_KEY = "nizi-layout-studio.autosave.v1";
const AUTOSAVE_DEBOUNCE_MS = 400;

function slugify(name: string): string {
  const lowered = name.toLowerCase();
  const slug = lowered.replace(/[^a-z0-9]+/g, "-").replace(/(^-+)|(-+$)/g, "");
  return slug.length > 0 ? slug : "layout";
}

/** § user request: "Mỗi khi clone hoặc thêm layout mới thì tự động sinh tên để không trùng" —
 * every id-collision path (New Layout with a blank/repeated variant name, Duplicate Layout,
 * Duplicate Slot) goes through this, never a raw timestamp suffix: `"square.1.untitled"`,
 * `"square.1.untitled-2"`, `"square.1.untitled-3"`, … — short, predictable, and still easy to
 * rename by hand later. */
function nextUniqueId(baseId: string, existing: Set<string>): string {
  if (!existing.has(baseId)) return baseId;
  let counter = 2;
  while (existing.has(`${baseId}-${counter}`)) counter += 1;
  return `${baseId}-${counter}`;
}

/** `"any"` is the one `AlbumSlotOrientation` value a rectangle's own shape can never imply — it's
 * a deliberate "accept whatever photo you're given" choice, not a geometry fact — so it's treated
 * as a sticky manual override here: once a slot is explicitly set to `"any"`, further frame
 * changes leave it alone. Every other value (`landscape`/`portrait`/`square`) always stays in
 * sync with the slot's actual current shape. */
function nextOrientation(current: AlbumSlotOrientation, width: number, height: number): AlbumSlotOrientation {
  return current === "any" ? "any" : classifyOrientationFromSize(width, height);
}

function makeSlot(order: number, frame: AlbumLayoutFrame): AlbumLayoutSlot {
  return {
    id: `photo-${order + 1}`,
    order,
    role: order === 0 ? "hero" : "supporting",
    preferredOrientation: classifyOrientationFromSize(frame.width, frame.height),
    frame,
    contentMode: "fill",
    cornerRadius: 0,
  };
}

/** Keeps `order` equal to array position and `photoCount` equal to `slots.length` at all times —
 * every mutation that touches `slots` funnels through this so those two invariants (both real
 * `AlbumLayoutValidator` rules) can never silently drift apart. */
function withReindexedSlots(layout: AlbumPageLayout, slots: AlbumLayoutSlot[]): AlbumPageLayout {
  const reindexed = slots.map((slot, index) => ({ ...slot, order: index }));
  return { ...layout, slots: reindexed, photoCount: reindexed.length };
}

/** Same idea as `withReindexedSlots`, minus `photoCount` — a layout's text blocks are a separate,
 * decorative collection never counted toward it (§ user request "Thêm chữ"). */
function withReindexedTextBlocks(layout: AlbumPageLayout, textBlocks: AlbumTextBlock[]): AlbumPageLayout {
  const reindexed = textBlocks.map((textBlock, index) => ({ ...textBlock, order: index }));
  return { ...layout, textBlocks: reindexed };
}

function makeTextBlock(order: number, frame: AlbumLayoutFrame): AlbumTextBlock {
  return {
    id: `text-${order + 1}`,
    order,
    frame,
    horizontalAlignment: "center",
    verticalAlignment: "center",
    fontFamily: "System",
    fontSize: 48,
    fontStyle: "regular",
  };
}

/** A `StudioProject` saved before `StudioLayout.key` existed (or hand-edited) won't have one —
 * generate a fresh key for anything missing it rather than fail to load. */
function ensureKeys(layouts: StudioLayout[]): StudioLayout[] {
  return layouts.map((l) => (l.key ? l : { ...l, key: makeStudioLayoutKey() }));
}

interface LayoutStudioState {
  layouts: StudioLayout[];
  /** Addresses a specific `StudioLayout` by its stable Studio-only `key`, never by `layout.id` —
   * see the doc comment on `StudioLayout.key` for why: `layout.id` can (temporarily, invalidly)
   * collide between entries, and every action below needs to unambiguously target exactly one. */
  selectedLayoutKey: string | null;
  selectedSlotId: string | null;
  /** Mutually exclusive with `selectedSlotId` (selecting one clears the other) — a simpler,
   * lower-risk addition than generalizing both into one "selected element" concept, at the cost of
   * every selection-driven action (`selectSlot`/`selectTextBlock`, the Inspector switch in
   * `App.tsx`, the canvas keyboard handler) needing its own explicit check of which one is set. */
  selectedTextBlockId: string | null;
  snapEnabled: boolean;
  issues: ValidationIssue[];
  importError: string | null;
  previewPhotos: PreviewPhoto[];

  selectedLayout: () => StudioLayout | undefined;

  importLibraryFromText: (rawText: string) => void;
  loadAutosaveIfAny: () => void;
  saveStudioProject: () => StudioProject;
  openStudioProject: (project: StudioProject) => void;
  resetStudio: () => void;

  selectLayout: (key: string | null) => void;
  selectSlot: (id: string | null) => void;
  selectTextBlock: (id: string | null) => void;

  createLayout: (photoCount: number, id: string, format: AlbumPageFormat) => void;
  duplicateLayout: (key: string) => void;
  deleteLayout: (key: string) => void;
  renameLayoutId: (key: string, newId: string) => void;
  updateLayoutMeta: (key: string, patch: Partial<StudioLayout["meta"]>) => void;
  setLayoutFormat: (key: string, format: AlbumPageFormat) => void;
  setLayoutBackgroundColor: (key: string, value: string) => void;

  addSlot: (key: string) => void;
  updateSlotFrame: (key: string, slotId: string, frame: AlbumLayoutFrame) => void;
  updateSlot: (
    key: string,
    slotId: string,
    patch: Partial<Pick<AlbumLayoutSlot, "role" | "preferredOrientation" | "contentMode" | "cornerRadius">>,
  ) => void;
  deleteSlot: (key: string, slotId: string) => void;
  duplicateSlot: (key: string, slotId: string) => void;
  nudgeSlot: (key: string, slotId: string, dx: number, dy: number) => void;

  addTextBlock: (key: string) => void;
  updateTextBlockFrame: (key: string, textBlockId: string, frame: AlbumLayoutFrame) => void;
  updateTextBlock: (
    key: string,
    textBlockId: string,
    patch: Partial<Pick<AlbumTextBlock, "horizontalAlignment" | "verticalAlignment" | "fontFamily" | "fontSize" | "fontStyle">>,
  ) => void;
  deleteTextBlock: (key: string, textBlockId: string) => void;
  duplicateTextBlock: (key: string, textBlockId: string) => void;
  nudgeTextBlock: (key: string, textBlockId: string, dx: number, dy: number) => void;

  toggleSnap: () => void;
  runValidation: () => void;

  setPreviewPhotos: (photos: PreviewPhoto[]) => void;
  clearPreviewPhotos: () => void;
  shufflePreview: () => void;
}

function scheduleAutosave(get: () => LayoutStudioState): void {
  if (autosaveTimer !== undefined) window.clearTimeout(autosaveTimer);
  autosaveTimer = window.setTimeout(() => {
    const state = get();
    const project: StudioProject = {
      studioSchemaVersion: 1,
      layouts: state.layouts,
      selectedLayoutKey: state.selectedLayoutKey,
      selectedSlotId: state.selectedSlotId,
      selectedTextBlockId: state.selectedTextBlockId,
      snapEnabled: state.snapEnabled,
    };
    try {
      window.localStorage.setItem(AUTOSAVE_KEY, JSON.stringify(project));
    } catch {
      // Autosave is best-effort (e.g. private browsing can throw on setItem) — never surfaced
      // as a user-facing error, since nothing was actually lost (state is still in memory).
    }
  }, AUTOSAVE_DEBOUNCE_MS);
}

let autosaveTimer: number | undefined;

export const useLayoutStudioStore = create<LayoutStudioState>((set, get) => ({
  layouts: [],
  selectedLayoutKey: null,
  selectedSlotId: null,
  selectedTextBlockId: null,
  snapEnabled: true,
  issues: [],
  importError: null,
  previewPhotos: [],

  selectedLayout: () => get().layouts.find((l) => l.key === get().selectedLayoutKey),

  /** Merges into whatever's already in the Studio — never a blind replace. A layout id already
   * present in the file being imported is refreshed from that file (the file is the source of
   * truth for anything it actually contains) but keeps its existing Studio `key`/`meta` if one
   * already existed for that id (so selection and notes/favorite survive a re-import). Any layout
   * that only exists in the Studio so far (newly created, not yet part of the imported file) is
   * kept untouched. Without this, importing the current production `album-layouts.json` *after*
   * creating a new layout in the Studio would silently wipe that new layout back out — exactly
   * the "chỉ thêm chứ không xoá cái cũ" case this exists to prevent, in both directions. */
  importLibraryFromText: (rawText) => {
    const result = importLayoutLibrary(rawText);
    if (result.parseError) {
      set({ importError: result.parseError });
      return;
    }

    const state = get();
    const existingById = new Map(state.layouts.map((l) => [l.layout.id, l]));
    const merged: StudioLayout[] = [];
    const importedIds = new Set<string>();

    for (const incoming of result.studioLayouts) {
      const existingMatch = existingById.get(incoming.layout.id);
      merged.push({
        key: existingMatch?.key ?? incoming.key,
        layout: incoming.layout,
        meta: existingMatch?.meta ?? incoming.meta,
      });
      importedIds.add(incoming.layout.id);
    }
    for (const existingLayout of state.layouts) {
      if (!importedIds.has(existingLayout.layout.id)) merged.push(existingLayout);
    }

    const keepsCurrentSelection = state.selectedLayoutKey !== null && merged.some((l) => l.key === state.selectedLayoutKey);
    set({
      layouts: merged,
      issues: validateLibrary({ schemaVersion: 1, layouts: merged.map((l) => l.layout) }),
      importError: null,
      selectedLayoutKey: keepsCurrentSelection ? state.selectedLayoutKey : merged[0]?.key ?? null,
      selectedSlotId: keepsCurrentSelection ? state.selectedSlotId : null,
      selectedTextBlockId: keepsCurrentSelection ? state.selectedTextBlockId : null,
    });
    scheduleAutosave(get);
  },

  loadAutosaveIfAny: () => {
    const raw = window.localStorage.getItem(AUTOSAVE_KEY);
    if (!raw) return;
    try {
      const project = JSON.parse(raw) as StudioProject;
      get().openStudioProject(project);
    } catch {
      // A corrupted autosave entry must never crash the app on load (§ 24 implies restoring
      // should degrade gracefully) — just start from an empty Studio instead.
    }
  },

  saveStudioProject: () => ({
    studioSchemaVersion: 1,
    layouts: get().layouts,
    selectedLayoutKey: get().selectedLayoutKey,
    selectedSlotId: get().selectedSlotId,
    selectedTextBlockId: get().selectedTextBlockId,
    snapEnabled: get().snapEnabled,
  }),

  openStudioProject: (project) => {
    const layouts = ensureKeys(project.layouts);
    set({
      layouts,
      selectedLayoutKey: project.selectedLayoutKey,
      selectedSlotId: project.selectedSlotId,
      selectedTextBlockId: project.selectedTextBlockId,
      snapEnabled: project.snapEnabled,
      issues: validateLibrary({ schemaVersion: 1, layouts: layouts.map((l) => l.layout) }),
      importError: null,
    });
  },

  resetStudio: () => {
    window.localStorage.removeItem(AUTOSAVE_KEY);
    revokePreviewPhotos(get().previewPhotos);
    set({
      layouts: [],
      selectedLayoutKey: null,
      selectedSlotId: null,
      selectedTextBlockId: null,
      issues: [],
      importError: null,
      previewPhotos: [],
    });
  },

  selectLayout: (key) => set({ selectedLayoutKey: key, selectedSlotId: null, selectedTextBlockId: null }),
  selectSlot: (id) => set({ selectedSlotId: id, selectedTextBlockId: null }),
  selectTextBlock: (id) => set({ selectedTextBlockId: id, selectedSlotId: null }),

  createLayout: (photoCount, id, format) => {
    const canvas = DEFAULT_REFERENCE_CANVAS[format];
    // § 10 — "Create default slots" isn't mandatory MVP, but starting from `photoCount` empty
    // slots (an even horizontal split, same starting shape `addSlot` reflows to) means a
    // brand-new layout is immediately valid/exportable rather than sitting on an
    // `invalidPhotoCount` error (0 slots) until the author manually adds exactly `photoCount` of
    // them one at a time.
    const evenWidth = canvas.width / photoCount;
    const slots = Array.from({ length: photoCount }, (_, index) =>
      makeSlot(index, { x: evenWidth * index, y: 0, width: evenWidth, height: canvas.height }),
    );
    const layout: AlbumPageLayout = {
      id,
      name: id,
      nameKey: `album.layout.${id.replace(/\./g, "_")}`,
      photoCount,
      supportedFormats: [format],
      referenceCanvas: canvas,
      background: { type: "solid", value: "#FFFFFF" },
      slots,
      textBlocks: [],
    };
    const studioLayout: StudioLayout = { key: makeStudioLayoutKey(), layout, meta: makeStudioMeta() };
    set((state) => ({
      layouts: [...state.layouts, studioLayout],
      selectedLayoutKey: studioLayout.key,
      selectedSlotId: null,
      selectedTextBlockId: null,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  duplicateLayout: (key) => {
    const state = get();
    const source = state.layouts.find((l) => l.key === key);
    if (!source) return;
    const existingIds = new Set(state.layouts.map((l) => l.layout.id));
    const newId = nextUniqueId(`${source.layout.id}-copy`, existingIds);
    const duplicated: StudioLayout = {
      key: makeStudioLayoutKey(),
      layout: { ...source.layout, id: newId, name: `${source.layout.name} Copy` },
      meta: makeStudioMeta(),
    };
    set({ layouts: [...state.layouts, duplicated], selectedLayoutKey: duplicated.key, selectedSlotId: null, selectedTextBlockId: null });
    get().runValidation();
    scheduleAutosave(get);
  },

  deleteLayout: (key) => {
    set((state) => {
      const layouts = state.layouts.filter((l) => l.key !== key);
      const wasSelected = state.selectedLayoutKey === key;
      return {
        layouts,
        selectedLayoutKey: wasSelected ? null : state.selectedLayoutKey,
        selectedSlotId: wasSelected ? null : state.selectedSlotId,
        selectedTextBlockId: wasSelected ? null : state.selectedTextBlockId,
      };
    });
    get().runValidation();
    scheduleAutosave(get);
  },

  renameLayoutId: (key, newId) => {
    const trimmed = newId.trim();
    if (trimmed.length === 0) return;
    set((state) => ({
      layouts: state.layouts.map((l) => (l.key === key ? { ...l, layout: { ...l.layout, id: trimmed } } : l)),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateLayoutMeta: (key, patch) => {
    set((state) => ({
      layouts: state.layouts.map((l) =>
        l.key === key ? { ...l, meta: { ...l.meta, ...patch, updatedAt: new Date().toISOString() } } : l,
      ),
    }));
    scheduleAutosave(get);
  },

  /** A layout's `referenceCanvas` and `supportedFormats` can never disagree — every real layout
   * ships with exactly one format whose aspect ratio the canvas actually matches
   * (`AlbumLayoutValidator.aspectRatio(of:matches:)`); nothing in the app schema or the real data
   * supports one canvas serving two different aspect-ratio families at once. So this is a
   * single-choice switch, not independent checkboxes — picking a format also resets
   * `referenceCanvas` to that format's own default size (`DEFAULT_REFERENCE_CANVAS`), which is
   * also the only way to *fix* a layout that's already in a mismatched state (e.g. imported, or
   * hand-edited via JSON) rather than leaving the author stuck looking at an error with no
   * control that resolves it.
   */
  setLayoutFormat: (key, format) => {
    set((state) => ({
      layouts: state.layouts.map((l) =>
        l.key === key
          ? { ...l, layout: { ...l.layout, supportedFormats: [format], referenceCanvas: DEFAULT_REFERENCE_CANVAS[format] } }
          : l,
      ),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  setLayoutBackgroundColor: (key, value) => {
    set((state) => ({
      layouts: state.layouts.map((l) => (l.key === key ? { ...l, layout: { ...l.layout, background: { type: "solid", value } } } : l)),
    }));
    scheduleAutosave(get);
  },

  addSlot: (key) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const nextOrder = l.layout.slots.length;
        // Re-flow every existing slot's frame too, not just the new one — otherwise "Add Slot"
        // three times just stacks three full-bleed slots on top of each other, none of them
        // usable without the author manually repositioning all of them first.
        const evenWidth = l.layout.referenceCanvas.width / (nextOrder + 1);
        const reflowedSlots = l.layout.slots.map((slot, index) => {
          const frame = { x: evenWidth * index, y: 0, width: evenWidth, height: l.layout.referenceCanvas.height };
          return { ...slot, frame, preferredOrientation: nextOrientation(slot.preferredOrientation, frame.width, frame.height) };
        });
        const newFrame = { x: evenWidth * nextOrder, y: 0, width: evenWidth, height: l.layout.referenceCanvas.height };
        const newSlot = makeSlot(nextOrder, newFrame);
        return { ...l, layout: withReindexedSlots(l.layout, [...reflowedSlots, newSlot]) };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  // § user request: "Preferred Orientation cần tự nhận diện theo kích thước RECT" — every frame
  // change (drag, resize, or a manual X/Y/W/H edit in the Inspector all funnel through this one
  // action) re-derives `preferredOrientation` from the new width/height via `nextOrientation`, so
  // it's never a separate, driftable field the author has to remember to update by hand after
  // reshaping a slot (except a deliberate `"any"`, which stays put — see `nextOrientation`).
  updateSlotFrame: (key, slotId, frame) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const clamped = clampFrame(frame, l.layout.referenceCanvas);
        return {
          ...l,
          layout: {
            ...l.layout,
            slots: l.layout.slots.map((slot) =>
              slot.id === slotId
                ? { ...slot, frame: clamped, preferredOrientation: nextOrientation(slot.preferredOrientation, clamped.width, clamped.height) }
                : slot,
            ),
          },
        };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateSlot: (key, slotId, patch) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        return {
          ...l,
          layout: {
            ...l.layout,
            slots: l.layout.slots.map((slot) => (slot.id === slotId ? { ...slot, ...patch } : slot)),
          },
        };
      }),
    }));
    scheduleAutosave(get);
  },

  deleteSlot: (key, slotId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        return { ...l, layout: withReindexedSlots(l.layout, l.layout.slots.filter((slot) => slot.id !== slotId)) };
      }),
      selectedSlotId: state.selectedSlotId === slotId ? null : state.selectedSlotId,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  duplicateSlot: (key, slotId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const source = l.layout.slots.find((slot) => slot.id === slotId);
        if (!source) return l;
        const existingIds = new Set(l.layout.slots.map((slot) => slot.id));
        const newId = nextUniqueId(`${source.id}-copy`, existingIds);
        const offset = l.layout.referenceCanvas.width * 0.03;
        const duplicated: AlbumLayoutSlot = {
          ...source,
          id: newId,
          frame: clampFrame(
            { ...source.frame, x: source.frame.x + offset, y: source.frame.y + offset },
            l.layout.referenceCanvas,
          ),
        };
        return { ...l, layout: withReindexedSlots(l.layout, [...l.layout.slots, duplicated]) };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  nudgeSlot: (key, slotId, dx, dy) => {
    const state = get();
    const layout = state.layouts.find((l) => l.key === key)?.layout;
    const slot = layout?.slots.find((s) => s.id === slotId);
    if (!layout || !slot) return;
    const step = layout.referenceCanvas.width * 0.01;
    get().updateSlotFrame(key, slotId, {
      ...slot.frame,
      x: slot.frame.x + dx * step,
      y: slot.frame.y + dy * step,
    });
  },

  // § user request "Thêm chữ" — mirrors addSlot/updateSlotFrame/updateSlot/deleteSlot/
  // duplicateSlot/nudgeSlot exactly, minus anything that only makes sense for photo slots
  // (contentMode/role/preferredOrientation/photoCount reflow).
  addTextBlock: (key) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const canvas = l.layout.referenceCanvas;
        // A sensible default size/position — a wide band across the middle third of the page,
        // not full-bleed (unlike a first photo slot, a text block overlapping the whole canvas by
        // default would almost always need immediate resizing to be useful).
        const frame = { x: canvas.width * 0.1, y: canvas.height * 0.4, width: canvas.width * 0.8, height: canvas.height * 0.2 };
        const newBlock = makeTextBlock(l.layout.textBlocks.length, frame);
        return { ...l, layout: withReindexedTextBlocks(l.layout, [...l.layout.textBlocks, newBlock]) };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateTextBlockFrame: (key, textBlockId, frame) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const clamped = clampFrame(frame, l.layout.referenceCanvas);
        return {
          ...l,
          layout: {
            ...l.layout,
            textBlocks: l.layout.textBlocks.map((textBlock) => (textBlock.id === textBlockId ? { ...textBlock, frame: clamped } : textBlock)),
          },
        };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateTextBlock: (key, textBlockId, patch) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        return {
          ...l,
          layout: {
            ...l.layout,
            textBlocks: l.layout.textBlocks.map((textBlock) => (textBlock.id === textBlockId ? { ...textBlock, ...patch } : textBlock)),
          },
        };
      }),
    }));
    scheduleAutosave(get);
  },

  deleteTextBlock: (key, textBlockId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        return { ...l, layout: withReindexedTextBlocks(l.layout, l.layout.textBlocks.filter((textBlock) => textBlock.id !== textBlockId)) };
      }),
      selectedTextBlockId: state.selectedTextBlockId === textBlockId ? null : state.selectedTextBlockId,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  duplicateTextBlock: (key, textBlockId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.key !== key) return l;
        const source = l.layout.textBlocks.find((textBlock) => textBlock.id === textBlockId);
        if (!source) return l;
        const existingIds = new Set(l.layout.textBlocks.map((textBlock) => textBlock.id));
        const newId = nextUniqueId(`${source.id}-copy`, existingIds);
        const offset = l.layout.referenceCanvas.width * 0.03;
        const duplicated: AlbumTextBlock = {
          ...source,
          id: newId,
          frame: clampFrame(
            { ...source.frame, x: source.frame.x + offset, y: source.frame.y + offset },
            l.layout.referenceCanvas,
          ),
        };
        return { ...l, layout: withReindexedTextBlocks(l.layout, [...l.layout.textBlocks, duplicated]) };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  nudgeTextBlock: (key, textBlockId, dx, dy) => {
    const state = get();
    const layout = state.layouts.find((l) => l.key === key)?.layout;
    const textBlock = layout?.textBlocks.find((t) => t.id === textBlockId);
    if (!layout || !textBlock) return;
    const step = layout.referenceCanvas.width * 0.01;
    get().updateTextBlockFrame(key, textBlockId, {
      ...textBlock.frame,
      x: textBlock.frame.x + dx * step,
      y: textBlock.frame.y + dy * step,
    });
  },

  toggleSnap: () => {
    set((state) => ({ snapEnabled: !state.snapEnabled }));
    scheduleAutosave(get);
  },

  runValidation: () => {
    const state = get();
    set({ issues: validateLibrary({ schemaVersion: 1, layouts: state.layouts.map((l) => l.layout) }) });
  },

  setPreviewPhotos: (photos) => {
    revokePreviewPhotos(get().previewPhotos);
    set({ previewPhotos: photos });
  },

  clearPreviewPhotos: () => {
    revokePreviewPhotos(get().previewPhotos);
    set({ previewPhotos: [] });
  },

  shufflePreview: () => {
    set((state) => ({ previewPhotos: [...state.previewPhotos].sort(() => Math.random() - 0.5) }));
  },
}));

export function slotOrientationOptions(): AlbumSlotOrientation[] {
  return ["landscape", "portrait", "square", "any"];
}

export { slugify, nextUniqueId, STUDIO_PROJECT_FILENAME };
