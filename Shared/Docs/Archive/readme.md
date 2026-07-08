# Documentation Archive

Historical implementation, migration, and fix documentation. These files chronicle how the system was built but are no longer the primary reference for current behavior. Archived files keep their original names (see naming policy in `../Documentation_Inventory.md`).

## Structure

- **`Migrations/`** — Completed architectural and model migrations (balance models, transaction architecture, iOS view migrations, BitcoinFormatter). `migration-history.md` is the consolidated summary.
- **`Implementations/`** — Completed feature implementations and refactorings, chronicled step-by-step or phase-by-phase: tag models, device registry (phases 1–3 + intermediate snapshot), wallet deletion, superseded device migration plan, and assorted refactoring summaries. Multi-file batches archived from a feature directory keep a topic subfolder (e.g. `Movements/`).
- **`Fixes/`** — Completed bug-fix and diagnostic/tracing docs. Each describes a specific resolved issue; the fix itself lives in git history.

## Purpose

These documents are preserved for:
- Historical context of design decisions
- Understanding the evolution of the codebase
- Reference for similar future implementations
- Troubleshooting migration-related issues

## Pointers to living docs

- Device registry: `../Device_Registry_Reference.md` (API reference), `../DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md` (final summary)
- Device migration planning: `../DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md`
- For current system documentation, see the main `Docs/` folder structure.
