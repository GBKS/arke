# Documentation Inventory & Modernization Plan

**Last Updated:** July 8, 2026
**Total Documentation Files:** 187
**Purpose:** Comprehensive inventory of all documentation to guide modernization efforts

---

## Executive Summary

### Overview Statistics

| Category | Count | % of Total |
|----------|-------|------------|
| Root-level files | 45 | 24% |
| Archive (historical) | 27 | 14% |
| Send feature | 18 | 10% |
| Initialization docs | 16 | 9% |
| Migrations (Bark FFI) | 10 | 5% |
| Address history | 9 | 5% |
| Other subdirectories | 62 | 33% |
| **TOTAL** | **187** | **100%** |

### Documentation Health

- **Total Lines:** ~56,811 lines across all files
- **Average File Size:** ~304 lines
- **Largest File:** LIVE_ACTIVITY_EXIT_PROGRESSION_PLAN.md (2,160 lines)
- **Most Recent Updates:** STARTUP_WALLET_DETECTION_PLAN.md (Jul 7), RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md (Jul 6), PREVIEWABLE_MODELS_EXTRACTION_PLAN.md (Jul 1)
- **Trend since last inventory (May 7):** +30 files. Growth is almost entirely large root-level plan documents. The root directory is getting worse, not better (46 → 53 files), even though several subdirectories were successfully consolidated.

### What Changed Since the May 7 Inventory

**Consolidations completed:**
- `Payment destination selection/` reduced 4 → 2 files; the new `PAYMENT_DESTINATION_SELECTOR.md` (2026-06-25) consolidates IMPLEMENTATION_SUMMARY, QUICK_REFERENCE, and the flow diagram.
- `Send/` reduced 23 → 18 files (SENDVIEW_INTEGRATION_SUMMARY, SENDVIEW_ARCHITECTURE, SENDVIEW_QUICK_REFERENCE, SENDVIEW_TEST_SCENARIOS, SENDVIEW_FLOW_DIAGRAMS removed).

**New content:**
- `Migrations/` directory (10 files) — structured per-version Bark FFI migration docs. This is a good pattern; future migrations should follow it.
- ~16 new root-level docs, mostly implementation plans (device migration, live activity, LNURL-pay, read-only mode, wallet backup, VTXO refresh, relay auth refresh, previewable models) plus analyses (Lightning fee estimation, linked devices/VTXO sync).
- `Features/send-metadata-enhancement.md` (1,088 lines) + phase 0 completion doc.
- `Initialization/STARTUP_WALLET_DETECTION_PLAN.md` — active hardening work (Phases 1–4 done as of Jul 7).

**Moved:** `Movement_Onchain_Linking.md` now sits at root instead of `Movements/`.

---

## Critical Issues Identified

### 1. Root-Level Plan Document Sprawl (HIGH PRIORITY)

The dominant new problem. Implementation plans get created at root, the work ships, and the plan stays at root with a stale "Planning" status. Current root-level plans and their real status:

| File | Doc Says | Actual Status |
|------|----------|---------------|
| `READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` | ✅ Completed | Done — archive or convert to feature doc |
| `MANUAL_PRIMARY_DEVICE_ASSIGNMENT.md` | ✅ Implemented | Done — archive or convert to feature doc |
| `LNURL_PAY_IMPLEMENTATION_PLAN.md` | Plan | Shipped (LNURLResolverTests exist) — verify, then archive/convert |
| `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` | ✅ Complete | Done — valuable architecture content, keep but consider Architecture/ |
| `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md` | Planning | Supersedes non-revised version |
| ~~`DEVICE_MIGRATION_IMPLEMENTATION_PLAN.md`~~ | — | ✅ Archived 2026-07-08 (superseded by REVISED) |
| `LIVE_ACTIVITY_EXIT_PROGRESSION_PLAN.md` | Planning | Verify implementation status |
| `VTXO_REFRESH_LOGIC_PLAN.md` | Plan | Verify implementation status |
| `WALLET_BACKUP_PLAN.md` | Plan | Verify implementation status |
| `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md` | Plan | Active (Jul 6) — keep at root for now |
| `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md` | Active | Paused mid-refactor (Phase 3b next) — keep |
| `PASSKEY_INTEGRATION_PLAN.md` | Planning | Has deprecation notice (references removed LinkWalletView) — needs revision or archive |
| `PASSKEY_INTEGRATION_PLAN_REVIEW.md` | Review notes | Raw pasted review transcript — archive with plan |

### 2. Device Registry Documentation Redundancy — ✅ RESOLVED 2026-07-08

Was seven root-level files for one completed feature. Archived the 3 phase summaries, the intermediate `DEVICE_REGISTRY_COMPLETE.md` snapshot, and the race-condition fix (Step 4). Remaining at root: `Device_Registry_Reference.md` (renamed from DEVICE_REGISTRY_QUICK_REFERENCE 2026-07-08) and `DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md`.

### 3. Non-Documentation Files at Root — ✅ MOSTLY RESOLVED 2026-07-08

- ~~`ExitTransactionStatus_History.md` and `ExitTransactionStatus_State.md`~~ — moved to `Data samples/` (Step 1).
- `PASSKEY_INTEGRATION_PLAN_REVIEW.md` is a pasted conversation transcript — handled with the passkey plan in Step 15.

### 4. Long-Standing Misplaced/Historical Files (carried over from May inventory)

Still pending from previous inventory passes:
- `FFI initial integration/` — entire directory (6 files) is historical → Archive
- `Contacts/` — all 5 migration docs → Archive
- `Initialization/` — 9 completed fix/tracing docs → Archive
- `Movements/` + `Address history/` — 8 phase-complete docs → Archive
- `Send/` — 3 bug-fix docs → Archive
- BIP39 docs (3), `ACCESSIBILITY.md`, `SCRATCH_CARD_IMPLEMENTATION.md`, `INTRO_VIDEO_PLAYER_GUIDE.md`, `SIGNET_FAUCET_IMPLEMENTATION.md` → Features/
- `BarkTypes.md` → API/; `CloudKitSyncImplementation.md` → CloudKit/

### 5. Unclear Which Doc Is Current

- **Movements:** `movements.md` (root, bark movement system reference) vs `Movements/` directory vs `Movement_Onchain_Linking.md` (root). Three homes for one topic.
- **CPFP:** `cpfp_package_relay_solution.md` + `bark_issue_cpfp_package_relay.md` (root) vs `BDK/CPFP-Implementation-Plan.md`.
- **Tags:** `tags-view-architecture.md` (root, Dec 2025) vs `Features/tag-system.md`.
- ~~**Bark 0.10→0.11.3 migration:** README said "📝 Planning" though the migration shipped.~~ ✅ Status corrected 2026-07-08.

---

## Small-Steps Refinement Backlog

Each step is intentionally small (one commit, 15–30 min). Work top to bottom; update this doc's Update History as steps complete.

> **Note on moving files:** Docs live under `Shared/`, which is mostly auto-synced across targets. Markdown files aren't compiled, but after moving/deleting files verify Xcode doesn't show red missing-file references.
>
> **Note on renaming (added 2026-07-08):** When a step moves a *living* doc (reorganization Steps 16–23, or converting a completed plan to a feature doc), rename it to `Title_Case_With_Underscores.md` in the same `git mv` — e.g. `SIGNET_FAUCET_IMPLEMENTATION.md` → `Features/Signet_Faucet.md` — and fix inbound links in the same pass. Files headed to `Archive/` keep their original names (not worth the churn). Use `git mv` for case-only renames; plain `mv` misbehaves on the case-insensitive filesystem.

### Quick wins (mechanical, no judgment needed)

- [x] **Step 1:** ✅ 2026-07-08 — Moved `ExitTransactionStatus_History.md` + `ExitTransactionStatus_State.md` to `Data samples/`; updated the reference in `Movement_Onchain_Linking.md`.
- [x] **Step 2:** ✅ 2026-07-08 — Archived `DEVICE_MIGRATION_IMPLEMENTATION_PLAN.md` with a superseded-by note pointing to `_REVISED`.
- [x] **Step 3:** ✅ 2026-07-08 — Updated `Migrations/Bark-0.10.0-to-0.11.3/README.md` status to Completed (verified via 04-completion-report.md: build green, runtime smoke tests pending).
- [x] **Step 4:** ✅ 2026-07-08 — Archived DEVICE_REGISTRY_PHASE1/2/3_SUMMARY, DEVICE_REGISTRY_COMPLETE (intermediate snapshot), and DEVICE_REGISTRATION_RACE_CONDITION_FIX. Kept `Device_Registry_Reference.md` (renamed 2026-07-08) + `DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md` at root. Fixed references in Initialization/ and Security device separation/ docs; updated Archive/readme.md index.
- [ ] **Step 5:** Move `FFI initial integration/` (6 files) into `Archive/`.

### Archival passes (one directory per step)

- [ ] **Step 6:** Archive `Movements/PHASE_1..4_COMPLETE.md` (4 files). Keep MOVEMENT_SYSTEM_COMPLETE, TRANSFER_TYPE_IMPLEMENTATION, FEE_DISPLAY_FIX.
- [ ] **Step 7:** Archive `Address history/` phase + fix docs (5 files: PHASE_3_*, FIX_REDECLARATION_ERRORS). Keep plan, guide, status, quick reference.
- [ ] **Step 8:** Archive `Initialization/` completed fix/tracing docs (9 files: DOUBLE_*, FIX_DUPLICATE_MNEMONIC_SAVES, CLOUDKIT_NOTIFICATION_STORM_FIX, BATCH_TAG_CREATION_FIX, ENHANCED_*, ADDRESS_GENERATION_TRACING, SERVER_CONNECTION_DIAGNOSTICS). Keep INITIALIZATION_FLOWS, REVIEW, STARTUP_WALLET_DETECTION_PLAN (active), and evaluate the two ISSUE_* docs.
- [ ] **Step 9:** Archive all 5 `Contacts/` migration docs.
- [ ] **Step 10:** Archive `Send/` bug-fix docs (ARK_ADDRESS_FIX_CORRECTED, ARK_ADDRESS_VALIDATION_FIX, SCENARIO_9_FIX_SUMMARY, CLIPBOARD_BANNER_BUG_FIX).

### Completed-plan cleanup (verify status, then archive or convert)

- [ ] **Step 11:** `READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` — completed; archive, or distill into a short `Features/read-only-mode.md` if the behavior needs living docs.
- [ ] **Step 12:** `MANUAL_PRIMARY_DEVICE_ASSIGNMENT.md` — implemented; same treatment.
- [ ] **Step 13:** `LNURL_PAY_IMPLEMENTATION_PLAN.md` — verify shipped, then same treatment.
- [ ] **Step 14:** `LIVE_ACTIVITY_EXIT_PROGRESSION_PLAN.md`, `VTXO_REFRESH_LOGIC_PLAN.md`, `WALLET_BACKUP_PLAN.md` — check each against the codebase, update status header, archive if done and abandoned.
- [ ] **Step 15:** `PASSKEY_INTEGRATION_PLAN.md` + `_REVIEW.md` — decide: revise for current codebase (LinkWalletView is gone) or archive both.

### Reorganization (move to proper homes)

- [ ] **Step 16:** BIP39 docs (3 files) → `Features/` (or consolidate 3 → 1 while moving).
- [ ] **Step 17:** `BarkTypes.md` → `API/`; `daemon-functionality.md` → `API/` or `Architecture/`.
- [ ] **Step 18:** `CloudKitSyncImplementation.md` → `CloudKit/`.
- [ ] **Step 19:** `ACCESSIBILITY.md`, `INTRO_VIDEO_PLAYER_GUIDE.md`, `SCRATCH_CARD_IMPLEMENTATION.md`, `SIGNET_FAUCET_IMPLEMENTATION.md` → `Features/`.
- [ ] **Step 20:** `DEFAULT_CONTACT_IMPLEMENTATION.md`, `CONTACT_ADDRESS_DELETION_LOGIC.md` → `Contacts/`; `WALLET_FIRST_INITIALIZATION.md` → `Initialization/`.
- [ ] **Step 21:** Consolidate movements docs: decide the canonical home (suggest `Movements/`), move `movements.md` and `Movement_Onchain_Linking.md` there, cross-link.
- [ ] **Step 22:** Consolidate CPFP docs: fold `bark_issue_cpfp_package_relay.md` + `cpfp_package_relay_solution.md` into `BDK/` (as background for CPFP-Implementation-Plan) or archive if resolved.
- [ ] **Step 23:** Resolve `tags-view-architecture.md` vs `Features/tag-system.md` — merge or archive the older one.

### Content consolidation (larger, do last)

- [ ] **Step 24:** Send/ architecture docs: merge SENDVIEW_OVERVIEW + SENDVIEW_REFACTORING + SENDVIEW_REFACTORING_SUMMARY into one architecture doc.
- [ ] **Step 25:** Review remaining root stragglers (`BEFORE_AFTER_COMPARISON.md`, `DataVersionObservation.md`, `process-state-service-implementation.md`, `BitcoinFormatter-Locale-Guide.md`, `FIX_DATABASE_ERROR_AFTER_DELETION.md`, `NETWORK_MISMATCH_UX_CHANGES.md`, `Fee-Calculation-Analysis.md`, `APNS_MAILBOX_SPEC.md`) — keep, move, or archive each.
- [ ] **Step 26:** Update `README.md` links after the moves; add links to Migrations/ and the active plan docs.

**Projected impact:** Root 53 → ~12 files; total active (non-Archive) docs ~166 → ~110.

---

## Directory-by-Directory Inventory

### Root Level (53 files) 🔴 HIGH PRIORITY FOR CLEANUP

**Status: BLOATED** — grew from 46 to 53 since April. See backlog above; only these should remain long-term:

#### Keep at Root
- ✅ `README.md` — Main documentation index
- ✅ `Documentation_Inventory.md` — This file (renamed from DOCUMENTATION_INVENTORY 2026-07-08)

#### Active Plans (keep at root while work is in flight)
- ✅ `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md` (541 lines, Jul 1) — refactor paused at Phase 3b
- ✅ `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md` (134 lines, Jul 6) — relay auth refresh while backgrounded
- ⚠️ `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md` (1,601 lines) — planning, not yet implemented

#### Everything Else
All other root files have a disposition in the Small-Steps Refinement Backlog above (archive, move to a subdirectory, or verify-then-archive). Full categorized listing:

**Completed work, archive candidates:** READ_ONLY_MODE_IMPLEMENTATION_PLAN, MANUAL_PRIMARY_DEVICE_ASSIGNMENT, LNURL_PAY_IMPLEMENTATION_PLAN, FIX_DATABASE_ERROR_AFTER_DELETION, BEFORE_AFTER_COMPARISON, NETWORK_MISMATCH_UX_CHANGES, PASSKEY_INTEGRATION_PLAN(_REVIEW). *(Device registry/migration docs archived 2026-07-08 — Steps 2 & 4.)*

**Verify status first:** LIVE_ACTIVITY_EXIT_PROGRESSION_PLAN, VTXO_REFRESH_LOGIC_PLAN, WALLET_BACKUP_PLAN, APNS_MAILBOX_SPEC, Fee-Calculation-Analysis, process-state-service-implementation, DataVersionObservation

**Move to subdirectories:** BIP39_* (3 → Features/), ACCESSIBILITY, INTRO_VIDEO_PLAYER_GUIDE, SCRATCH_CARD_IMPLEMENTATION, SIGNET_FAUCET_IMPLEMENTATION (→ Features/), BarkTypes, daemon-functionality (→ API/), CloudKitSyncImplementation (→ CloudKit/), DEFAULT_CONTACT_IMPLEMENTATION, CONTACT_ADDRESS_DELETION_LOGIC (→ Contacts/), WALLET_FIRST_INITIALIZATION (→ Initialization/), movements + Movement_Onchain_Linking (→ Movements/), tags-view-architecture (→ merge with Features/tag-system), bark_issue_cpfp_package_relay + cpfp_package_relay_solution (→ BDK/), BitcoinFormatter-Locale-Guide (→ Archive/ with the other formatter docs)

**Reference docs, keep (find proper home):** Device_Registry_Reference, LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS (→ Architecture/?), LIGHTNING_FEE_ESTIMATION_ISSUES (current known-issues list, Jun 23), PAYMENT_DESTINATION_SELECTOR_README + QUICK_PAYMENT_SOURCE_GUIDE (→ merge with Payment destination selection/)

---

### Migrations/ (10 files) ✅ NEW — GOOD PATTERN

**Status: CURRENT** — structured per-version Bark FFI migration documentation. This is the model for future migration docs.

- `Bark-0.6.3-to-0.7.0/` (5 files) — ✅ Completed migration: README, api-changes, migration-plan, impact-analysis, completion-report
- `Bark-0.10.0-to-0.11.3/` (5 files) — ✅ Completed (README status corrected 2026-07-08): README, api-changes, migration-plan, completion-report, vtxo-exited-and-already-spent

**Assessment:** Keep as-is. Completed migration folders could eventually move under Archive/ wholesale, but they're well-contained and low-noise where they are.

---

### Architecture/ (6 files) ✅ GOOD STRUCTURE

**Status: CURRENT** — well-organized, keep as-is.

- `intro.md`, `system-overview.md`, `data-flow.md`, `service-layer.md`, `network-configuration-guide.md`, `network-configuration-persistence.md`

**Candidate addition:** `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` from root (device linking architecture).

---

### API/ (3 files) ✅ GOOD STRUCTURE

- `intro.md`, `model-definitions.md`, `service-interfaces.md`

**Candidate additions:** `BarkTypes.md` (534-line Bark API type reference) and `daemon-functionality.md` from root.

---

### Features/ (6 files) ✅ GOOD STRUCTURE

- `intro.md`, `balance-persistence.md`, `tag-system.md`, `theme-system-implementation.md`
- `send-metadata-enhancement.md` (1,088 lines, Jun 24) — active feature plan (contact/tag/note assignment during send)
- `send-metadata-enhancement_phase_0_complete.md` — ⚠️ phase doc; fold status into the main doc and archive once the feature completes

**Candidate additions from root:** BIP39 docs, accessibility, scratch card, signet faucet, intro video player.

---

### Development/ (4 files) ✅ GOOD STRUCTURE

- `intro.md`, `setup.md`, `testing-patterns.md`, `common-tasks.md`

**Assessment:** Valuable, current. Keep as-is.

---

### Send/ (18 files) ⚠️ PARTIALLY CONSOLIDATED

**Status: IMPROVED** — down from 23 (integration summary, architecture, quick reference, test scenarios, flow diagrams docs were removed since the May inventory).

#### Architecture/refactoring (still overlapping — merge into one)
- `SENDVIEW_OVERVIEW.md`, `SENDVIEW_REFACTORING.md`, `SENDVIEW_REFACTORING_SUMMARY.md`

#### Reference & guides (keep)
- ✅ `SENDVIEW_USAGE_GUIDE.md`, `SENDVIEW_USAGE_EXAMPLES.md` (603 lines), `SENDVIEW_PREVIEW_STATES.md`, `SENDVIEW_MIGRATION_CHECKLIST.md`, `SENDVIEW_BANNER_COMPARISON.md`, `PAYMENT_SOURCE_FLOW_REFERENCE.md`

#### Feature-specific (keep)
- ✅ `QR_CODE_SOURCE_IMPLEMENTATION.md`, `PAYMENT_REQUEST_INFO_BANNER_GUIDE.md`, `PAYMENT_REQUEST_INFO_BANNER_IMPLEMENTATION.md`, `PAYMENT_REQUEST_INFO_BANNER_VISUAL_REFERENCE.md`, `CLIPBOARD_BANNER_ENHANCEMENT.md`

#### Bug fixes (archive — Step 10)
- `ARK_ADDRESS_FIX_CORRECTED.md`, `ARK_ADDRESS_VALIDATION_FIX.md`, `SCENARIO_9_FIX_SUMMARY.md`, `CLIPBOARD_BANNER_BUG_FIX.md`

---

### Initialization/ (16 files) ⚠️ MOSTLY HISTORICAL + ONE ACTIVE PLAN

#### Current (keep)
- ✅ `INITIALIZATION_FLOWS.md` (1,444 lines) — comprehensive flow doc
- ✅ `STARTUP_WALLET_DETECTION_PLAN.md` (Jul 7) — **ACTIVE**: launch-to-onboarding bug hardening, Phases 1–4 done, review follow-ups remain
- ✅ `REVIEW.md` — system review
- ⚠️ `WALLET_CREATION_ISSUES.md`, `WALLET_CREATION_ISSUES_OVERVIEW.md` — verify still current
- ⚠️ `ISSUE_1_DEVICE_REGISTRATION.md`, `ISSUE_2_ADDRESS_GENERATION.md` — evaluate

#### Archive (completed fixes/tracing — Step 8)
- `DOUBLE_WALLET_INITIALIZATION_FIX.md`, `DOUBLE_INITIALIZATION_FIX_CORRECTED.md`, `FIX_DUPLICATE_MNEMONIC_SAVES.md`, `CLOUDKIT_NOTIFICATION_STORM_FIX.md`, `BATCH_TAG_CREATION_FIX.md`, `ENHANCED_CALL_TRACING.md`, `ENHANCED_INITIALIZATION_LOGGING.md`, `ADDRESS_GENERATION_TRACING.md`, `SERVER_CONNECTION_DIAGNOSTICS.md`

---

### Address history/ (9 files) ⚠️ NEEDS CLEANUP

#### Keep
- ✅ `ADDRESS_HISTORY_PLAN.md`, `ADDRESS_IMPLEMENTATION_GUIDE.md`, `ADDRESS_QUICK_REFERENCE.md`, `ADDRESS_IMPLEMENTATION_STATUS.md`

#### Archive (Step 7)
- `PHASE_3_IMPLEMENTATION.md`, `PHASE_3_TRANSACTION_INTEGRATION.md`, `PHASE_3_COMPLETE.md`, `PHASE_3_COMPLETE_SUMMARY.md`, `FIX_REDECLARATION_ERRORS.md`

---

### Movements/ (7 files) ⚠️ ARCHIVE PHASES

#### Keep
- ✅ `MOVEMENT_SYSTEM_COMPLETE.md`, `TRANSFER_TYPE_IMPLEMENTATION.md`, `FEE_DISPLAY_FIX.md`

#### Archive (Step 6)
- `PHASE_1_COMPLETE.md`, `PHASE_2_COMPLETE.md`, `PHASE_3_COMPLETE.md`, `PHASE_4_COMPLETE.md`

**Note:** `movements.md` and `Movement_Onchain_Linking.md` currently live at root — consolidate here (Step 21).

---

### BDK/ (6 files) ✅ MOSTLY CURRENT

- `BDK-Implementation-Complete.md`, `BDK-Integration-Status.md`, `BDK-Next-Steps.md`, `BDK-Improvements-2026-02-26.md`, `CPFP-Implementation-Plan.md` (1,008 lines), `OnchainTransactionService-Implementation.md`

**Note:** Root-level CPFP docs (`cpfp_package_relay_solution.md`, `bark_issue_cpfp_package_relay.md`) should fold in here or be archived (Step 22).

---

### Contacts/ (5 files) ⚠️ ARCHIVE ALL (Step 9)

All 5 are completed-migration docs: `CONTACTS_VIEW_REFACTOR_COMPLETE.md`, `CONTACT_DETAIL_IOS_MERGE_SUMMARY.md`, `FORM_MIGRATION_SUMMARY.md`, `FORM_MIGRATION_TECHNICAL_DETAILS.md`, `FORM_MIGRATION_VISUAL_GUIDE.md`

Root-level `DEFAULT_CONTACT_IMPLEMENTATION.md` and `CONTACT_ADDRESS_DELETION_LOGIC.md` would move in as the living docs (Step 20).

---

### CloudKit/ (3 files) ✅ KEEP

- `CloudKitQuickStart.md`, `CloudKitSetupChecklist.md`, `CloudKitSyncGuidelines.md`
- Candidate addition: `CloudKitSyncImplementation.md` from root (Step 18).

---

### Console/ (3 files) ✅ KEEP

- `CONSOLE_COMMANDS.md`, `CONSOLE_OPTIMIZATION.md`, `CONSOLE_REFACTOR.md`

---

### Security device separation/ (6 files) ✅ CURRENT

- `IMPLEMENTATION_SUMMARY.md`, `SEPARATION_OF_CONCERNS_IMPLEMENTATION.md`, `ARCHITECTURE_DIAGRAMS.md`, `QUICK_REFERENCE.md`, `TESTING_CHECKLIST_SEPARATION.md`, `COMMIT_MESSAGE.md` (archive candidate)

---

### Payment destination selection/ (2 files) ✅ CONSOLIDATED

- ✅ `PAYMENT_DESTINATION_SELECTOR.md` (Jun 25) — consolidated reference (replaced IMPLEMENTATION_SUMMARY, QUICK_REFERENCE, flow diagram)
- ⚠️ `BUG_FIXES_SUMMARY.md` — archive candidate

**Note:** Root-level `PAYMENT_DESTINATION_SELECTOR_README.md` (Nov 2025) predates the consolidated doc — likely superseded; verify and archive.

---

### Localization/ (2 files) ✅ KEEP

- `LOCALIZATION_MIGRATION_SUMMARY.md`, `LOCALIZATION_UPDATE_SUMMARY.md`

---

### FFI initial integration/ (6 files) ⚠️ ARCHIVE ALL (Step 5)

Historical: `PHASE1..4_COMPLETE.md`, `PHASES567_COMPLETE.md`, `FINAL_COMPLETE.md`

---

### Archive/ (27 files) ✅ PROPER USE

Appropriately archived migration/refactoring/phase docs plus `readme.md` index (6 device registry/migration docs added 2026-07-08). Will grow substantially as the backlog above executes — consider subfolders (`migrations/`, `completed-implementations/`, `fixes/`) once it passes ~40 files.

---

### Data samples/ (3 md files + JSON files)

- `Movements.md`, `ExitTransactionStatus_History.md`, `ExitTransactionStatus_State.md` (the latter two are raw exit-state dumps, moved from root 2026-07-08) + JSON samples in CLI/. Keep.

---

## Documentation Standards (Proposed)

### File Naming Conventions

- **Format:** `Title_Case_With_Underscores.md` — e.g. `Movement_Onchain_Linking.md`. Not ALL_CAPS (hard to read), not lowercase-kebab.
- **Quick Reference:** `Topic_Reference.md` (not QUICK_REFERENCE)
- **No "SUMMARY" in names** — all docs should be summaries
- **No phase numbers** — use git history for implementation phases
- **Plans:** include a `**Status:**` header line and update it when work ships; move to Archive (or convert to a feature doc) once complete

### Documentation Lifecycle

1. **Planning:** High-level plan document — fine at root or in the feature's directory while active
2. **Implementation:** Track in git commits, not docs
3. **Completion:** Update the plan's Status header; distill lasting knowledge into a feature doc; archive the plan
4. **Maintenance:** Update feature docs as needed
5. **Deprecation:** Move to Archive with a deprecation note

### What NOT to Document

- Individual bug fixes (use git commits)
- Phase-by-phase implementation (use git history)
- Refactoring steps (use git commits)
- Temporary workarounds (use code comments)

### What TO Document

- Feature purpose and architecture
- API interfaces and usage examples
- Development workflows and testing patterns
- Configuration and troubleshooting guides

### When to Archive

Archive documentation when:
- Implementation is complete and stable
- Document describes a specific bug fix
- Document tracks phase-by-phase implementation
- Document is superseded by newer documentation

### When to Delete

Only delete when it's an exact duplicate, content has been merged elsewhere, or the file was created in error. **Default action: ARCHIVE, not DELETE.**

---

## Metrics & Health Indicators

### Current State (July 8, 2026)

| Metric | Value | Health |
|--------|-------|--------|
| Total Files | 187 | 🔴 Growing (was 157 in May) |
| Root Files | 45 | ⚠️ Improving (53 → 45 on Jul 8) |
| Archived Files | 27 | ⚠️ Growing appropriately |
| Phase/Fix Docs (active dirs) | ~30 | ⚠️ Should archive |
| Stale-status plan docs | ~7 | ⚠️ New problem category |
| Total Lines | ~56,800 | — |

### Target State

| Metric | Target |
|--------|--------|
| Total active (non-Archive) files | ~110 |
| Root files | ~12 (index, inventory, active plans only) |
| Phase/fix docs outside Archive | 0 |
| Plan docs with wrong Status header | 0 |

---

## Update History

| Date | Author | Changes |
|------|--------|---------|
| 2026-07-08 | Claude Code | Naming convention decided: `Title_Case_With_Underscores.md` (per Christoph); living docs get renamed during their backlog moves, Archive keeps original names |
| 2026-07-08 | Claude Code | Renamed the two settled keepers to the new convention: DEVICE_REGISTRY_QUICK_REFERENCE → Device_Registry_Reference, DOCUMENTATION_INVENTORY → Documentation_Inventory; fixed inbound links (INITIALIZATION_FLOWS deprecation notice + 2 mentions) |
| 2026-07-08 | Claude Code | Backlog Steps 1–4 completed: moved 2 ExitTransactionStatus dumps to Data samples/, archived superseded device migration plan + 5 device registry docs (root 53 → 45, Archive 21 → 27), corrected Bark 0.11.3 migration README status, fixed cross-references in 5 docs, updated Archive/readme.md index |
| 2026-07-08 | Claude Code | Full re-inventory: 157 → 187 files. Added Migrations/ section, catalogued 16 new root docs (mostly plans), noted Send/ and Payment destination selection/ consolidations, flagged stale plan statuses, replaced Priority Actions with 26-step small-steps backlog |
| 2026-05-07 | Claude Code | Added LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md to inventory (device linking architecture) |
| 2026-04-24 | Claude Code | Archived 10 historical migration/refactoring docs to Archive/ directory |
| 2026-04-24 | Claude Code | Deleted duplicate PHASE_3_COMPLETE_SUMMARY 2.md from Address history/ |
| 2026-04-24 | Claude Code | Merged Intro.md into README.md and deleted duplicate |
| 2026-04-24 | Claude Code | Fixed Archive file extensions (3 files) |
| 2026-04-22 | Claude Code | Initial comprehensive inventory created |

---

## Notes for Future Maintainers

- This inventory is a living document — update it (and the backlog checkboxes) as you make changes.
- Work the Small-Steps Refinement Backlog top-to-bottom; each step is one commit.
- When a plan doc ships, update its Status header immediately — stale "Planning" headers were the biggest source of confusion in this pass.
- Automation opportunities: file counter, link checker, code-reference checker, staleness flagging (docs untouched 6+ months).

---

**END OF INVENTORY**
