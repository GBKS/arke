# DefaultValue Migration Plan

**Status: PLANNING — no migration work started yet.**

Migrate all localized string call sites so the English copy lives in code via
`defaultValue:`, making source code the single source of truth for the `en`
localization. This executes (and supersedes) the "opportunistic" adoption path in
`Localization_Guidelines.md` §Usage in Code as a deliberate, phased sweep.

---

## Why (recap)

- Xcode rewrites both `.xcstrings` catalogs on every build; hand-added `en` values
  have been emptied by re-extraction before. With `defaultValue:` the English is
  re-populated from code instead of lost.
- Past key-migration work sometimes created semantic keys **without** English copy
  ("ditched the English"), leaving raw keys to render in the UI. As of 2026-08-17 the
  Shared catalog has 56 keys with missing/empty `en` values (21 of them snake_case
  hybrid keys such as `button_unlink_all_devices`); ArkéUI has 2. This migration makes
  that failure mode structurally impossible for `en`.
- Reviewers see actual copy at call sites instead of cross-referencing the catalog.

## Scope (measured 2026-08-17)

| Class | Count | Notes |
|-------|-------|-------|
| `String(localized:)` without `defaultValue:` | ~632 | 726 total minus 94 already migrated |
| Bare `Text("snake_key")` | ~486 | `LocalizedStringKey` literal, value lives only in catalog |
| Other bare-key builders (`Button`/`Label`/`Toggle`/`TextField`/`navigationTitle`/`.alert`) | 224+ | Lower bound — grep didn't cover `.help()`, `.accessibilityLabel()`, `confirmationDialog`, `Section`, `Picker`, `ContentUnavailableView`, `LocalizedStringKey(...)` ternaries |
| Catalog keys missing `en` value | 56 Shared + 2 ArkéUI | Must author English fresh |
| Hardcoded English (never localized) | unknown | e.g. `LinkedDevicesView.swift:136` alert message, `StatusBadge` texts — Phase 0 audit will count |

Roughly **1,300+ call sites across ~160 files** in four roots: `Shared/`,
`ArkeMobile/`, `ArkeDesktop/`, and the `ArkéUI` package. Catalogs:
`Shared/Localizable.xcstrings` (954 keys) and
`ArkeUI/Sources/ArkéUI/Localizable.xcstrings` (208 keys, all lookups need
`bundle: .module`).

---

## Design Decisions

### D1 — Canonical call-site patterns

| Context | Pattern |
|---------|---------|
| Already `String(localized: "key")` | Add `defaultValue:` (mechanical) |
| Bare `Text("key")` / `Button("key")` / etc. | Wrap: `Text(String(localized: "key", defaultValue: "..."))` — the `String` overloads exist for all of these; the wrapped string is already localized so no double lookup |
| Interpolated hybrid keys (`"key %@"`) | `defaultValue:` with the interpolation inside it (already mandatory per guidelines) |
| `String(format:)` sources (`format_*` keys) | `defaultValue:` containing the literal specifier, e.g. `defaultValue: "Address #%lld"` |
| ArkéUI package | Same patterns + `bundle: .module` (unchanged requirement) |

Do **not** invent wrapper helpers/macros — Xcode's extractor only recognizes the
standard APIs, and a wrapper would silently stop extraction.

### D2 — Reused keys get one accessor, not N duplicated defaultValues

`button_cancel` appears at dozens of call sites. Duplicating
`defaultValue: "Cancel"` everywhere invites drift (two sites disagreeing on copy →
extraction conflict warnings, ambiguous source of truth). Rule:

- **1–2 call sites** → inline `defaultValue:` at each site (2-site keys are mostly
  iOS/macOS view pairs; copy must be identical — the audit script flags drift).
- **≥3 call sites** (113 keys per the Phase 0 audit, e.g. `button_cancel` ×22) → one
  static accessor in a per-module `L10n` namespace, e.g.

  ```swift
  enum L10n {
      static var buttonCancel: String {
          String(localized: "button_cancel", defaultValue: "Cancel")
      }
  }
  ```

  One in `Shared/` (needs target membership in both apps + widgets), one in `ArkéUI`
  (with `bundle: .module`, package-internal). Extraction picks up the single
  definition. Call sites use `Button(L10n.buttonCancel)`.

The accessor list is generated data: `Scripts/audit_output/multiuse_keys.md`, filter
sites ≥ 3.

### D3 — English copy is copied verbatim from the catalog

This is a **mechanical migration, not a copywriting pass**. Existing `en` values move
into code unchanged (Shared catalog is canonical where a key exists in both catalogs).
Copy improvements are a separate task. Exception: the 58 keys with missing `en` values
need English authored — flag each in the batch's PR/commit message for review.

### D4 — Plural-variation keys are a special class (verify in pilot)

Keys with `plural` variations (e.g. `tags_transaction_count`) keep their variations in
the catalog — `defaultValue:` only supplies the base value. **Pilot must verify** that
a build after adding `defaultValue:` preserves the catalog's variation dictionaries.
If extraction damages them, plural keys stay catalog-managed (bare key) and get listed
as explicit exceptions here.

### D5 — `shouldTranslate: false` keys stay as they are

`symbol_*`, `app_name`, and pure format strings (`"%@"`, `"—"`) are catalog
configuration, low-risk, and mostly the reason for the "56 missing values" count.
They are hygiene items (Phase 6), not defaultValue targets.

---

## Hard Rules (apply to every batch)

1. **Never migrate a call site without carrying the English copy.** A migrated site
   always has `defaultValue:` (or an `L10n` accessor). Creating/renaming a key with no
   English is the exact failure this migration exists to eliminate.
2. **After every batch: build, then `git diff` both `.xcstrings` files.** Confirm no
   `en` value was lost or changed unintentionally and missing values got filled from
   code. The catalog diff is the primary correctness check.
3. **Keep files internally consistent** — when touching a file, migrate all of its
   bare keys, don't leave a half-and-half file.
4. **Don't rename keys or restructure copy while migrating.** One concern per change.
5. **Opportunistic pickup:** hardcoded English encountered in a file being migrated
   gets localized (new semantic key + `defaultValue:`) as part of that batch.

## Per-Batch Procedure

1. Generate the batch work list from the Phase 0 audit script (key → `en` value →
   call sites).
2. Edit code: apply D1/D2 patterns, copying values verbatim (D3). New Shared files go
   through `XcodeWrite`, never plain filesystem writes (see Phase 1 findings).
3. Build **in Xcode** (`BuildProject`) — command-line `xcodebuild` does not merge
   extraction back into the catalog. If the batch adds desktop-only keys, also build
   the desktop scheme.
4. Inspect `git diff` of the affected `.xcstrings`: values preserved/filled, no
   unexplained deletions, no new extraction-conflict warnings in the build log.
5. `XcodeRefreshCodeIssuesInFile` on touched files (fast sanity), run the catalog
   guard test (Phase 1). Full test suites only at task end per the lean workflow.
6. Tick the batch in the Progress table below; commit per batch.

---

## Phases

### Phase 0 — Tooling & audit — DONE 2026-08-17
- [x] Audit script: `Scripts/localization_audit.py`, outputs in `Scripts/audit_output/`
      (`keys.json`, `worklists.md`, `multiuse_keys.md`, `problems.md`,
      `hardcoded_english.md`). Rerun after each batch to refresh work lists.
- [x] Hardcoded-English sweep: 88 heuristic candidates in 32 files
      (`hardcoded_english.md`); many are `#Preview`-only (tagged) — triage per batch
      (Rule 5). Preview-only literals are exempt from localization.
- [x] `L10n` accessor list = multi-use keys with ≥3 sites (113 keys), see refined D2.

**Phase 0 findings (2026-08-17):**
- True scope: **2,145 call sites**, 100 already migrated; 1,137 catalog keys, 1,087
  referenced. Interpolation-generated keys (`"%lld addresses"` style) are matched by
  the scanner via regex; 50 keys are unreferenced and nearly all already carry
  Xcode's `stale` mark — scanner and extractor agree.
- The "missing English" scare was mostly a false alarm: those keys are
  **plural-variation keys** whose English lives under `variations`, not `stringUnit`.
  Zero referenced snake_case keys actually lack English.
- **D4 de-risked by existing evidence:** `settings_devices_connected` and
  `button_unlink_all_devices` already have `defaultValue:` call sites AND intact
  plural variations in the catalog across many builds — extraction preserves
  variations. Pilot still confirms via diff.
- 31 referenced plural keys total; 0 value drift between Shared and ArkéUI catalogs.
- Oddity to triage in Phase 6: `%u confirmation%@` is unreferenced but not
  stale-marked (dynamically constructed?).

### Phase 1 — Guard test + pilot — DONE 2026-08-17
- [x] Guard test: `Tests/Shared/LocalizationCatalogTests.swift` (missing-English,
      cross-catalog drift, whitespace keys). Green on both catalogs.
- [x] Pilot: Linked Devices (`LinkedDevicesView.swift`, `LinkedDevicesView_iOS.swift`)
      fully migrated; `Shared/Helpers/L10n.swift` created with the pilot's 9 accessors.
- [x] D4 verified by diff: plural variations (`button_unlink_all_devices`,
      `settings_devices_connected`) survived extraction unchanged.

**Phase 1 findings (2026-08-17):**
- **Catalog extraction merges only on Xcode IDE builds.** Command-line `xcodebuild`
  compiles but does not rewrite the source `.xcstrings`. Per-batch procedure step 3
  must be an in-Xcode build (`BuildProject` MCP command), not `xcodebuild`.
- **Extraction is per-scheme.** A mobile build does not add keys whose only call
  sites are desktop files. New desktop-only keys (`alert_unlink_device_message`,
  `error_unlink_devices`) render correct English via `defaultValue:` meanwhile, and
  will land in the catalog on the next desktop IDE build. Batches touching
  desktop-only strings should end with a desktop build.
- **New Shared source files must be created via the Xcode tools** (`XcodeWrite`), not
  plain filesystem writes — ArkeDesktop's synchronized folder picks up loose files but
  ArkeMobile's membership list does not (`L10n.swift` initially failed to compile in
  ArkeMobile). `Tests/Shared/` picked up the new test file automatically.
- The verbatim-copy discipline works: the pilot's catalog diff was a single deletion
  (the orphaned, empty plain-English alert key) — zero value churn.
- Commented-out code still shows up in audit work lists (e.g. the disabled Menu block
  in `LinkedDevicesView_iOS.swift`) — ignore those entries; comments aren't extracted.
- Desktop badge copy changed "Full Wallet"/"Metadata Only" → "Primary"/"Secondary" by
  adopting the canonical `status_full_wallet`/`status_metadata_only` keys (D3:
  Shared catalog is canonical; desktop had hardcoded, never-localized English).

### Phase 2 — ArkéUI package — DONE 2026-08-17
- [x] 40 files migrated (37 by script, 6 by hand for special classes), all lookups
      carry `bundle: .module`.
- [x] `ArkeUI/Sources/ArkéUI/Helpers/L10n.swift` created (21 accessors, internal —
      no collision with the app-side `L10n`).
- [x] Deliberately left: 6 sanctioned plain-English interpolation keys (`%@ ago`,
      `%llu sat/vB`, `+%lld`, `Cannot use: %@`, `%lld confirmations`,
      `%lld transactions`) — promoting them to semantic keys is a rename, out of
      scope (Rule 4); revisit in Phase 6.

**Phase 2 findings (2026-08-17):**
- New tooling: `Scripts/migrate_defaultvalue.py` — mechanical batch migration
  (accessor collapse, defaultValue insertion, builder wrapping + bundle-arg cleanup).
  Use it for Phases 3–5; it skips plural/hybrid/ambiguous sites and reports them.
- Manual classes found: multiline `String(localized:` calls (already migrated,
  audit-visible only), `LocalizedStringKey`-typed params on private row views
  (converted to `String`), literal keys in static data arrays (`EmojiPickerGrid`),
  hybrid interpolated keys (key stays the literal `"key %@"` form, defaultValue
  carries the interpolation — preserves existing catalog entries).
- Package catalog showed **zero diff** after the build: every migrated key already
  had the identical value there. Open question (harmless either way): whether IDE
  builds extract into *package* catalogs at all — the first genuinely new package
  key will answer it; if it doesn't appear, add the entry manually.

### Phase 3 — Shared/ (largest root), one feature area per batch
- [ ] Balance (incl. Boarding/Offboarding/Refresh modals)
- [ ] Send
- [ ] Receive
- [ ] Contacts
- [ ] Activity + Tags
- [ ] Data
- [ ] Settings (incl. Fees, deletion flows, recovery phrase)
- [ ] Non-view sources (WalletManager, services, models — e.g.
      `TransactionModel+DisplayHelpers.swift` alone has 174 sites)

### Phase 4 — ArkeMobile/ (per feature area, same batching)
### Phase 5 — ArkeDesktop/ (per feature area, same batching)

### Phase 6 — Hygiene & wrap-up
- [ ] Author English for any remaining missing-value keys; `shouldTranslate: false`
      pass on symbols/format strings (D5).
- [ ] Consolidate duplicate-meaning key pairs found during migration (Rule 2):
      `accessibility_current_device_hint` / `accessibility_other_device_hint` have
      identical English and a pointless ternary in `LinkedDevicesView_iOS`.
- [ ] Purge stale catalog entries (Xcode editor, filter "Stale"; confirm no dynamic
      key construction first).
- [ ] Run the full guard test + both mobile test suites; on-device/simulator smoke of
      one screen per feature area for raw-key sightings.
- [ ] Update `Localization_Guidelines.md`: adoption path §3 becomes "migration
      complete — `defaultValue:` (or `L10n` accessor) is mandatory for all strings";
      fold in D2 and any D4 exceptions.
- [ ] Update `Open_Follow_Ups.md`.

---

## Risks / Watch Items

- **Extraction conflicts:** same key, different `defaultValue` at two sites → build
  warning + nondeterministic value. Mitigated by D2 accessors; watch build logs.
- **Plural variations** (D4) — unverified until the pilot.
- **`Text(String(...))` loses `LocalizedStringKey` niceties** (automatic locale-aware
  re-render on language change mid-session). Acceptable: app copy is static per
  launch; note if a live-language-switch feature ever lands.
- **xcstrings churn in diffs:** re-extraction re-sorts the file; batch commits keep
  catalog diffs reviewable.
- **Widgets/Live Activities** use the Shared catalog — include `ArkeWidgets` sources
  in the Phase 0 audit sweep.

## Progress

| Batch | Phase | Status | Notes |
|-------|-------|--------|-------|
| Audit tooling | 0 | done 2026-08-17 | `Scripts/localization_audit.py`; 2,145 sites measured (1,680 after noise filter) |
| Guard test | 1 | done 2026-08-17 | `LocalizationCatalogTests`, green |
| Linked Devices (pilot) | 1 | done 2026-08-17 | 136/1,680 sites migrated overall; D4 verified; desktop-only keys pending next desktop build |
| ArkéUI package | 2 | done 2026-08-17 | 333/1,654 sites migrated overall; script + manual pass; 6 plain-English keys deferred to Phase 6 |
