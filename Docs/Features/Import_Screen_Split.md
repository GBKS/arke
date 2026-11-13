# Import: Phrase Screen and Backup-File Screen

**Status:** BUILT 2026-11-12, simulator-checked the same day (§13), full
mobile suite run noted in §13; **device check owed** (§10) before the backlog
entry is ticked. Design rulings DECIDED 2026-11-12 (Christoph, §6). Absorbs
the Tier 3 "First use" entries "Import — autocomplete for seed words" and
"Import — validate the phrase before handing it to bark" (relocated verbatim
in §12). Sibling plans: `Phrase_Entry_Autocomplete.md` (prefix arithmetic §3,
engine §6; declined for the verification screen), `BIP39.md` (pre-check
evidence), `Backup_Restore.md` (backup file semantics),
`Wallet_Deletion_Export_Step.md` (the file this screen imports).

## 1. What changes

The single `ImportWalletView_iOS` (phrase field, backup-file section, one
import button) becomes two onboarding steps:

1. **Recovery phrase screen.** A numbered word grid in the visual language
   of the settings phrase display (`MnemonicGrid` in
   `RecoveryPhraseSettingView`: two columns, numbered pills, monospaced).
   Each pill is a single-word field. Suggestions from two letters, space or
   Return commits a word, invalid words are marked after commit, the
   checksum is checked through bark's binding before the user can continue.
2. **Wallet backup file screen.** Selecting the file is the default action
   and the primary button. Restoring from the phrase alone is the emergency
   path (Second's guidance): a small Skip in the corner, behind a
   confirmation that says what is lost. The import call runs from this
   screen.

Below the view layer the import entry points are unchanged:
`WalletManager.importWallet(mnemonic:networkConfig:)` and
`importWalletWithBackup(mnemonic:backupFileURL:networkConfig:)` take the
phrase as a space-joined string as today. New below the view layer: the
checksum pre-check, a cached word list with prefix lookup, and one typed
error for the phrase/file mismatch.

## 2. Trace (all **verified** by reading, 2026-11-12)

| What | Where | State today |
|---|---|---|
| The screen | `ImportWalletView_iOS` | one multi-line `TextField(axis: .vertical)`, ASCII keyboard, no autocapitalization, no autocorrection, newline dismisses the keyboard; backup-file section with `fileImporter` (`.database`, `sqlite`); import button disabled only on an empty phrase; back and inputs disabled while importing |
| Flow | `OnboardingFlow_iOS`, `OnboardingState` | `.firstUse → .importWallet → .walletImported`; each case wires `onBack` / completion closures and the asymmetric slide transition |
| Settings phrase display | `MnemonicGrid` (Shared, `RecoveryPhraseSettingView`) | two `VStack` columns inside an `HStack`, each row a numbered pill: number in `.body` monospaced secondary, word `.body` monospaced, pill background `.background` with corner radius 100, column background `systemGray6`, corner radius 12 |
| Per-word field precedent | `DeletePhraseConfirmationView` (Shared) | single-line `TextField`s, `@FocusState` by index, `onSubmit` advances, `submitLabel` next / done |
| Pre-check | `SecurityService.isValidBIP39` | word count only; called by `validateMnemonic` inside `importWalletWithBackup` (format → `.invalidFormat`) |
| Binding | `Bark.validateMnemonic(mnemonic:) throws -> Bool` | top-level function in `Bark.swift`; returns `false` for a bad checksum and for an unknown word (`BIP39.md` "Open", verified 2026-10-09) |
| Word list | `EnglishWordListProvider().wordList` (BIP39 package) | computed property, rebuilds the 2048-element literal on every access; three callers, none cached |
| Dead validators | `BarkWalletFFI.validateMnemonic(_:)` (private, no callers), `BIP39Usage.validate` | both carry a checksum TODO |
| Backup restore | `WalletBackupService.restoreFromUserBackup` | checks the SQLite header only, then replaces the local database |
| Mismatch at open | bark `Wallet::open`, tag `bark-0.8.0` (`~/workspace/bark`, `git show bark-0.8.0:bark/src/lib.rs`) | `if properties.fingerprint != fingerprint { bail!("incorrect mnemonic") }` before any chain or server call; the app's `importWalletWithBackup` catch block rolls back the seed, the KVS hash and the handle |
| Error classification precedent | `WalletManager.isServerKeyMismatch` | text match on the bark error, mapped to `BarkErrorArke.backupBelongsToAnotherServer` |
| Clipboard precedent | `SendViewModel+Clipboard`, `ClipboardService.hasStrings()` | the paste affordance shows when the pasteboard has strings; content is read only on tap |
| Suggestion API | `textInputSuggestions` | macOS only (`Phrase_Entry_Autocomplete.md` §2); on iOS the strip is custom |
| Keyboard toolbar precedent | `ToolbarItemGroup(placement: .keyboard)` | eight sites |
| Import stays uncovered | `Recovery_Phrase_Exposure.md` | DECIDED 2026-10-29: import and delete confirmation are not covered by the privacy card |

## 3. Phrase screen

**Grid.** Twelve numbered pills in two columns, same proportions, fonts and
backgrounds as `MnemonicGrid` so the screen reads as "the phrase you wrote
down, now being typed back". Each pill holds a `TextField` instead of a
`Text`. A small text link under the grid, trailing ("Have a 24-word
phrase?" / "Back to 12 words"), switches between 12 and 24 pills (bark's
`importWallet` guard accepts exactly those counts); a segmented control
above the grid was built first and DECIDED against 2026-11-13 as too
prominent for the exception. The body reads "Enter your recovery phrase,
one word per field, in order." (DECIDED 2026-11-13). The custom-server note
from the old screen stays, under the title.

**Typing.**

- Input traits as today: ASCII keyboard, no autocapitalization, no
  autocorrection (which also keeps the system prediction bar off), no
  content type. Focus by index with `@FocusState`, first pill focused on
  appear.
- **Space and Return commit the word and move focus to the next pill.**
  Return on the last pill dismisses the keyboard. (A planned "backspace in
  an empty pill goes back one pill" rule was dropped at build time: SwiftUI
  exposes no delete-key event on a `TextField`; the user taps the pill.)
- **Space on a unique prefix completes it** (DECIDED): if the typed letters
  are a prefix of exactly one list word and are not themselves a whole list
  word, space fills the word. "cabi␣" → "cabin"; "act␣" stays "act" (a word
  of its own, also a prefix of action, actor, actress, actual); "cab␣"
  commits "cab" as typed and the invalid mark appears (three candidates, no
  completion). Return behaves the same as space here.
- **Suggestions from two letters, at most six, in the keyboard toolbar**
  (`ToolbarItemGroup(placement: .keyboard)`, horizontally scrolling chips in
  list order). Tapping a chip fills the word and advances. Nothing shows
  below two letters; the median candidate count after two letters is seven
  (`Phrase_Entry_Autocomplete.md` §3), after one letter it is 82.
- **Invalid mark on commit, not per keystroke.** A committed word not in
  the list gets a red outline on its pill (the house error colour, as on the
  deletion check's mismatch line) and the status line under the grid reads
  "Word 7 isn't in the recovery word list." Editing the pill clears the
  mark. Several invalid words name the first. The mark is derived from
  focus: while the pill is focused nothing is marked.
- **Status line and Continue.** The line under the grid shows progress
  ("7 of 12 words") while incomplete, the invalid-word message when one is
  marked, and the checksum message when all words are valid but the
  binding's `validateMnemonic` returns `false`: "Every word is in the list,
  but one is wrong or out of order. Check each word against your written
  phrase." No word is named for a checksum failure; none can be. Continue
  enables only when the count is complete, every word is in the list and
  the checksum passes.
- **Paste** is the system `PasteButton` (icon only, capsule, gold), drawn
  as an overlay at the trailing edge of pill 1 while the grid is empty and
  gone after the first letter (DECIDED 2026-11-13, replacing a header
  button). It enables itself only while the pasteboard holds text and never
  shows the paste-permission alert. The delivered string is split on
  anything that is not a letter, so numbering such as "1." or "1)", line
  breaks and commas all split cleanly, lowercased, and applied from pill 1;
  24 words switch the grid to 24. Fewer than 12 tokens or more than 24: the
  status line says "The clipboard doesn't hold a recovery phrase" and
  nothing is filled. Pasting into a pill with the system paste menu runs the same
  split when the pasted text holds more than one word: a whole 12- or
  24-word phrase fills the grid from pill 1 wherever it landed (simulator
  pass: a mid-grid insertion otherwise flipped the grid to 24 words), any
  other multi-word text fills the following pills up to the shown count.
- **Accessibility.** Each pill is labelled "Word 7 of 12"; the invalid state
  is in the field's accessibility value; chips are buttons; the status line
  is announced on change.

**The engine** (`Phrase_Entry_Autocomplete.md` §6, unchanged):
`nonisolated enum BIP39WordSuggestions` in Shared beside
`PhraseConfirmation`, with a cached `static let words`, `contains(_:)`,
`candidates(forPrefix:limit:)` and `uniqueCompletion(for:)`. It never
reports validity of a phrase, only list membership of a word; the checksum
stays with bark. The three existing list users adopt the cache
(`BIP39Usage`, `BarkWalletFFI+Mnemonic` generation) and the two dead
validators are deleted.

**The pre-check** (as built, simpler than first planned): `nonisolated enum
RecoveryPhraseInput` in `Shared/Helpers/` holds the supported counts (12 and
24, the FFI's own import guard), the paste tokenizer and
`isValidPhrase(words:)`, which calls the binding's top-level
`Bark.validateMnemonic(mnemonic:)` directly. `SecurityService.isValidBIP39`
delegates to it, so both `WalletManager` import paths refuse a bad checksum
or an unknown word before the seed is written (the window noted in
`BIP39.md` "Open"); the phrase screen calls the same function once every
shown pill holds a list word. Not added to `BarkWalletProtocol`: the binding
function is not a wallet method, and a mock conformance would have put a
weaker validator behind the same name.

## 4. Backup-file screen

- Title "Wallet Backup File"; body copy explains what the file adds and a
  second line what is lost without it. Directly under the text a glass
  button "Select Backup File" (document icon) opens the same
  `fileImporter`; once a file is chosen it becomes the file card with the
  checkmark and the name, still tappable to change the file. At the bottom
  a prominent "Import Wallet" button, disabled until a file is chosen
  (DECIDED 2026-11-13: one morphing primary button was built first and
  rejected, people would not read which action it currently was).
- **Skip** is a small text button in the top trailing corner with a 44 pt
  hit area. Tapping it opens an **alert** (not a `confirmationDialog`: on
  iPhone that rendered as a narrow popover without its Cancel button,
  simulator pass 2026-11-12): "Restore without the backup file? Your funds
  are recovered from the network, but your payment history and anything
  still in progress are not. If the file exists on another device or in
  Files, go back and choose it." Buttons: "Restore without file"
  (destructive role) and Cancel. Confirming runs the phrase-only import.
- Back returns to the phrase screen with the words kept; back and Skip are
  disabled while importing, as today.
- **Mismatch copy.** When bark refuses the restored database with
  "incorrect mnemonic", `BarkWalletFFI.importWallet` types it as
  `BarkWalletFFIError.mnemonicMismatch` (text match beside the existing
  `networkMismatch` detection), `importWalletWithBackup` maps that to
  `BarkErrorArke.backupBelongsToAnotherPhrase`, the rollback runs as today,
  and the screen shows "This backup file belongs to a different recovery
  phrase. Check the file, or go back and check the phrase." Any other
  failure keeps today's generic alert.

## 5. Flow wiring

`OnboardingState` gains `.importBackupFile`; `.importWallet` becomes the
phrase screen. The flow holds `@State private var importPhrase: [String]`
(cleared when the flow leaves the import branch or completes) and passes
it down; the file screen receives the joined phrase and `networkConfig`.
Transitions reuse the existing asymmetric slide. The phrase never reaches a
log line (the FFI already logs only the word count).

## 6. Rulings

DECIDED 2026-11-12 (Christoph):

1. Numbered grid, not a single field with committed chips.
2. The checksum pre-check through the binding is folded into this item.
3. Space on a unique prefix completes the word.
4. Backup file is the default path; phrase-only is a small Skip in the
   corner behind a confirmation. Visual treatment of the grid follows the
   settings phrase display. An explicit Paste button when the clipboard has
   strings.

Rulings on the first build (Christoph, 2026-11-13, all DECIDED): the 12/24
control becomes a link under the grid; Paste becomes the system paste
button in pill 1; the body reads "Enter your recovery phrase, one word per
field, in order."; the file screen gets a select button under the text and
a disabled Import Wallet at the bottom.

Second round of rulings (Christoph, 2026-11-13 after the device test, all
DECIDED): no progress counter; the link reads "Switch to 24 words" /
"Switch to 12 words" and sits flush left; the paste button is one control
size smaller (it nearly touched the pill's edges on the phone); the Done
button keeps the trailing edge of an empty keyboard bar; no automatic focus
on appear (the keyboard sliding up over an unread screen is too much).

Settled at build time (simulator passes 2026-11-12 and 2026-11-13):

- Suggestions sit in the keyboard toolbar beside a Done button, so the bar
  is never empty; chips scroll horizontally. Six chips maximum, list order.
- The "N of 12 words" counter disappears once the phrase is complete and
  valid rather than reading "12 of 12 words"; the enabled Continue button
  is the signal.
- The paste button is an overlay, not a row member: as a row member it made
  pill 1 taller than the right column. The system button ignores
  `controlSize` on iOS and renders 34 pt tall in a 38 pt pill (what
  Christoph saw on the phone), so it is scaled to 0.8 with a circle border
  shape, leaving about 5 pt above and below; the drawn shape is still a
  slightly wide capsule, the system's own. The chip strip and Done share one
  toolbar item and the strip has an explicit width (measured screen width
  minus Done and margins), because the keyboard bar sizes its item to
  content and an empty strip otherwise left Done centred; chips are gold
  and clip before Done; a chip that only repeats a complete word is not
  shown.
- Known cosmetic: the three-line checksum message pushes the link and
  Continue down while it shows; Continue is scroll content, not pinned.

## 7. Claims

- **verified**: everything in §2; bark's fingerprint check at tag
  `bark-0.8.0` and its error text; the binding's `validateMnemonic`
  signature (DerivedData checkout); the prefix statistics
  (`Phrase_Entry_Autocomplete.md` §3).
- **derived**: `autocorrectionDisabled(true)` keeps the QuickType bar off
  the pills; the bindings crate rev in the DerivedData checkout wraps bark
  0.8.0 (memory of the 0.26 bump, not re-read for this plan).
- **assumed** (check when built): a keyboard `ToolbarItemGroup` with no
  chips renders an empty bar rather than nothing; a `TextField` inside a
  pill scrolls into view under the keyboard without a `ScrollViewReader`;
  bark's "incorrect mnemonic" error text survives the FFI error wrapping
  unchanged (the server-key text does).

## 8. Sweep

| Surface | Covered / exempt |
|---|---|
| `ImportWalletView_iOS` | **covered**: replaced by the two screens |
| `OnboardingFlow_iOS` | **covered**: new state and phrase hand-off |
| `ActivityView_iOS` "Enter recovery phrase" sheet (read-only device, seed not synced) | **covered**, found by grep after the plan's sweep missed it (ledger 2026-11-12): `ImportWalletSheet_iOS` runs the same two steps inside the sheet |
| `importWalletWithBackup` | **covered**: pre-check wrapper, mismatch classification; rollback untouched |
| `importWallet(mnemonic:networkConfig:)` | **covered**: pre-check wrapper only |
| `SecurityService.isValidBIP39` | **covered**: body replaced by the wrapper; callers listed at build time |
| `BarkWalletFFI.validateMnemonic(_:)`, `BIP39Usage.validate` | **covered**: deleted (dead, checksum TODO) |
| `DeletePhraseConfirmationView` | **exempt because** autocomplete and list checking were declined there 2026-11-12 and 2026-10-15 |
| `ImportWalletView` (ArkeDesktop) | **exempt because** desktop is parked; gains nothing, keeps compiling against the protocol addition through `MockBarkWallet` and the FFI |
| `MnemonicGrid` | **exempt because** display only; the import grid copies its styling, it does not reuse the view (a `Text` pill and a `TextField` pill share nothing but numbers) |

## 9. Tests (decisions only, Swift Testing)

- Engine: `uniqueCompletion` for "cabi" → "cabin", nil for "cab", nil for
  "act", nil for "zo" (under two letters even when unique), nil for a
  non-prefix; `candidates` respects limit and order; cached list has 2048
  entries and equals the provider's list.
- Paste parsing: "1. abandon 2. ability …", newline-separated, double
  spaces, mixed case, 24 words → 24 tokens; 11 tokens → rejected; 25 →
  rejected.
- Pre-check: `MnemonicChecksumTests` pins bark's behaviour and, since
  2026-11-12, that `SecurityService.isValidBIP39` refuses a bad checksum, an
  unknown word and a fifteen-word phrase; `RecoveryPhraseInputTests` pins
  the same through the shared helper (fixtures are the BIP39 test vector,
  never the simulator wallet's phrase).
- Not unit-tested: the "incorrect mnemonic" text match in
  `BarkWalletFFI.importWallet` (the FFI catch block has no seam for a
  synthetic `Bark.Error`); it is covered by the device check with a backup
  file from another phrase (§10).
- No view test. Tier 3 closes on simulator screenshots: empty grid, two
  chips after "ca", completion after "cabi␣", invalid mark, checksum line,
  file screen, skip confirmation, mismatch alert.

## 10. Definition of done

Tier 3 "First use" by area, but the phrase path is seed handling, so done
includes one on-device import on signet, phrase only, with a valid phrase
and with one wrong word (expect the checksum line, no import). The backup
file import is exercised on the device with the file written by the
deletion export step. Two devices are not involved: nothing below the view
layer changes order or ownership. The simulator wallet's phrase is typed
into the grid only, never pasted from a tracked file.

## 11. Build steps

1. `BIP39WordSuggestions` + tests; adopt the cache in the two list users;
   delete the two dead validators.
2. Protocol method, mock conformance, `WalletManager.isValidRecoveryPhrase`,
   `SecurityService.isValidBIP39` body, mismatch error + classification,
   tests.
3. Phrase screen (grid, commit rules, chips, status line, paste), file
   screen (primary select, Skip + confirmation, mismatch copy), flow state.
   Strings via `defaultValue:`; translations ride the next batch.
4. Simulator screenshots on a layout simulator; session index notes.
5. Device check (§10). Backlog: tick and move the absorbed entries;
   `Phrase_Entry_Autocomplete.md` status paragraph and `BIP39.md` "Open"
   get a closing pointer; Rework Ledger if anything is revisited.

## 12. Absorbed backlog entries (relocated verbatim 2026-11-12)

- [ ] **Import — autocomplete for seed words** (`EnglishWordListProvider`).
  Christoph's intent (2026-11-12, not yet scheduled): first split the import
  screen into a recovery-phrase screen and a wallet-backup-file screen; the
  phrase screen then takes the suggestions. Engine design, prefix arithmetic
  and the cached-list note: `Features/Phrase_Entry_Autocomplete.md` §3, §6.
- [ ] **Import — validate the phrase before handing it to bark** (moved
  down from Tier 0 2026-10-09: `MnemonicChecksumTests` shows bark rejects a
  bad checksum or unknown word before any network I/O). Fix: call the
  binding's `validateMnemonic(mnemonic:)` in `SecurityService.isValidBIP39`
  (word count only today), show "phrase has a typo" before the import UI
  starts, delete the two dead checksum-TODO validators. Also closes the
  seed-written-before-bark-sees-it window. Detail: `Features/BIP39.md` "Open".

## 13. Verification record (2026-11-12)

- Build: Arke mobile, clean. Scoped suites `RecoveryPhraseInputTests` +
  `MnemonicChecksumTests`: 12 of 12 on the `Arke Tests` simulator. Full
  mobile suite: see the session note in `Open_Follow_Ups.md` / the commit
  message once it has run.
- Simulator (iPhone 17 layout simulator, screenshots in
  `~/workspace/Arke-sessions/screenshots/2026-11-12/`): empty grid with
  keyboard and Done bar; chips `cabbage cabin cable…` after "ca"; "cabi␣" →
  "cabin" and focus to pill 2; chip tap fills "cable"; twelve typed words →
  no status line, Continue enabled; 12 × "abandon" → red checksum line,
  Continue disabled; "abandonx" in pill 12 → red outline and "Word 12 isn't
  in the recovery word list."; 24-word grid keeps words 1–12; Paste with
  ordinary text on the clipboard → "The clipboard doesn't hold a recovery
  phrase."; file screen with Skip, body copy and "Select Backup File"; Skip
  alert with both buttons, Cancel returns; back from the file screen keeps
  the twelve words.
- Second round (2026-11-13, after the four rulings above): no segmented
  control, link under the grid switches 12 ↔ 24 and back with words kept;
  system paste button in pill 1, gone after the first letter, pills 1 and 7
  at the same y; chips gold, clipped before Done; typed phrase with a bad
  checksum → red line, Continue disabled; five backspaces plus "abandon␣"
  in pill 1 → valid phrase, Continue enabled; file screen with glass
  "Select Backup File" under the text, "Import Wallet" disabled at the
  bottom, Skip in the corner; the system document picker opens and cancels
  back to the unchanged screen.
- Device (2026-11-13, latest build, Christoph): signet wallet deleted on
  the last device, mainnet wallet imported with the 2026-11-10 export; log
  reviewed end to end, import path clean (restore, pre-check, open without
  migrations on the restored file, server check, primary registration).
  Covers the backup-file half of §10.
- Third round (2026-11-13, after the device notes): no keyboard and no focus
  on arrival; no counter line; "Switch to 24 words" flush left at the
  content margin, toggling to "Switch to 12 words" and back; paste circle
  inset about 5 pt inside pill 1, pills 1 and 7 aligned; Done at the
  trailing edge with and without chips; chips clipped before Done.
- Not checked in the simulator: Paste with a real phrase on the clipboard
  (the simulator pasteboard mirrors the Mac clipboard, which was in use),
  the file picker, the mismatch alert, any import. All owed to the device
  check (§10).

## 14. Findings filed, not built

- **Seed-only import against leftover data of another phrase.** The
  phrase-only path wipes and retries on `networkMismatch` but not on the
  new `mnemonicMismatch`; leftover wallet data created from another phrase
  on the same network fails the import with the generic configuration
  error. Wiping it would destroy offchain state the seed cannot reproduce,
  so the right behaviour needs a ruling. PROPOSED, Tier 3 "First use".
- **Third-party keyboards see the phrase.** Nothing stops a keyboard
  extension on any phrase-entry screen; the only lever is the app-wide
  `application(_:shouldAllowExtensionPointIdentifier:)` hook. PROPOSED,
  Tier 3 "First use".
