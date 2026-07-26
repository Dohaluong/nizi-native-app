# ADR-MD-003: iOS talks to the backend only through the API

**Status:** Accepted

**Decision:** `nizi-ios` never accesses the server database directly; all communication with Nizi Web goes through its API.

**Context:** Keeps the two apps decoupled and lets the server enforce ownership/validation on anything the client sends (e.g. album creation, upload sessions — see [SPRINT-007](../../sprint/SPRINT-007-MOBILE-API-UPLOAD-HANDOFF.md)).
