# Documentation Archive

Historical implementation, migration, and fix documentation. These files chronicle how the system was built but are no longer the primary reference for current behavior. Archived files keep their original names (see naming policy in `../Documentation_Inventory.md`). Since 2026-09-27 `Docs/` lives at the repo root outside every Xcode target, so basenames no longer need to be unique.

## Structure

- **`Migrations/`** — Completed architectural and model migrations (balance models, transaction architecture, iOS view migrations, BitcoinFormatter). `migration-history.md` is the consolidated summary. `Localization/` holds the March 2026 semantic-key migration summaries.
- **`Implementations/`** — Completed feature implementations and refactorings, chronicled step-by-step or phase-by-phase: tag models, the tags view refactor (merged into `Features/tag-system.md`), device registry (phases 1–3 + intermediate snapshot), wallet deletion, superseded device migration plan, read-only mode + manual primary device assignment plans, the LNURL-pay, live activity, VTXO refresh, and wallet backup plans, the passkey integration plan + review (not pursued), and assorted refactoring summaries. Multi-file batches archived from a feature directory keep a topic subfolder: `Movements/`, `Address history/`, `Contacts/`, `FFI initial integration/`, and — added 2026-09-27 — `SendView/` (11 superseded send-flow docs), `BDK/` (the abandoned custom BDK onchain wallet, all 6 docs), `CloudKit/` (alpha setup guides), `Initialization/` (the 2024 three-flow walkthrough + architecture review), `Security device separation/` (Dec 2024 SecurityService split, 6 docs). Root-level plans archived the same day: relay auth background refresh, linked-devices/VTXO sync analysis, device registry all-phases summary, revised device migration plan (superseded by `../Architecture/Multi_Device_Design.md`), payment destination selector README, network mismatch UX, AddressValidator before/after, colour-theme plan (never built).
- **`Fixes/`** — Completed bug-fix and diagnostic/tracing docs. Each describes a specific resolved issue; the fix itself lives in git history. `Wallet creation/` holds the Dec 2024 wallet-creation issue analyses (device registration race, address generation).

## Purpose

These documents are preserved for:
- Historical context of design decisions
- Understanding the evolution of the codebase
- Reference for similar future implementations
- Troubleshooting migration-related issues

## Pointers to living docs

- Device registry: `../Device_Registry_Reference.md` (API reference); multi-device model: `../Architecture/Multi_Device_Design.md`
- Read-only mode & device roles: `../Features/Read_Only_Mode.md`
- LNURL-pay: `../Features/LNURL_Pay.md`
- Tag system (incl. view architecture): `../Features/tag-system.md`
- For current system documentation, see the main `Docs/` folder structure.
