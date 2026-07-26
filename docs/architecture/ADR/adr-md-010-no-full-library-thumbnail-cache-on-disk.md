# ADR-MD-010: No full-library thumbnail cache on disk

**Status:** Accepted

**Decision:** Nizi does not persist thumbnails for the whole library. `PHCachingImageManager` (PhotoKit) remains the primary thumbnail source for an actively displayed gallery; Nizi keeps only a small memory cache for visible/near-visible cells and a limited disk cache for covers and in-progress album drafts.

**Context:** Avoids unbounded disk growth on libraries with tens of thousands of assets — see [modules/memory-discovery/ARCHITECTURE.md § 6.4](../../modules/memory-discovery/ARCHITECTURE.md).
