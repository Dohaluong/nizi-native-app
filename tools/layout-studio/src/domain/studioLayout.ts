import type { AlbumPageLayout } from "./albumLayout";

/**
 * Studio-only metadata layered on top of a real `AlbumPageLayout` — never exported to production
 * JSON (see `services/exportLayoutLibrary.ts`, which only ever reads `.layout`). Kept as a
 * *separate* type (not extra optional fields bolted onto `AlbumPageLayout` itself) so it's
 * structurally impossible to accidentally serialize Studio metadata into `album-layouts.json` —
 * the exporter's input type doesn't even have these fields to serialize.
 */
export interface StudioLayoutMeta {
  notes: string;
  favorite: boolean;
  locked: boolean;
  createdAt: string; // ISO 8601
  updatedAt: string; // ISO 8601
}

export interface StudioLayout {
  /** A stable Studio-only identity, generated once and never changed — deliberately *not* the
   * same thing as `layout.id`. `layout.id` is user-editable production data, and the whole point
   * of a "Layout ID" text field is letting the author type a duplicate or nonsense value
   * temporarily while fixing it; every store action addresses a specific `StudioLayout` by this
   * `key` instead, so a duplicate-id state (`AlbumLayoutValidator.duplicateLayoutId`) never makes
   * selection, editing, or renaming ambiguous between the colliding entries. Without this,
   * `renameLayoutId` (or any per-layout action) matched by `layout.id` and silently applied to
   * *every* layout sharing that id at once — which is exactly why 3 layouts that already
   * collided could never be un-collided from the Inspector. */
  key: string;
  layout: AlbumPageLayout;
  meta: StudioLayoutMeta;
}

export function makeStudioMeta(): StudioLayoutMeta {
  const now = new Date().toISOString();
  return { notes: "", favorite: false, locked: false, createdAt: now, updatedAt: now };
}

export function makeStudioLayoutKey(): string {
  return crypto.randomUUID();
}

/** A whole Studio session — what autosave/"Save Studio Project" persists. Distinct from
 * `AlbumLayoutLibrary` (the production shape) on purpose (§ 23 of the spec: "Production export
 * và Studio project là hai loại file khác nhau"). */
export interface StudioProject {
  studioSchemaVersion: 1;
  layouts: StudioLayout[];
  selectedLayoutKey: string | null;
  selectedSlotId: string | null;
  snapEnabled: boolean;
}

export const STUDIO_PROJECT_FILENAME = "nizi-layout-studio.json";
export const PRODUCTION_EXPORT_FILENAME = "album-layouts.json";
