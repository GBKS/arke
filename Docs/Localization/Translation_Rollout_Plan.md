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
