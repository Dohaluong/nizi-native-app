# Product Philosophy

Core values that guide product and architecture decisions across Nizi. First articulated while designing the Memory Discovery module ([modules/memory-discovery](../modules/memory-discovery/)); they apply to any module that touches the user's photo library or personal data.

## 1. Nizi does not replace Apple Photos

Apple Photos remains the source of truth for the original library: storage, iCloud sync, editing, deletion, cross-device sync.

Nizi's role is narrower:

> Discover the stories hidden in a photo library and help the user turn them into meaningful albums.

## 2. Local-first

Initial survey of a user's library happens on-device. Nothing is uploaded by default — not originals, thumbnails, GPS coordinates, recognition data, face data, or the library listing itself. The server only receives photos once the user confirms an album or a feature that explicitly requires sync.

## 3. Metadata-first

Processing order is fixed:

```text
Metadata
→ Temporal / spatial clustering
→ Small thumbnails
→ Selective image analysis
→ Original only when actually needed
```

This ordering is what keeps scan time, memory, CPU, thermal load, battery, iCloud traffic, and upload volume low.

## 4. Suggest, not decide

Nizi proposes; it never decides on the user's behalf. Every suggestion can be renamed, split, merged, extended, trimmed, dismissed, or silenced permanently.

## 5. Progressive intelligence

Early phases should not require complex AI. Intelligence is layered in over time:

```text
Phase 1: Metadata rules
Phase 2: Image quality
Phase 3: Similarity and duplicate detection
Phase 4: Scene and people understanding
Phase 5: Personalized curation
```

Don't front-load AI before the rules-based core is stable.

## 6. Resumable by design

Any long-running task (scan, analysis, upload) must batch its work, checkpoint progress, tolerate pause/resume, and survive the app being closed mid-task. Nothing may depend on the app staying open until completion.

## 7. Explainable suggestions

Every suggestion should be able to justify itself: how many photos, over how many days, where, what kind of content, why these were chosen as highlights. Never present an "AI-made" result without context the user can inspect.
