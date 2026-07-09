# Documentation Inventory & Modernization Plan

**Last Updated:** July 9, 2026
**Total Documentation Files:** 189
**Purpose:** Comprehensive inventory of all documentation to guide modernization efforts

---

## Executive Summary

### Overview Statistics

| Category | Count | % of Total |
|----------|-------|------------|
| Root-level files | 39 | 21% |
| Archive (historical) | 66 | 35% |
| Send feature | 14 | 7% |
| Initialization docs | 7 | 4% |
| Migrations (Bark FFI) | 10 | 5% |
| Address history | 4 | 2% |
| Other subdirectories | 49 | 26% |
| **TOTAL** | **189** | **100%** |

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
| ~~`READ_ONLY_MODE_IMPLEMENTATION_PLAN.md`~~ | — | ✅ Archived 2026-07-09, distilled into `Features/Read_Only_Mode.md` |
| ~~`MANUAL_PRIMARY_DEVICE_ASSIGNMENT.md`~~ | — | ✅ Archived 2026-07-09, covered by `Features/Read_Only_Mode.md` |
| ~~`LNURL_PAY_IMPLEMENTATION_PLAN.md`~~ | — | ✅ Archived 2026-07-09, distilled into `Features/LNURL_Pay.md` |
| `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` | ✅ Complete | Done — valuable architecture content, keep but consider Architecture/ |
| `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md` | Planning | Supersedes non-revised version |
| ~~`DEVICE_MIGRATION_IMPLEMENTATION_PLAN.md`~~ | — | ✅ Archived 2026-07-08 (superseded by REVISED) |
| ~~`LIVE_ACTIVITY_EXIT_PROGRESSION_PLAN.md`~~ | — | ✅ Archived 2026-07-09 (shipped 2026-05-12) |
| ~~`VTXO_REFRESH_LOGIC_PLAN.md`~~ | — | ✅ Archived 2026-07-09 (shipped 2026-04-24) |
| ~~`WALLET_BACKUP_PLAN.md`~~ | — | ✅ Archived 2026-07-09 (shipped 2026-05-07) |
| `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md` | Plan | Active (Jul 6) — keep at root for now |
| `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md` | Active | Paused mid-refactor (Phase 3b next) — keep |
| `PASSKEY_INTEGRATION_PLAN.md` | Planning | Has deprecation notice (references removed LinkWalletView) — needs revision or archive |
| `PASSKEY_INTEGRATION_PLAN_REVIEW.md` | Review notes | Raw pasted review transcript — archive with plan |

### 2. Device Registry Documentation Redundancy — ✅ RESOLVED 2026-07-08

Was seven root-level files for one completed feature. Archived the 3 phase summaries, the intermediate `DEVICE_REGISTRY_COMPLETE.md` snapshot, and the race-condition fix (Step 4). Remaining at root: `Device_Registry_Reference.md` (renamed from DEVICE_REGISTRY_QUICK_REFERENCE 2026-07-08) and `DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md`.

### 3. Non-Documentation Files at Root — ✅ MOSTLY RESOLVED 2026-07-08

- ~~`ExitTransactionStatus_History.md` and `ExitTransactionStatus_State.md`~~ — moved to `Data samples/` (Step 1).
- `PASSKEY_INTEGRATION_PLAN_REVIEW.md` is a pasted conversation transcript — handled with the passkey plan in Step 15.

### 4. Long-Standing Misplaced/Historical Files — ✅ ARCHIVAL HALF RESOLVED 2026-07-08

The archival items (Steps 5–10) are done:
- ~~`FFI initial integration/` (6 files)~~ → Archive/Implementations/
- ~~`Contacts/` migration docs (5)~~ → Archive/Implementations/Contacts/
- ~~`Initialization/` fix/tracing docs (9)~~ → Archive/Fixes/
- ~~`Movements/` + `Address history/` phase docs (8 + 1 fix)~~ → Archive/Implementations/ + Fixes/
- ~~`Send/` bug-fix docs (4)~~ → Archive/Fixes/

Still pending (reorganization, Steps 16–23):
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
- [x] **Step 5:** ✅ 2026-07-08 — Moved `FFI initial integration/` (6 files) to `Archive/Implementations/FFI initial integration/`; directory removed.

### Archival passes (one directory per step)

> Steps 5–10 were executed together on 2026-07-08, after first restructuring `Archive/` into `Migrations/`, `Implementations/`, and `Fixes/` category folders (commit "Restructure Docs/Archive…"). Multi-file batches kept topic subfolders under `Implementations/`, which also resolved the `PHASE_3_COMPLETE.md` name collision between Movements and Address history.

- [x] **Step 6:** ✅ 2026-07-08 — Archived `Movements/PHASE_1..4_COMPLETE.md` (4 files) to `Archive/Implementations/Movements/`. Kept MOVEMENT_SYSTEM_COMPLETE, TRANSFER_TYPE_IMPLEMENTATION, FEE_DISPLAY_FIX; updated phase-doc references in MOVEMENT_SYSTEM_COMPLETE.
- [x] **Step 7:** ✅ 2026-07-08 — Archived `Address history/` PHASE_3_* (4 files) to `Archive/Implementations/Address history/` and FIX_REDECLARATION_ERRORS to `Archive/Fixes/`. Kept plan, guide, status, quick reference; updated references in ADDRESS_IMPLEMENTATION_STATUS.
- [x] **Step 8:** ✅ 2026-07-08 — Archived the 9 completed fix/tracing docs to `Archive/Fixes/`. Kept INITIALIZATION_FLOWS, REVIEW, STARTUP_WALLET_DETECTION_PLAN (active), WALLET_CREATION_ISSUES(_OVERVIEW). **ISSUE_1/ISSUE_2 kept in place** — both say "root cause identified, ready for implementation" (Dec 2024); whether their fixes shipped needs code verification before archiving (folded into Step 25's review).
- [x] **Step 9:** ✅ 2026-07-08 — Archived all 5 `Contacts/` migration docs to `Archive/Implementations/Contacts/`; directory removed (will be recreated by Step 20's living docs).
- [x] **Step 10:** ✅ 2026-07-08 — Archived the 4 `Send/` bug-fix docs to `Archive/Fixes/`; updated the reference in CLIPBOARD_BANNER_ENHANCEMENT.

### Completed-plan cleanup (verify status, then archive or convert)

- [x] **Step 11:** ✅ 2026-07-09 — Archived `READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` to `Archive/Implementations/`; distilled current behavior into new `Features/Read_Only_Mode.md` (also covers Step 12's role switching). Fixed 4 inbound references in 3 docs.
- [x] **Step 12:** ✅ 2026-07-09 — Archived `MANUAL_PRIMARY_DEVICE_ASSIGNMENT.md` to `Archive/Implementations/` (no inbound links); its demote/promote flows are covered by `Features/Read_Only_Mode.md` § Switching the Primary Device.
- [x] **Step 13:** ✅ 2026-07-09 — Verified LNURL-pay shipped (2026-05-30; LNURLResolver, `.lnurl` in ArkéUI AddressFormat, payment execution, tests all present). Archived the plan to `Archive/Implementations/`; distilled current behavior into `Features/LNURL_Pay.md` — notably, since Bark 0.11 the LNURL flow runs natively via `payLnurl`, superseding the plan's app-side invoice handling. Updated 2 references in the Bark 0.11.3 migration docs.
- [x] **Step 14:** ✅ 2026-07-09 — All three verified shipped and archived to `Archive/Implementations/` with archive notes: Live Activity (2026-05-12; all planned files exist in Shared + ArkeWidgets, plan's checklist was just never ticked), VTXO refresh logic (2026-04-24; `BalanceRefreshStatusViewModel` implements the ppm-free-window design as written), wallet backup (2026-05-07; `WalletBackupService` — note the DB is `bark.sqlite`, not the plan's `db.sqlite`). Fixed 1 inbound reference in DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.
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

### Root Level (39 files) 🔴 HIGH PRIORITY FOR CLEANUP

**Status: BLOATED** — peaked at 53 in early July, down to 39 after Steps 1–4 and 11–14. See backlog above; only these should remain long-term:

#### Keep at Root
- ✅ `README.md` — Main documentation index
- ✅ `Documentation_Inventory.md` — This file (renamed from DOCUMENTATION_INVENTORY 2026-07-08)

#### Active Plans (keep at root while work is in flight)
- ✅ `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md` (541 lines, Jul 1) — refactor paused at Phase 3b
- ✅ `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md` (134 lines, Jul 6) — relay auth refresh while backgrounded
- ⚠️ `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md` (1,601 lines) — planning, not yet implemented

#### Everything Else
All other root files have a disposition in the Small-Steps Refinement Backlog above (archive, move to a subdirectory, or verify-then-archive). Full categorized listing:

**Completed work, archive candidates:** FIX_DATABASE_ERROR_AFTER_DELETION, BEFORE_AFTER_COMPARISON, NETWORK_MISMATCH_UX_CHANGES, PASSKEY_INTEGRATION_PLAN(_REVIEW). *(Device registry/migration docs archived 2026-07-08 — Steps 2 & 4; read-only mode + manual primary assignment archived 2026-07-09 — Steps 11 & 12; LNURL-pay plan archived 2026-07-09 — Step 13.)*

**Verify status first:** APNS_MAILBOX_SPEC, Fee-Calculation-Analysis, process-state-service-implementation, DataVersionObservation *(Live Activity, VTXO refresh, and wallet backup plans verified shipped and archived 2026-07-09 — Step 14.)*

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

### Features/ (8 files) ✅ GOOD STRUCTURE

- `intro.md`, `balance-persistence.md`, `tag-system.md`, `theme-system-implementation.md`
- `Read_Only_Mode.md` (Jul 9) — secondary-device read-only mode + primary device switching (distilled from the two archived plans, Steps 11–12)
- `LNURL_Pay.md` (Jul 9) — LNURL-pay send support (distilled from the archived plan, Step 13; Bark 0.11 handles the flow natively via `payLnurl`)
- `send-metadata-enhancement.md` (1,088 lines, Jun 24) — active feature plan (contact/tag/note assignment during send)
- `send-metadata-enhancement_phase_0_complete.md` — ⚠️ phase doc; fold status into the main doc and archive once the feature completes

**Candidate additions from root:** BIP39 docs, accessibility, scratch card, signet faucet, intro video player.

---

### Development/ (4 files) ✅ GOOD STRUCTURE

- `intro.md`, `setup.md`, `testing-patterns.md`, `common-tasks.md`

**Assessment:** Valuable, current. Keep as-is.

---

### Send/ (14 files) ⚠️ PARTIALLY CONSOLIDATED

**Status: IMPROVED** — down from 23 in May; bug-fix docs archived 2026-07-08 (Step 10).

#### Architecture/refactoring (still overlapping — merge into one, Step 24)
- `SENDVIEW_OVERVIEW.md`, `SENDVIEW_REFACTORING.md`, `SENDVIEW_REFACTORING_SUMMARY.md`

#### Reference & guides (keep)
- ✅ `SENDVIEW_USAGE_GUIDE.md`, `SENDVIEW_USAGE_EXAMPLES.md` (603 lines), `SENDVIEW_PREVIEW_STATES.md`, `SENDVIEW_MIGRATION_CHECKLIST.md`, `SENDVIEW_BANNER_COMPARISON.md`, `PAYMENT_SOURCE_FLOW_REFERENCE.md`

#### Feature-specific (keep)
- ✅ `QR_CODE_SOURCE_IMPLEMENTATION.md`, `PAYMENT_REQUEST_INFO_BANNER_GUIDE.md`, `PAYMENT_REQUEST_INFO_BANNER_IMPLEMENTATION.md`, `PAYMENT_REQUEST_INFO_BANNER_VISUAL_REFERENCE.md`, `CLIPBOARD_BANNER_ENHANCEMENT.md`

---

### Initialization/ (7 files) ✅ CLEANED UP 2026-07-08

- ✅ `INITIALIZATION_FLOWS.md` (1,444 lines) — comprehensive flow doc
- ✅ `STARTUP_WALLET_DETECTION_PLAN.md` (Jul 7) — **ACTIVE**: launch-to-onboarding bug hardening, Phases 1–4 done, review follow-ups remain
- ✅ `REVIEW.md` — system review
- ⚠️ `WALLET_CREATION_ISSUES.md`, `WALLET_CREATION_ISSUES_OVERVIEW.md` — verify still current
- ⚠️ `ISSUE_1_DEVICE_REGISTRATION.md`, `ISSUE_2_ADDRESS_GENERATION.md` — Dec 2024 root-cause analyses, "ready for implementation"; verify fixes shipped, then archive (Step 25)

The 9 completed fix/tracing docs moved to `Archive/Fixes/` (Step 8).

---

### Address history/ (4 files) ✅ CLEANED UP 2026-07-08

- ✅ `ADDRESS_HISTORY_PLAN.md`, `ADDRESS_IMPLEMENTATION_GUIDE.md`, `ADDRESS_QUICK_REFERENCE.md`, `ADDRESS_IMPLEMENTATION_STATUS.md`

Phase docs moved to `Archive/Implementations/Address history/`, FIX_REDECLARATION_ERRORS to `Archive/Fixes/` (Step 7).

---

### Movements/ (3 files) ✅ CLEANED UP 2026-07-08

- ✅ `MOVEMENT_SYSTEM_COMPLETE.md`, `TRANSFER_TYPE_IMPLEMENTATION.md`, `FEE_DISPLAY_FIX.md`

Phase docs moved to `Archive/Implementations/Movements/` (Step 6).

**Note:** `movements.md` and `Movement_Onchain_Linking.md` currently live at root — consolidate here (Step 21).

---

### BDK/ (6 files) ✅ MOSTLY CURRENT

- `BDK-Implementation-Complete.md`, `BDK-Integration-Status.md`, `BDK-Next-Steps.md`, `BDK-Improvements-2026-02-26.md`, `CPFP-Implementation-Plan.md` (1,008 lines), `OnchainTransactionService-Implementation.md`

**Note:** Root-level CPFP docs (`cpfp_package_relay_solution.md`, `bark_issue_cpfp_package_relay.md`) should fold in here or be archived (Step 22).

---

### Contacts/ — ✅ ARCHIVED 2026-07-08 (Step 9)

All 5 completed-migration docs moved to `Archive/Implementations/Contacts/`; the directory is gone. It will be recreated when Step 20 moves the living docs (`DEFAULT_CONTACT_IMPLEMENTATION.md`, `CONTACT_ADDRESS_DELETION_LOGIC.md`) in from root.

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

### FFI initial integration/ — ✅ ARCHIVED 2026-07-08 (Step 5)

All 6 historical phase docs moved to `Archive/Implementations/FFI initial integration/`; the directory is gone.

---

### Archive/ (66 files) ✅ PROPER USE, RESTRUCTURED 2026-07-08

Now organized into category folders (plus `readme.md` index at Archive root):
- `Migrations/` (7) — completed model/architecture migrations
- `Implementations/` (43) — completed implementations and refactorings; multi-file batches keep topic subfolders (`FFI initial integration/`, `Movements/`, `Address history/`, `Contacts/`)
- `Fixes/` (15) — completed bug-fix and tracing/diagnostic docs

Steps 5–10 added 33 files; Steps 11–14 added the read-only mode, manual primary assignment, LNURL-pay, live activity, VTXO refresh, and wallet backup plans. Archived files keep their original names per the naming policy.

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

### Current State (July 9, 2026)

| Metric | Value | Health |
|--------|-------|--------|
| Total Files | 189 | 🔴 Growing (was 157 in May) |
| Root Files | 39 | ⚠️ Improving (53 → 39 since Jul 8) |
| Archived Files | 66 | ✅ Restructured into category folders |
| Phase/Fix Docs (active dirs) | ~4 | ✅ Nearly cleared (was ~35) |
| Stale-status plan docs | ~1 | ✅ Nearly cleared (was ~7; passkey plan remains — Step 15) |
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
| 2026-07-09 | Claude Code | Step 14 completed: verified all three plans shipped — Live Activity exits (2026-05-12), VTXO refresh ppm-free logic (2026-04-24), wallet backup (2026-05-07) — and archived them to Archive/Implementations/ with archive notes (root 42 → 39, Archive 63 → 66). Fixed 1 reference in DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED |
| 2026-07-09 | Claude Code | Step 13 completed: verified LNURL-pay shipped 2026-05-30 (Bark 0.11 now runs the flow natively via `payLnurl`, superseding the plan's app-side invoice handling), archived LNURL_PAY_IMPLEMENTATION_PLAN to Archive/Implementations/ (root 43 → 42, Archive 62 → 63), distilled current behavior into new `Features/LNURL_Pay.md`, updated 2 references in Bark 0.11.3 migration docs and the Archive index |
| 2026-07-09 | Claude Code | Steps 11–12 completed: archived READ_ONLY_MODE_IMPLEMENTATION_PLAN + MANUAL_PRIMARY_DEVICE_ASSIGNMENT to Archive/Implementations/ (root 45 → 43, Archive 60 → 62), distilled both into new `Features/Read_Only_Mode.md`, fixed 4 inbound references in 3 docs, updated Archive/readme.md index |
| 2026-07-08 | Claude Code | Steps 5–10 completed: restructured Archive/ into Migrations/Implementations/Fixes category folders (26 existing files sorted), then archived 33 files from FFI initial integration/ (dir removed), Movements/, Address history/, Initialization/, Contacts/ (dir removed), and Send/. Archive 27 → 60. ISSUE_1/2 kept pending code verification. Fixed 6 inbound references |
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
