import { create } from "zustand";
import type {
  AlbumLayoutFrame,
  AlbumLayoutSlot,
  AlbumPageFormat,
  AlbumPageLayout,
  AlbumSlotOrientation,
} from "../domain/albumLayout";
import { DEFAULT_REFERENCE_CANVAS } from "../domain/albumLayout";
import type { StudioLayout, StudioProject } from "../domain/studioLayout";
import { makeStudioMeta, STUDIO_PROJECT_FILENAME } from "../domain/studioLayout";
import { importLayoutLibrary } from "../services/importLayoutLibrary";
import { clampFrame } from "../services/normalizeGeometry";
import { validateLibrary, type ValidationIssue } from "../services/validateLayout";
import type { PreviewPhoto } from "../preview/LocalPhotoProvider";
import { revokePreviewPhotos } from "../preview/LocalPhotoProvider";

const AUTOSAVE_KEY = "nizi-layout-studio.autosave.v1";
const AUTOSAVE_DEBOUNCE_MS = 400;

function slugify(name: string): string {
  const lowered = name.toLowerCase();
  const slug = lowered.replace(/[^a-z0-9]+/g, "-").replace(/(^-+)|(-+$)/g, "");
  return slug.length > 0 ? slug : `layout-${Date.now()}`;
}

function nextUniqueId(baseId: string, existing: Set<string>): string {
  if (!existing.has(baseId)) return baseId;
  let counter = 2;
  while (existing.has(`${baseId}-${counter}`)) counter += 1;
  return `${baseId}-${counter}`;
}

function makeSlot(order: number, frame: AlbumLayoutFrame): AlbumLayoutSlot {
  return {
    id: `photo-${order + 1}`,
    order,
    role: order === 0 ? "hero" : "supporting",
    preferredOrientation: "any",
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

interface LayoutStudioState {
  layouts: StudioLayout[];
  selectedLayoutId: string | null;
  selectedSlotId: string | null;
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

  selectLayout: (id: string | null) => void;
  selectSlot: (id: string | null) => void;

  createLayout: (photoCount: number, id: string, format: AlbumPageFormat) => void;
  duplicateLayout: (id: string) => void;
  deleteLayout: (id: string) => void;
  renameLayoutId: (oldId: string, newId: string) => void;
  updateLayoutMeta: (id: string, patch: Partial<StudioLayout["meta"]>) => void;
  setLayoutFormat: (layoutId: string, format: AlbumPageFormat) => void;
  setLayoutBackgroundColor: (layoutId: string, value: string) => void;

  addSlot: (layoutId: string) => void;
  updateSlotFrame: (layoutId: string, slotId: string, frame: AlbumLayoutFrame) => void;
  updateSlot: (
    layoutId: string,
    slotId: string,
    patch: Partial<Pick<AlbumLayoutSlot, "role" | "preferredOrientation" | "contentMode" | "cornerRadius">>,
  ) => void;
  deleteSlot: (layoutId: string, slotId: string) => void;
  duplicateSlot: (layoutId: string, slotId: string) => void;
  nudgeSlot: (layoutId: string, slotId: string, dx: number, dy: number) => void;

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
      selectedLayoutId: state.selectedLayoutId,
      selectedSlotId: state.selectedSlotId,
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
  selectedLayoutId: null,
  selectedSlotId: null,
  snapEnabled: true,
  issues: [],
  importError: null,
  previewPhotos: [],

  selectedLayout: () => get().layouts.find((l) => l.layout.id === get().selectedLayoutId),

  importLibraryFromText: (rawText) => {
    const result = importLayoutLibrary(rawText);
    if (result.parseError) {
      set({ importError: result.parseError });
      return;
    }
    set({
      layouts: result.studioLayouts,
      issues: result.issues,
      importError: null,
      selectedLayoutId: result.studioLayouts[0]?.layout.id ?? null,
      selectedSlotId: null,
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
    selectedLayoutId: get().selectedLayoutId,
    selectedSlotId: get().selectedSlotId,
    snapEnabled: get().snapEnabled,
  }),

  openStudioProject: (project) => {
    set({
      layouts: project.layouts,
      selectedLayoutId: project.selectedLayoutId,
      selectedSlotId: project.selectedSlotId,
      snapEnabled: project.snapEnabled,
      issues: validateLibrary({ schemaVersion: 1, layouts: project.layouts.map((l) => l.layout) }),
      importError: null,
    });
  },

  resetStudio: () => {
    window.localStorage.removeItem(AUTOSAVE_KEY);
    revokePreviewPhotos(get().previewPhotos);
    set({
      layouts: [],
      selectedLayoutId: null,
      selectedSlotId: null,
      issues: [],
      importError: null,
      previewPhotos: [],
    });
  },

  selectLayout: (id) => set({ selectedLayoutId: id, selectedSlotId: null }),
  selectSlot: (id) => set({ selectedSlotId: id }),

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
    };
    const studioLayout: StudioLayout = { layout, meta: makeStudioMeta() };
    set((state) => ({
      layouts: [...state.layouts, studioLayout],
      selectedLayoutId: id,
      selectedSlotId: null,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  duplicateLayout: (id) => {
    const state = get();
    const source = state.layouts.find((l) => l.layout.id === id);
    if (!source) return;
    const existingIds = new Set(state.layouts.map((l) => l.layout.id));
    const newId = nextUniqueId(`${source.layout.id}-copy`, existingIds);
    const duplicated: StudioLayout = {
      layout: { ...source.layout, id: newId, name: `${source.layout.name} Copy` },
      meta: makeStudioMeta(),
    };
    set({ layouts: [...state.layouts, duplicated], selectedLayoutId: newId, selectedSlotId: null });
    get().runValidation();
    scheduleAutosave(get);
  },

  deleteLayout: (id) => {
    set((state) => {
      const layouts = state.layouts.filter((l) => l.layout.id !== id);
      const wasSelected = state.selectedLayoutId === id;
      return {
        layouts,
        selectedLayoutId: wasSelected ? null : state.selectedLayoutId,
        selectedSlotId: wasSelected ? null : state.selectedSlotId,
      };
    });
    get().runValidation();
    scheduleAutosave(get);
  },

  renameLayoutId: (oldId, newId) => {
    const trimmed = newId.trim();
    if (trimmed.length === 0) return;
    set((state) => ({
      layouts: state.layouts.map((l) => (l.layout.id === oldId ? { ...l, layout: { ...l.layout, id: trimmed } } : l)),
      selectedLayoutId: state.selectedLayoutId === oldId ? trimmed : state.selectedLayoutId,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateLayoutMeta: (id, patch) => {
    set((state) => ({
      layouts: state.layouts.map((l) =>
        l.layout.id === id ? { ...l, meta: { ...l.meta, ...patch, updatedAt: new Date().toISOString() } } : l,
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
  setLayoutFormat: (layoutId, format) => {
    set((state) => ({
      layouts: state.layouts.map((l) =>
        l.layout.id === layoutId
          ? { ...l, layout: { ...l.layout, supportedFormats: [format], referenceCanvas: DEFAULT_REFERENCE_CANVAS[format] } }
          : l,
      ),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  setLayoutBackgroundColor: (layoutId, value) => {
    set((state) => ({
      layouts: state.layouts.map((l) =>
        l.layout.id === layoutId ? { ...l, layout: { ...l.layout, background: { type: "solid", value } } } : l,
      ),
    }));
    scheduleAutosave(get);
  },

  addSlot: (layoutId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.layout.id !== layoutId) return l;
        const nextOrder = l.layout.slots.length;
        // Re-flow every existing slot's frame too, not just the new one — otherwise "Add Slot"
        // three times just stacks three full-bleed slots on top of each other, none of them
        // usable without the author manually repositioning all of them first.
        const evenWidth = l.layout.referenceCanvas.width / (nextOrder + 1);
        const reflowedSlots = l.layout.slots.map((slot, index) => ({
          ...slot,
          frame: { x: evenWidth * index, y: 0, width: evenWidth, height: l.layout.referenceCanvas.height },
        }));
        const newFrame = { x: evenWidth * nextOrder, y: 0, width: evenWidth, height: l.layout.referenceCanvas.height };
        const newSlot = makeSlot(nextOrder, newFrame);
        return { ...l, layout: withReindexedSlots(l.layout, [...reflowedSlots, newSlot]) };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateSlotFrame: (layoutId, slotId, frame) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.layout.id !== layoutId) return l;
        const clamped = clampFrame(frame, l.layout.referenceCanvas);
        return {
          ...l,
          layout: {
            ...l.layout,
            slots: l.layout.slots.map((slot) => (slot.id === slotId ? { ...slot, frame: clamped } : slot)),
          },
        };
      }),
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  updateSlot: (layoutId, slotId, patch) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.layout.id !== layoutId) return l;
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

  deleteSlot: (layoutId, slotId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.layout.id !== layoutId) return l;
        return { ...l, layout: withReindexedSlots(l.layout, l.layout.slots.filter((slot) => slot.id !== slotId)) };
      }),
      selectedSlotId: state.selectedSlotId === slotId ? null : state.selectedSlotId,
    }));
    get().runValidation();
    scheduleAutosave(get);
  },

  duplicateSlot: (layoutId, slotId) => {
    set((state) => ({
      layouts: state.layouts.map((l) => {
        if (l.layout.id !== layoutId) return l;
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

  nudgeSlot: (layoutId, slotId, dx, dy) => {
    const state = get();
    const layout = state.layouts.find((l) => l.layout.id === layoutId)?.layout;
    const slot = layout?.slots.find((s) => s.id === slotId);
    if (!layout || !slot) return;
    const step = layout.referenceCanvas.width * 0.01;
    get().updateSlotFrame(layoutId, slotId, {
      ...slot.frame,
      x: slot.frame.x + dx * step,
      y: slot.frame.y + dy * step,
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

export { slugify, STUDIO_PROJECT_FILENAME };
