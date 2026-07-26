# Memory Discovery

**Product name:** Khám phá ký ức · **Technical name:** `PhotoLibraryDiscovery` · **Platform:** Native iOS

Surveys the user's Photos library on-device, builds a local metadata index, detects clusters of related photos, and proposes events the user can turn into Albums — without uploading the library.

## Docs

- [SPEC.md](SPEC.md) — product spec, problem statement, user stories, MVP scope.
- [ARCHITECTURE.md](ARCHITECTURE.md) — module architecture, components, domain entities, folder structure.
- [../../database/memory-discovery.md](../../database/memory-discovery.md) — local schema (SwiftData/GRDB).
- [../../ui/memory-discovery.md](../../ui/memory-discovery.md) — screens, navigation flow, copywriting, accessibility.
- [../../sprint/](../../sprint/) — sprint-by-sprint build order (SPRINT-001 through SPRINT-008).
- [../../architecture/ADR/](../../architecture/ADR/) — architecture decision records (ADR-MD-001–010).
- [ORIGINAL-DRAFT.md](ORIGINAL-DRAFT.md) — the original full-length draft this module's docs were split out from; kept for historical reference only, superseded by the files above.

## Cross-cutting principles

This module is where Nizi's [product philosophy](../../philosophy/PRODUCT-PHILOSOPHY.md) and [design principles](../../philosophy/DESIGN-PRINCIPLES.md) were first written down. Other modules should follow the same rules rather than re-deriving them.
