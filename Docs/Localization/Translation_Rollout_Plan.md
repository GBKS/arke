# Translation Rollout Plan — German, Japanese & Traditional Chinese

Adds `de` and `ja` (and later `zh-Hant`, see the section at the end) on top of
the completed defaultValue migration
(`Default_Value_Migration_Plan.md`). Volume: ~1,250 translatable strings per
language across `Shared/Localizable.xcstrings` (~1,085 keys) and the ArkéUI
package catalog (~208), plus 6 Info.plist permission strings.

Terminology and style are governed by `Translation_Glossary.md` — one meaning,
one term. Decisions locked: German uses **du**; balance names are **translated**
(Zahlungen/Erspartes, 支払い/貯蓄).

---

## Phase A — Readiness — DONE 2026-08-18

- [x] Glossary authored (`Translation_Glossary.md`); ⚠️-marked terms await
      native review, everything else decided.
- [x] `InfoPlist.xcstrings` created for ArkeMobile (camera, contacts, local
      network, nearby interaction ×2) and ArkeDesktop (contacts) — permission
      prompts were previously unlocalizable.
- [x] Positional-specifier pass: only `accessibility_video_item` needed fixing
      (now `Video %1$lld: %2$@`); all other multi-arg values were already
      positional. Interpolation-generated hybrid values stay non-positional by
      nature — translations reorder with `%1$`-syntax on their side.
- [x] Guard test extended (`LocalizationCatalogTests`): no empty translated
      values, and per-argument **specifier parity** against English — both sound
      mid-translation (missing entries are fine, they fall back to English).
- [x] Translator comments: deferred deliberately — key prefixes carry most
      context (`button_`/`label_`/`status_`); comments get added in code when a
      reviewer flags a genuinely ambiguous string (glossary Mechanics §6).

## Phase B — Add the languages — DONE 2026-08-18 (user, in Xcode)

knownRegions gained de/ja; the build also enriched the InfoPlist catalogs
(NFC usage description discovered; CFBundle*/copyright marked non-translatable).

## Phase C — Translation first pass — DONE 2026-08-18

- [x] **1,090 entries translated to both German and Japanese** (all translatable
      keys across all four catalogs), state `needs_review` throughout.
- [x] Process: 13 parallel glossary-bound drafting agents (one per feature
      family, batches in `Scripts/translation_batches/`), applied via
      `Scripts/apply_translations.py`, then an explicit review-corrections
      overlay (29 keys: Sie→du register violations, the BLE "advertising" ≠
      "Werbung" mistranslation, grammar/terminology fixes).
- [x] German plural variations authored where needed (incl. the
      `^[…](inflect: true)` keys); Japanese single-form with 件 counters.
- [x] Verified: Xcode build green; guard tests green (26 cases) — the
      specifier-parity check needed to learn `%#@name@` substitution tokens and
      to skip `shouldTranslate: false` entries (also mirrored in the new
      `Scripts/translation_lint.py`, which prints offenders the simulator test
      can't).
- [ ] **Native-speaker review before release** (the entire point of
      `needs_review`): all values are first-pass; the glossary's ⚠️ terms
      (Übertrag, Rechnung, Hauptgerät/Zweitgerät) deserve first attention.
      Xcode's catalog editor can filter by "Needs Review" per language;
      alternatively export `.xcloc` for an external reviewer.

## Phase D — Per-language QA

- [ ] Run each app with scheme App Language = de, then ja.
- [ ] German layout pass (+30% expansion): badges, fixed-width buttons,
      settings rows, alerts.
- [ ] Japanese typography pass: line breaking, mixed-script spacing.
- [ ] Guard test + full mobile suite; on-device smoke per feature area.

## Known limitations

- bark FFI error messages (`error.localizedDescription` passthroughs) remain
  English regardless of locale — mapping them to keys is a separate follow-up.
- App Store metadata (name, description, screenshots) is out of scope here.

## Progress

| Step | Status | Notes |
|---|---|---|
| Phase A | done 2026-08-18 | glossary, InfoPlist catalogs, specifier fix, guard rails |
| Phase B | done 2026-08-18 | languages added in Xcode (user) |
| Phase C | done 2026-08-18 | 1,090 entries × de+ja, needs_review; guard green; native review pending |
| Phase D | not started | per-language QA: App Language runs, German expansion layout pass, ja typography |
| zh-Hant | done 2026-08-23 | 1,088 entries, needs_review; see section below |
| Debt batch | done 2026-11-11 | 236 keys × de+ja+zh-Hant, needs_review; missing count 0; see "Debt batch" below |
| Review pass | done 2026-11-11 | 147 / 145 / 28 corrections (de / ja / zh-Hant); see "Consistency review pass" below |

---

## Traditional Chinese (zh-Hant) — added 2026-08-23

Motivated by a Hong Kong conference demo. Same pipeline as Phase C, one
language: glossary section added to `Translation_Glossary.md` (Taiwan
conventions — Apple's zh-Hant flavor; Hong Kong devices resolve to it via
locale fallback; plain 你 register mirroring the German du decision), 13
parallel glossary-bound drafting batches (the Phase C family grouping,
regenerated from the live catalogs since the originals were deleted), applied
via `apply_translations.py` (now language-generic), then a review-corrections
overlay (11 keys: transfer=轉移 not 轉帳 for balance moves, `label_change`
mistranslated as bitcoin change output, assign/undo terminology unification,
VTXO-refresh vs UI-refresh conflations).

Extra guard used this round: ICU `Hans-Hant` transform over all values — any
character that changes under it is simplified-character leakage (zero found).
A hand-curated "simplified-only characters" list had false positives (估, 備);
use the transform, not a list.

Open, mirroring de/ja:
- [ ] Native-speaker review (⚠️ glossary terms first: 聰 vs "sats", 復原片語
      vs community 助記詞, 付款請求, 轉入/轉出; plus the app-wide 拷貝/剪貼板
      vs 複製/剪貼簿 pair).
- [ ] zh-Hant typography QA (App Language = zh-Hant run; CJK/Latin spacing,
      line breaking) — fold into Phase D.
- [ ] `knownRegions` gains `"zh-Hant"` in Xcode (user — pbxproj is not edited
      by tooling while Xcode is open); catalog entries exist regardless.

## Translation debt (moved from the backlog 2026-11-10)

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

- [x] **Translation debt — 128 user-facing keys have no de or ja value,
  112 no zh-Hant — closed 2026-11-11** (moved down from Tier 1 and recounted 2026-10-09 over
  `Shared/Localizable.xcstrings`, 1,029 keys, 17 `shouldTranslate=false`
  excluded; plus one ArkéUI key, `accessibility_decimal_separator`, per
  language). Groups: deletion strings (`settings_delete_warning_*`,
  `settings_delete_override*`, `button_delete_*_anyway`,
  `error_delete_scope_changed`), `metadata_*` export/import, ~28 X-Ray
  `data_bg_*` plus `data_background_*` / `action_*_background_events`, the 5
  `ManualRefreshOutcome` keys (now extracted, `en` only), `rejoin_*` and
  `error_wallet_already_on_account`, `linked_devices_unsynced_*` +
  `settings_unsynced_devices`, `transaction_list_syncing_*`,
  `data_fiat_rates*`, `settings_currency*`, `fiat_approx*`, the fiat-entry
  `receive_*` / `send_switch_to_*` strings, and ~13 format-only keys
  (`%@ UTC`, `%llu sat/vB`, `Block %u`, `Round %u`, `Invoice #%lld`, …). All
  render English `defaultValue` (no raw keys) — cosmetic, the whole Phase 3
  debt in one number. `apply_translations.py` then `translation_lint.py`
  (the lint checks empty values and format specifiers, not missing
  languages, so it is not the counter).

### Debt batch — DONE 2026-11-11

Recounted on 2026-11-10: 222 Shared keys without de/ja (206 without zh-Hant)
plus 14 ArkéUI keys, grown by the server-selection, deletion, fiat-currency,
metadata-import, X-Ray background-activity and send-viability work since
October. Closed in one batch:

- 236 keys translated into de, ja and zh-Hant (the 14 keys that already had
  zh-Hant kept it), including `backup_file_section_description`, whose
  English changed meaning on 2026-10-26. Five glossary-bound drafting agents
  by feature family (server/onboarding, deletion/recovery, X-Ray + rates +
  plain-English format keys, fiat/send/receive/fees incl. ArkéUI, refresh
  outcomes + metadata); flagged placeholder ambiguities were checked against
  the call sites before applying.
- `Scripts/apply_translations.py` writer fixed to reproduce Xcode's catalog
  format (key order preserved, `" : "` separators, three-line empty objects,
  no trailing newline); the Shared diff is additive (`git diff --minimal`:
  3,907 insertions, 5 deletions — the three replaced "optional" values).
- Verified: `translation_lint.py` 0 issues; `LocalizationCatalogTests` 5/5
  green on the `Arke Tests` simulator; ICU `Hans-Hant` transform 0 hits
  (one 了解 normalised to 瞭解 to keep the guard at zero); missing count
  0 / 0 / 0 in both catalogs, recounted after an IDE build so re-extraction
  is known to leave the values in place.
- Same day: the German „aktualisieren" vs „erneuern" inconsistency in the
  older VTXO-refresh keys was fixed (ten values; `VTXODeveloperActionsView`
  repointed from the two-meaning `button_refresh` to `maintenance_refresh`),
  see the Done log. Not done: native-speaker review (all values
  `needs_review`) and Phase D QA. Terms
  the batch had to coin are listed in `Translation_Glossary.md` under
  "Terms added 2026-11-11", all ⚠️.
- Follow-up the same day: the 8 stale Shared entries were purged (none
  referenced in code, none constructed dynamically; an IDE build did not
  re-add them); translator `comment:` added at the eleven call sites the
  drafting agents flagged as ambiguous (`linked_devices_unsynced_device_registered %@`,
  `label_held_back` in both modules, `button_verify`, `metadata_import_exported`,
  `metadata_import_network_mismatch`, `data_bg_event_timer`,
  `server_sheet_by_second`, `Waiting`, `send_switch_to_fiat_entry`,
  `receive_switch_to_fiat_entry`), extracted into the catalogs on build; the
  two InfoPlist catalogs re-serialized once into Xcode's format.

### Consistency review pass — DONE 2026-11-11

One fresh-context reviewer per language read all 1,330 entries of every
catalog against the English and the glossary (meaning, glossary term, sibling
drift, grammar, specifiers, plurals/counters, spacing and punctuation). A
mechanical pre-scan (formal register, banned vocabulary, simplified
characters, CJK spacing) was clean beforehand. Results, applied through
`apply_translations.py` and re-verified (lint 0, `LocalizationCatalogTests`
green, ICU Hans-Hant 0 hits, build green):

| Language | Corrections | Meaning errors | Notable |
|---|---|---|---|
| de | 147 + 4 | 14 | `backup_file_not_selected` said „optional" (English: recommended, emergency recovery otherwise); `settings_make_secondary_step_3` named the wrong device; unlink rendered three ways; `Zahlungsguthaben` → `Zahlungen-Guthaben`; `label_change` was „Wechselgeld" for a Change button; `button_exit` was „Beenden" for the Ark exit |
| ja | 145 + 1 | ~20 | `label_change` おつり → 変更; `balance_refresh_in %@` read "refresh with X"; 確認 → 承認 for confirmations; ワード → 単語; 転送 → 移動 |
| zh-Hant | 28 + 1 | 3 | `backup_file_not_selected` 選填; `button_refresh` → 重新整理 (UI refresh at its only call site); `button_set_primary` said primary *device* for a contact address; forfeit strings restructured |

The ArkeDesktop `NSContactsUsageDescription` shares its key with ArkeMobile
but has different English; all three languages carried the Mobile text and
were rewritten by hand in the desktop catalog (the apply script writes a key
to every catalog that holds it). Terms the reviewers had to decide are in
`Translation_Glossary.md` under "Terms added 2026-11-11 (review pass)".
English-side findings (copy nits, concatenation keys, the
`balance_vtxos_expired_and_expiring` substitution gap) were fixed the same
day; write-up in the Done log under Localization. Per-language
`substitutions` are now a supported pattern: the guard test and the lint read
them for every language, not only English. Still not done: native-speaker sign-off (every
value stays `needs_review`) and the Phase D layout pass.

