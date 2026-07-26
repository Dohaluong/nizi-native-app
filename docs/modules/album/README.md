# Album

Not yet documented. Referenced in the module map in [../../architecture/ARCHITECTURE.md](../../architecture/ARCHITECTURE.md#2-module-map-nizi-ios).

Per [ADR-MD-001](../../architecture/ADR/adr-md-001-memory-discovery-independent-module.md), this module must not access PhotoKit directly — it consumes photos through the interfaces [Memory Discovery](../memory-discovery/) exposes.
