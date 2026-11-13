# Autocomplete on the Phrase Verification Screen

**Status: DECLINED for the verification screen, DECIDED 2026-11-12
(Christoph, after the plan below). Nothing built. The arithmetic (§3), the
engine design (§6) and the sweep (§10) stay as the reference for the
import-screen item (Tier 3 First use, "Import — autocomplete for seed
words"), which Christoph intends to approach after splitting the import
screen into a recovery-phrase screen and a wallet-backup-file screen
(intent noted 2026-11-12, not scheduled). The verification entry is in
`Open_Follow_Ups_Done.md` under "Wallet Deletion & Device Registry".**
Planned the same day: `Import_Screen_Split.md` (rulings in its §6).

Why declined, in one paragraph: the four-letter rule already caps the
typing at four letters per word with the tail forgiven. A
single-candidate completion saves one or two keystrokes for the 31% of
words unique at three letters and shows nothing the rest of the time; any
list mode reintroduces the recognition menu that multiple choice was
declined for and the per-field validity signal declined 2026-10-15. The
only honest improvement left on that screen is copy telling the user four
letters are enough, which was offered and not taken up.

Backlog entry: `Open_Follow_Ups.md`, Tier 3 "Settings, devices, deletion",
"Autocomplete on the phrase verification screen". Sibling entry: Tier 3
"First use", "Import — autocomplete for seed words". Parent plans:
`Wallet_Deletion_Phrase_Confirmation.md` (§3 items 5–6: random positions,
four-letter rule, multiple choice declined; §4.4: per-field word-list
checking declined 2026-10-15), `Wallet_Deletion_Export_Step.md` §1 and §3.1.

## 1. The question

The two-word check exists to prove a **written copy** of the phrase, not
that the user recognises their words. Multiple choice was declined for
that reason. Autocomplete sits between the two: it eases typing, and it
turns part of the recall into recognition for anyone who remembers how a
word begins. The plan has to say how much recognition it buys back, and
whether that price is worth the typing it saves now that the four-letter
rule already accepts four letters per word.

## 2. Trace (all **verified**, read 2026-11-12)

| What | Where | State today |
|---|---|---|
| The screen | `DeletePhraseConfirmationView` (Shared) | two single-line `TextField`s labelled "Word N", `@FocusState` by index, iOS island sets no autocapitalization, no autocorrection, ASCII keyboard, `submitLabel` next / done; `onSubmit` moves focus or calls `continueTapped()` on the last field; `onChange` clears the mismatch line |
| The matcher | `PhraseConfirmation.Challenge.matches` → `wordMatches(answer:expected:)` | whole word or first four letters, after `normalize` (trim + lowercase); no word-list lookup, no hint which word failed |
| Mismatch path | `continueTapped()` | "That doesn't match your recovery phrase.", error haptic, focus back to the first field, typed words kept |
| Word list | `EnglishWordListProvider().wordList` (BIP39 package) | a **computed property that builds the 2048-element array literal on every access**; `BIP39Examples.englishWordList` is the Shared accessor, used only by `PhraseConfirmationTests.fourLettersIdentifyEveryWord` |
| Other list users | `BIP39Examples.validate`, `BarkWalletFFI.validateMnemonic`, `SecurityService.isValidBIP39` | the first two build the list per call and do `contains`; the third checks word count only |
| Import, iOS | `ImportWalletView_iOS` | one multi-line `TextField(axis: .vertical)` for the whole phrase, same input traits, newline → dismiss keyboard |
| Import, macOS | `ImportWalletView` (ArkeDesktop) | `TextEditor`, monospaced; desktop parked |
| SwiftUI suggestion API | `textInputSuggestions` / `textInputCompletion` | **macOS 15+ only, `@available(iOS, unavailable)`** (iPhoneOS 26 SDK swiftinterface) — on iOS the strip is custom |
| Keyboard toolbar precedent | `ToolbarItemGroup(placement: .keyboard)` | eight sites (notes, boarding, send flows, ArkéUI amount inputs) |
| Deployment targets | project, ArkéUI `Package.swift` | iOS 26.2, macOS 26.x, package `.iOS(.v26), .macOS(.v26)` |
| Tier 3 definition of done | `Release_Train.md` | simulator screenshot or RenderPreview; no device step |

## 3. The recognition arithmetic (**verified**, computed on the package's list 2026-11-12)

| Typed letters | Distinct prefixes | Candidates per prefix: mean / median / max | Words already unique |
|---|---|---|---|
| 1 | 25 | 82 / 76 / 250 ("s") | 0 |
| 2 | 200 | 10.2 / 7 / 48 ("re") | 34 |
| 3 | 1096 | 1.9 / 1 / 13 ("pro") | 638 (31%) |
| 4 | 2048 | 1 / 1 / 1 | 2048 |

Also: 103 words are shorter than four letters (match whole); 49 words are
a prefix of another word ("act" → action, actor, actress, actual); 442
words are exactly four letters.

What this says: a list after one letter is a browsing exercise (dozens to
250 entries) and pure recognition. After two letters the median list is
seven entries, still a menu to recognise from. After three letters the
median list is **one** entry, and the four-letter rule accepts after one
more keystroke, so a list saves at most one or two letters per word. The
typing the feature can save is small in every mode; the only mode that
adds nothing a menu offers is the one that never shows a menu.

## 4. Ruling 1 — how many letters before a suggestion (PROPOSED)

Options, named for the rulings below:

- **T1 / T2**: list suggestions from one or two letters. Rejected in the
  plan: T1 is a word-list browser; T2 shows a median of seven and up to 48
  candidates to pick from, which is multiple choice with a longer menu.
- **T3**: list from three letters, up to about six chips. Saves one or two
  letters per word. Exposes the "not a word" signal (see §7) and still
  presents a menu for 42% of three-letter prefixes.
- **U, single-candidate completion** (recommended): show a completion
  **only when the typed letters match exactly one word of the list and the
  typed text is not already that whole word**. Never a list. Below three
  letters nothing appears regardless of uniqueness (the 34 two-letter
  singletons are excluded so the rule is "from three letters" in every
  case and easy to state). This is the one mode in which the screen offers
  no menu to recognise from: the user has to produce at least three correct
  letters of a word at a random position before anything is shown, which
  is already most of what the four-letter rule asks. What it buys is the
  answer to "have I typed enough, and is this the word" without a hint
  mechanism.
- **None**: keep the screen as it is; the four-letter rule already made the
  typing cheap. The recommendation in §1.2 (e) of the export-step plan was
  against building; this plan keeps that as a live option, with U as the
  build if Christoph wants one.

## 5. Ruling 2 — presentation on `DeletePhraseConfirmationView` (PROPOSED)

Depends on ruling 1. For **U** (one candidate, never a list):

- **Ghost text inside the field** (recommended): the untyped remainder of
  the word drawn in secondary colour after the typed letters, the iOS
  inline-prediction idiom. No layout shift, no empty strip, nothing
  outside the field the user is already looking at. Built as an overlay
  aligned leading in the field's padding: an invisible `Text` of the typed
  text followed by the visible suffix in the same `.title3` font; the two
  words are at most eight letters and the field never scrolls. **Accept
  with the Return key** (Next on the first field, Done on the second) or by
  tapping the field's trailing half. Accepting fills the whole word, then
  does what Return does today: moves focus to the next field, or on the
  last field dismisses the keyboard and runs the check. With no completion
  shown, Return behaves exactly as today. VoiceOver: the field's
  accessibility value gains "suggested: cabin" and a hint "double-tap or
  return to accept" (localized strings, two new keys).
- Alternative, one chip under the active field: a reserved one-line row so
  nothing shifts; the chip appears when a completion exists. Costs a line
  under each field or a jump when focus moves.
- Alternative, keyboard toolbar (`ToolbarItemGroup(placement: .keyboard)`,
  house precedent): no layout cost on the page, but the bar shows an empty
  strip whenever no completion exists (**assumed**, not checked) and puts
  the suggestion away from the field.

For **T3** (a list): the keyboard toolbar with a horizontally scrolling
chip row is the only place that holds up to six chips without reflowing
the page; tapping a chip fills the word and advances focus as above. Ghost
text cannot show a list.

Tap-to-complete only (no visible suggestion, Return silently expands) is
rejected: an invisible feature is not discoverable and surprises on the
mismatch path.

Platform islands: the ghost-text overlay and Return handling are plain
SwiftUI and compile into the macOS sheet presentation unchanged
(compile-only; desktop parked). The macOS-native `textInputSuggestions`
is not used anywhere in this item.

## 6. Ruling 3 — sharing with the import screen (PROPOSED)

The two screens differ in input model and in intent:

| | Verification | Import |
|---|---|---|
| Field | one word per field | one whole-phrase field; the active token is the last word |
| Intent | must not prove less than today | wants help, including "that is not a word" |
| Suggestions | U: one completion, never a list | list from one or two letters, scrolling chips, plus the validity cue the Tier 3 validate-before-bark item adds |

Recommendation: **share the engine, not the view.**

- New pure type in Shared next to `PhraseConfirmation`:
  `nonisolated enum BIP39WordSuggestions` with a **cached** `static let
  words: [String]` (the provider's `wordList` rebuilds its array literal on
  every access, so the three existing validators pay 2048 allocations per
  call; the cache is also the single list source for future adopters),
  `static func candidates(forPrefix:limit:) -> [String]` (normalized with
  `PhraseConfirmation.normalize`, empty below a caller-supplied minimum
  length), and `static func uniqueCompletion(for:minimumLetters:) ->
  String?` (nil unless exactly one candidate and the typed text is shorter
  than it). The verification screen calls only the second; the import item
  calls the first.
- It lives in **Shared**, not ArkéUI: it imports the BIP39 package, which
  ArkéUI does not depend on (`ArkeUI/Package.swift`), and a 2048-word list
  is not a previewable value model. No chip component goes into ArkéUI in
  this item: under U there is no chip; a chip strip is designed when the
  import item is built, and that item's backlog line gets a pointer to the
  engine.
- The import item itself is **not built in this session** (one issue per
  session). Its line in Tier 3 "First use" gains "engine:
  `BIP39WordSuggestions.candidates`" once the engine exists.
- The 2026-10-15 ruling (per-field word-list checking declined as a
  second verification mechanism) is honoured by construction: the engine
  never reports validity, only completions; the screen never colours a
  field or marks a word valid or invalid; `matches` is untouched.

## 7. Ruling 4 — the mismatch path and text that matches no word (PROPOSED)

Unchanged: Verify runs `matches`, a failure shows the one neutral line,
fires the error haptic, refocuses the first field, keeps the typed words,
and never says which word failed. Autocomplete adds no second path.

What typing a non-word looks like under each mode:

- **U**: nothing appears. Nothing also appears for a valid prefix with
  several candidates ("cab": cabbage, cabin, cable), for a complete word
  ("zoo", "act"), and for anything under three letters. The absence of a
  completion is therefore **not** a "not a word" oracle; it is ambiguous
  by design, and the four-letter rule still accepts "cabi" even if the
  user never sees the completion. No new copy, no new state.
- **T3**: an empty chip row after three letters is readable as "no such
  word", a per-field validity signal of exactly the kind declined on
  2026-10-15. If T3 is chosen anyway, the row stays silent (no "no
  matches" text) and the mismatch line still names nothing.

Accepting a completion that is wrong for the position (the user typed
"cabi", the phrase says "cable" at that position) is a plain mismatch at
Verify, same as today; the completion is never checked against the
expected word before Verify, or the screen would be a hint machine.

## 8. Rulings (2026-11-12)

Asked whether the feature was a worthwhile user benefit on this screen,
the answer was no (Status paragraph above). Christoph: **"let's decline it
here."** DECIDED 2026-11-12. Rulings 1–4 are therefore moot for the
verification screen; §5 and §7 are kept as the record of what was
considered. Follow-on ruling in the same exchange: asked what the
"four-letters copy line" was, Christoph judged the unannounced four-letter
rule itself the problem ("weird to have this hidden functionality and it
might feel broken") and had it **removed**: `PhraseConfirmation.matches`
is an exact compare again, `wordMatches`, `identifyingPrefixLength`, the
uniqueness premise test and the `BIP39Examples.englishWordList` accessor
are deleted, one test pins that partial words fail. §3's arithmetic is
unaffected and still serves the import item. For the import screen, §6's engine and the T2-style list with
a validity cue are the starting point, and rulings on threshold and
presentation are owed when that item is planned.

## 9. Claims the design rests on

- **verified**: `textInputSuggestions` is unavailable on iOS (SDK
  swiftinterface); the prefix statistics in §3; `wordList` is a computed
  array literal; the screen's structure, focus and submit handling; the
  four-letter rule and its premise test; deployment targets; Tier 3
  definition of done.
- **derived**: `autocorrectionDisabled(true)` (already on both fields)
  keeps the system QuickType predictions off these fields, so the ghost
  text does not compete with a system suggestion bar; from UIKit's
  autocorrection trait semantics, not executed here.
- **assumed** (to check in the simulator when built): the overlay's ghost
  text aligns with the typed text at `.title3` across Dynamic Type sizes
  and in the four themes; an empty keyboard `ToolbarItemGroup` renders an
  empty bar (only matters if that presentation is chosen).

## 10. Sweep — every phrase-entry surface

| Surface | Covered / exempt |
|---|---|
| `DeletePhraseConfirmationView` (Shared, iOS push + macOS sheet) | **covered**: the change |
| `ImportWalletView_iOS` whole-phrase field | **exempt because** it has its own Tier 3 item and a different input model; gains the engine pointer |
| `ImportWalletView` (ArkeDesktop, `TextEditor`) | **exempt because** desktop is parked; the native macOS `textInputSuggestions` is the obvious later fit |
| `RecoveryPhraseSettingView`, `ManualBackupView_iOS`, `ScratchableMnemonicGrid_iOS`, `WalletCreatedView_iOS`, `WalletImportedView_iOS` | **exempt because** display only, no entry (grep of mnemonic / recovery-phrase views, 2026-11-12) |
| `BIP39Examples.validate`, `BarkWalletFFI.validateMnemonic`, `SecurityService.isValidBIP39` | **exempt because** validators, not entry; noted as later adopters of the cached list, not touched here |

## 11. Tests (decisions only, `Tests/Shared/`, Swift Testing)

- `uniqueCompletion` returns the word for a unique prefix of three or more
  letters ("sket" → "sketch", "cabi" → "cabin"), nil for a prefix with
  several candidates ("cab"), nil under three letters even when unique
  ("oz"), nil for a complete word ("zoo", "act"), nil for a non-prefix
  ("xq"); normalization matches `PhraseConfirmation.normalize` ("  Cabi "
  → "cabin"). Pins ruling 1.
- `candidates(forPrefix:limit:)` respects the limit and the minimum
  length, returns the list order, and is empty for a non-prefix. Pins the
  engine the import item will consume.
- The cached list has 2048 entries and equals the provider's list, so the
  cache cannot drift from the package on a bump.
- No view test: Tier 3 is closed by a simulator screenshot (ghost text
  visible for "cabi", nothing for "cab", mismatch line after a wrong
  accepted completion), logged in the session index.

## 12. Build steps (after the rulings)

1. `BIP39WordSuggestions` in `Shared/Views/Settings/` beside
   `PhraseConfirmation.swift` (or `Shared/Helpers/` if the import item is
   expected soon; Christoph's call, default beside the matcher).
2. `DeletePhraseConfirmationView`: per-field completion state derived from
   `answers[index]`, ghost overlay, Return and tap acceptance, VoiceOver
   value and hint, two new strings via `defaultValue:`.
3. Tests above; scoped suite, then the full mobile suite once.
4. Simulator screenshots on a layout simulator (not the wallet one; the
   screen is reachable only through the deletion flow, so the skip-wallet
   or a throwaway wallet path is used and the backup screen stays closed).
5. Backlog: tick and move the entry; add the engine pointer to the import
   item; translations ride the next batch.
