# ADR-MD-009: Long-running tasks must be resumable

**Status:** Accepted

**Decision:** Any multi-step task that can span more than a few seconds (library scan, analysis, upload) must batch its work and checkpoint progress, so it can pause and resume across app launches — nothing may depend on the app staying open until completion.

**Context:** See [PRODUCT-PHILOSOPHY.md § Resumable by design](../../philosophy/PRODUCT-PHILOSOPHY.md#6-resumable-by-design). iOS gives no guarantee that background work runs to completion once the app closes.
