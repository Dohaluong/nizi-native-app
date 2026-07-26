# ADR-MD-004: Metadata-first, original-last

**Status:** Accepted

**Decision:** Processing always goes metadata → clustering → thumbnail → selective analysis → original. Original assets are only requested at the final step (upload, print prep, full-screen view).

**Context:** See [PRODUCT-PHILOSOPHY.md § Metadata-first](../../philosophy/PRODUCT-PHILOSOPHY.md#3-metadata-first). This is what keeps scan time, memory, and network/iCloud usage bounded on libraries with tens of thousands of assets.
