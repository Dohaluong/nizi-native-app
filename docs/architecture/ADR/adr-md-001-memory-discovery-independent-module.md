# ADR-MD-001: Memory Discovery is an independent module

**Status:** Accepted

**Decision:** Memory Discovery is a standalone module inside `nizi-ios`. Other modules (e.g. Album Management) do not access PhotoKit directly — they go through the interfaces Memory Discovery exposes.

**Context:** Keeps PhotoKit coupling in one place, so it can be tested, replaced, or extended without touching every module that needs a photo.
