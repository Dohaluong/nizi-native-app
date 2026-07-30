import { albumLayoutLibrarySchema } from "../domain/schemas";
import type { AlbumLayoutLibrary } from "../domain/albumLayout";
import { makeStudioLayoutKey, makeStudioMeta, type StudioLayout } from "../domain/studioLayout";
import { validateLibrary, type ValidationIssue } from "./validateLayout";

export interface ImportResult {
  studioLayouts: StudioLayout[];
  /** Zod structural errors, if the file wasn't even shaped like `AlbumLayoutLibrary`. Present
   * only when import failed outright (§ 19: "không crash; hiển thị lỗi"). */
  parseError?: string;
  /** Semantic validation issues (errors/warnings) found in an otherwise well-shaped file — the
   * file is still imported (so the author can *fix* the problem in the Studio), matching § 19's
   * "chỉ rõ field/layout lỗi nếu có thể" rather than refusing the import outright. */
  issues: ValidationIssue[];
}

/** File → JSON.parse → Zod → semantic validation, exactly the first half of the flow in § 19.
 * Preserves layout IDs, slot IDs, order, orientation, and geometry verbatim — nothing here
 * rewrites a single field, only wraps each `AlbumPageLayout` in a fresh `StudioLayoutMeta`.
 *
 * This only parses *this one file* in isolation — it doesn't know about (and can't merge with)
 * whatever's already in the Studio. That merge (keep any Studio-only layout this file doesn't
 * mention, refresh anything it does) happens one layer up, in `store/layoutStudioStore.ts`'s
 * `importLibraryFromText`, specifically so importing the production JSON can never silently
 * delete a layout you've already started building in the Studio. */
export function importLayoutLibrary(rawText: string): ImportResult {
  let json: unknown;
  try {
    json = JSON.parse(rawText);
  } catch (error) {
    return { studioLayouts: [], parseError: `Invalid JSON: ${(error as Error).message}`, issues: [] };
  }

  const parsed = albumLayoutLibrarySchema.safeParse(json);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0];
    const path = firstIssue ? firstIssue.path.join(".") : "";
    const detail = firstIssue ? `${path ? `${path}: ` : ""}${firstIssue.message}` : "unknown error";
    return {
      studioLayouts: [],
      parseError: `File doesn't match the app's AlbumLayoutLibrary schema (${detail}).`,
      issues: [],
    };
  }

  const library = parsed.data as AlbumLayoutLibrary;
  const issues = validateLibrary(library);
  const studioLayouts: StudioLayout[] = library.layouts.map((layout) => ({
    key: makeStudioLayoutKey(),
    layout,
    meta: makeStudioMeta(),
  }));

  return { studioLayouts, issues };
}
