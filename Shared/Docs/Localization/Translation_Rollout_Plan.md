# Translation Rollout Plan — German & Japanese

Adds `de` and `ja` on top of the completed defaultValue migration
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

## Phase B — Add the languages (mechanical, in Xcode)

- [ ] Catalog editor: add German and Japanese to `Shared/Localizable.xcstrings`,
      the ArkéUI package catalog, and both `InfoPlist.xcstrings`.
- [ ] Build once; commit the seeded catalogs (every key state "new").

## Phase C — Translation

- [ ] First pass per language, glossary-driven, in batches by feature area
      (state `needs_review`), verifying after each batch: build → guard test →
      catalog diff review. AI first pass is acceptable to bootstrap;
      **native-speaker review is required before release** — this app moves money.
- [ ] Plural variations authored for German where English uses
      `^[…](inflect: true)`; Japanese collapses all plurals to one form.
- [ ] Optionally: Xcode export (`.xcloc`) → external reviewer → import, which
      preserves review state.

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
| Phase B | not started | |
