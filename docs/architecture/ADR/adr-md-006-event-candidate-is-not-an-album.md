# ADR-MD-006: EventCandidate is not an Album

**Status:** Accepted

**Decision:** `EventCandidate` (a discovered cluster) and `AlbumDraft` (a reviewed, user-confirmed selection) are distinct entities. A server-side Album is only created once the user explicitly confirms an `AlbumDraft`.

**Context:** Keeps automatic discovery clearly separate from the user's actual decision to create something — see [PRODUCT-PHILOSOPHY.md § Suggest, not decide](../../philosophy/PRODUCT-PHILOSOPHY.md#4-suggest-not-decide).
