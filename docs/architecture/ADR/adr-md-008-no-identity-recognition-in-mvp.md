# ADR-MD-008: No identity recognition in the MVP

**Status:** Accepted

**Decision:** The MVP only detects face *presence* and quality (count, group vs. portrait, cropped/occluded) — it does not identify who a person is, name people, or sync face data to the server.

**Context:** If per-person recognition is needed later, any embedding data must stay on-device, be encrypted, require separate consent, and be deletable — never uploaded by default.
