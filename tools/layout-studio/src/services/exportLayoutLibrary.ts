import type { AlbumLayoutLibrary, AlbumPageLayout } from "../domain/albumLayout";
import { SUPPORTED_SCHEMA_VERSION } from "../domain/albumLayout";
import type { StudioLayout } from "../domain/studioLayout";
import { albumLayoutLibrarySchema } from "../domain/schemas";
import { roundFrame } from "./normalizeGeometry";
import { hasErrors, validateLibrary, type ValidationIssue } from "./validateLayout";

export interface ExportResult {
  library?: AlbumLayoutLibrary;
  issues: ValidationIssue[];
  blocked: boolean;
}

/** Studio State → App Layout Model (strips Studio-only `meta`) → Zod → semantic validation →
 * rounded geometry, exactly the flow in § 22. Never exports if any `issues` entry is an error —
 * `blocked` tells the caller not to call `downloadJson`. Only fields the real app understands are
 * ever included, since the output type here is `AlbumLayoutLibrary` itself, not `StudioLayout`. */
export function exportLayoutLibrary(studioLayouts: StudioLayout[]): ExportResult {
  const layouts: AlbumPageLayout[] = studioLayouts.map(({ layout }) => ({
    ...layout,
    slots: layout.slots.map((slot) => ({ ...slot, frame: roundFrame(slot.frame) })),
    textBlocks: layout.textBlocks.map((textBlock) => ({ ...textBlock, frame: roundFrame(textBlock.frame) })),
  }));
  const library: AlbumLayoutLibrary = { schemaVersion: SUPPORTED_SCHEMA_VERSION, layouts };

  const issues = validateLibrary(library);
  if (hasErrors(issues)) {
    return { issues, blocked: true };
  }

  const structurallyValid = albumLayoutLibrarySchema.safeParse(library);
  if (!structurallyValid.success) {
    // § the toolbar used to show a generic "Studio bug" message here with no way to tell what
    // actually failed, which left the user stuck (semantic validation passes, but this second,
    // separate Zod structural check still blocks export with no visible reason). Each Zod issue
    // carries its own field path (e.g. `layouts.3.textBlocks.0.fontStyle`) — surface that verbatim
    // instead of swallowing it, and resolve it back to the offending layout's real `id` when the
    // path starts with `layouts.<index>` so it lines up with every other issue's `layoutId`.
    const zodIssues: ValidationIssue[] = structurallyValid.error.issues.map((zodIssue) => {
      const [root, layoutIndex] = zodIssue.path;
      const layoutId =
        root === "layouts" && typeof layoutIndex === "number" ? layouts[layoutIndex]?.id : undefined;
      return {
        level: "error",
        code: "structuralValidationFailed",
        message: `${zodIssue.path.join(".")}: ${zodIssue.message}`,
        layoutId,
      };
    });
    return {
      issues: [...issues, ...zodIssues],
      blocked: true,
    };
  }

  return { library, issues, blocked: false };
}
