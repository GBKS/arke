# Delete Everywhere: Two-Word Phrase Confirmation

**Status: DONE 2026-10-15 (Tier 0, Train 1, deletion cluster item 2).
Committed `b42d536` (code) + `daabaf8` (docs); device check passed the
same evening on Christoph's phone (§9.1). Direction DECIDED 2026-10-10,
flow and the five open calls DECIDED 2026-10-15 (§3), three tweak rounds
on copy and layout the same day (§4.4). Adversarial pass in §11: one
CONFIRMED finding (pre-existing, new trigger) and two PLAUSIBLE ones fixed
in-session; full mobile suite green on the iPhone 17 Pro simulator after
the fixes (9 new test cases). Left for the Device stage: the two-device
override route (§9, second paragraph).**

Backlog entry: `Open_Follow_Ups.md`, Decisions, "phrase confirmation on
full wipe", and the Current train block, deletion cluster. Area doc:
`Wallet_Deletion_And_Rejoin.md`; failure mode "Full wipe without a written
phrase" in `../Architecture/Multi_Device_Design.md` §A; contract rules 17–21
in `../Initialization/Launch_Sequence_Contract.md`.

## 1. Problem

The last-device full wipe deletes the synchronizable seed as its final step
(`WalletDataCleanupService.swift:359-380`). Afterwards only a phrase the user
wrote down can restore the wallet. Nothing on the path checks that such a
copy exists: the slider sheet asks for one gesture, and the override path
adds a toggle whose first half ("I have my recovery phrase written down") is
an unverified claim. The forfeit warning (2026-10-13) names the funds at
stake but cannot tell a user with no written phrase from one with it.

## 2. Trace (all **verified**, read 2026-10-15)

| Step | Where | What |
|---|---|---|
| 1 | `SettingsView_iOS.swift:496-500` | the delete screen is a pushed settings page (`DeleteWalletSettingView`, Shared) |
| 2 | `DeleteWalletSettingView.swift:145-188` | one "Delete wallet" button opens the slider sheet; the override button sets `overrideRequested` and opens the same sheet |
| 3 | `DeleteWalletSettingView.swift:202-226` | sheet presents `DeletePermanentlyConfirmationView(deletionStrategy:onConfirm:onBack:isOverride:blockers:)`; `onDismiss` re-runs the device check |
| 4 | `DeletePermanentlyConfirmationView.swift:33-35` | the slider is enabled unless deleting, or on override until the toggle is on; no phrase check anywhere |
| 5 | `WalletDataCleanupService.swift:149-159` | scope: `.promptForCloudData` → full wipe; `.localOnly` → full wipe only with `overrideConfirmed` |
| 6 | `WalletManager+Wallet.swift:19-36` | `getMnemonic()` reads the keychain through `SecurityService.loadMnemonic()`, no bark handle involved |
| 7 | `SecurityService.swift:604-630` | `loadMnemonic()` queries the synchronizable item; `nil` on `errSecItemNotFound`, throws on any other status |
| 8 | `SecurityService.swift:909-913` | `mnemonicKeychainStatus()` distinguishes `.found` / `.notFound` / `.unavailable(OSStatus)` |
| 9 | `DeleteWalletSettingView.swift:84-120` | the gold "manual backup" box asks about a backup with one copy for every strategy |

## 3. Decisions

- DECIDED 2026-10-10: two words by position on the final "Delete
  everything"; unconditional on the last-device full-wipe path, not gated
  on balance; local-only untouched; new strings + de/ja/zh-Hant; two-device
  verify with the deletion set.
- DECIDED 2026-10-15 (Christoph, one message):
  1. **Own screen, pushed.** The check is not squeezed into the slider sheet
     (full-screen art there). It is a dedicated view between the info
     screen and the slider sheet, pushed in the settings stack. The slider
     sheet stays as it is.
  2. **Info-screen copy is strategy-aware.** The gold box changes on the
     full-wipe path (§4.4); the local-only copy stays.
  3. **Keychain failure fails closed.** A transient read error shows an
     error with retry and never reaches the slider. A definitive
     `.notFound` skips the check: there is no seed left to protect.
  4. **Override keeps its toggle.** The words prove the written copy; the
     toggle's second half is consent to every device losing the wallet,
     which the words do not cover. Toggle text unchanged for now
     (copywriting is the Tier 3 deletion-copy line).
  5. **Random positions** per presentation, so a screenshot of the phrase
     screen does not pre-answer the check.

## 4. Design

### 4.1 `PhraseConfirmation` (Shared, pure, `nonisolated`)

One decision type next to `DeletionForfeitWarning`:

- `static func isRequired(strategy:overrideRequested:) -> Bool` — the same
  predicate as `WalletDataCleanupService.includesCloudData`, called with the
  view's inputs, so the screen appears exactly when the scope would be
  `.everywhere`. Not a new policy: it mirrors the existing one and a test
  pins the two in step.
- `struct Challenge { let positions: [Int]; let expected: [String] }` —
  built from the phrase: two distinct 1-based positions drawn with
  `SystemRandomNumberGenerator` from `1...wordCount`, ascending; the two
  expected words are kept, the rest of the phrase is dropped before the
  value leaves the factory. Word count comes from the phrase itself
  (`split(separator: " ")`), so 12 and 24 both work.
- `func matches(_ answers: [String]) -> Bool` — trims whitespace and
  newlines, lowercases, exact compare per position. No prefix matching, no
  BIP39 word-list lookup, no hint which word failed.
- An injectable generator parameter on the factory for tests only.

### 4.2 The new screen: `DeletePhraseConfirmationView` (Shared)

Plain settings style like the info screen (serif title, secondary body),
not the slider sheet's art. Content, top to bottom:

- Title "Confirm your recovery phrase".
- Body: deleting everything removes the phrase from this device and from
  iCloud Keychain; only a copy written down brings the wallet back; enter
  the two words to continue.
- Two single-line fields labelled "Word N" (positions from the challenge).
  iOS island: `textInputAutocapitalization(.never)`,
  `autocorrectionDisabled`, `keyboardType(.asciiCapable)`,
  `submitLabel(.next)` / `.done`. Both fields `privacySensitive()` is
  *not* added here (that is the Tier 0 screen-capture item's call; the
  typed words are two of twelve, and the item should decide the rule once
  for all phrase surfaces).
- One neutral mismatch line under the fields after a failed Continue:
  "That doesn't match your recovery phrase." Never which word.
- "Continue" button, red tint, disabled while either field is empty or the
  phrase is still loading. Tapping it runs `matches`; on success it opens
  the slider sheet from this screen with the inputs the info screen passes
  through today (`strategy`, `isOverride`, `blockers`, `onConfirm`,
  `onBack`).
- No "show recovery phrase" shortcut. Settings → Recovery phrase stays
  reachable, but not from here: a shortcut would turn the backup proof back
  into a tap.

State and lifecycle:

- `.task` loads the phrase via `walletManager.getMnemonic()` (keychain only,
  works on a read-only secondary taking the override route), builds the
  challenge, discards the full string. The two expected words live in
  `@State` for the life of the screen and are cleared in `onDisappear`.
- Load failure: `SecurityService.mnemonicKeychainStatus()` decides. `.found`
  but the read threw, or `.unavailable` → `ErrorBox` with the status, a
  Retry button (ArkéUI's `ErrorBox(onRetry:)`, key `button_retry`),
  Continue stays disabled (fail closed). `.notFound` → the fields are
  replaced by a one-line note that no recovery phrase is stored on this
  device and Continue is enabled without input; no auto-presentation (as
  built: a sheet appearing on push is jarring, and the note should be read
  first). Why the skip is safe: on this device there is nothing to check
  and nothing its own wipe could destroy — a wiped seed, or a secondary
  whose iCloud Keychain never delivered it (`seedNotSynced` state); in the
  second case the account copy is untouched by this device's local
  `SecItemDelete`. Blocking here would make the wallet undeletable.
- The slider sheet's `onDismiss` on this screen does what the info screen's
  does today (re-check devices) by calling back into the info screen; the
  scope-invalidated abort pops to the info screen with the error, since
  that is where the strategy and blockers are shown. Simplest form: the
  screen is a `navigationDestination(isPresented:)` on the info screen,
  the sheet presentation and `deleteWallet(strategy:overrideConfirmed:)`
  stay in the info screen, and the new screen only owns the challenge and
  calls `onPassed()` which flips `showingDeletionConfirmation`. Then
  nothing about the deletion call, the abort path or the override reset
  moves. **Built this way** (the alternative, sheet owned by the new
  screen, duplicates the abort handling). Override lifecycle as built: set
  explicitly on every button tap; kept while the phrase screen is up even
  if the slider sheet is cancelled (the user can slide again from there
  with the scope the sheet shows); dropped when the phrase screen pops
  without handing over to the sheet. The abort also had to stop
  `checkDevices()` from clearing `deleteError` (§11 finding 1).
- The info screen's button handlers: when `PhraseConfirmation.isRequired`
  is true, set `showingPhraseConfirmation = true` instead of
  `showingDeletionConfirmation = true`; the override button additionally
  sets `overrideRequested` as today. Local-only keeps the direct sheet.
- The pushed screen shares the info screen's `WalletManager` environment;
  no new dependency.

### 4.3 macOS island

The desktop settings pane embeds the delete view in a detail `ScrollView`
without a stack (`ArkeDesktop/Views/Settings/SettingsView.swift:289-295`),
so `navigationDestination` has nowhere to push. `#if os(macOS)` presents
the same screen as a `.sheet` instead. Both are then sheets on the same
view and SwiftUI presents one at a time, so on macOS `onPassed` sets the
slider flag first and closes the phrase sheet second; the override reset
on the phrase screen's close is guarded on the slider flag so a pass keeps
it (§11 finding 2). Desktop is parked: compile-only by virtue of Shared,
no desktop build or run in this item; whether the queued sheet appears
after the first closes is **assumed**, not executed.

### 4.4 Info-screen copy (revised 2026-10-15, tweaks round)

The gold "manual backup" box is gone (Christoph: it repeated the intro).
The intro paragraph carries the whole message, and the "Back up Wallet"
link sits under it as a plain gold link:

- Last device (new key `settings_delete_warning_everywhere_intro`; the old
  `settings_delete_warning_icloud` had manual translations, so the catalog
  kept its English value over a changed `defaultValue:` — verified in the
  catalog after the build — and goes stale instead): "This
  permanently deletes your wallet from this device and from iCloud,
  including the recovery phrase." then a paragraph break, "Only a copy you
  wrote down can bring it back, and the next step asks for two of its
  words. To restore your history as well, back up the wallet state file
  first." (Christoph 2026-10-15: "in your iCloud Keychain" dropped — users
  do not separate Keychain from iCloud, and the half that matters is that
  the phrase itself goes.)
- The forfeit warning lost its orange box (second tweak round): it is a
  row with the transaction icon's filled tile recipe (44 pt rounded
  square, orange at 0.15, orange triangle) and the text beside it.
- Phrase screen, same rounds: no placeholder in the fields, body "Enter
  words N and M to confirm you have it written down.", a mismatch fires
  the system error haptic (`sensoryFeedback(.error)`, counter-triggered)
  and refocuses the first field with the typed words kept. BIP39
  word-list checking per field was PROPOSED and declined (Christoph:
  a second verification mechanism is confusing).
- Local-only variants: unchanged, and **no backup sentence and no link**.
  Christoph asked whether "back up to keep this device's history" was
  accurate there; it was not: a local-only deletion writes its final state
  file to the iCloud backup slot itself (`Wallet_Deletion_Backup_Skip.md`
  §4.3, load-bearing for a later promotion) and the history rows are
  CloudKit-mirrored, so the remaining devices need nothing from this one.
- The link shows on the full-wipe path only: `.promptForCloudData`, or
  `.localOnly` while the override is offered (same rule as the forfeit
  warning), since the override route reaches the same wipe.

Buttons (same round): the info screen's button is a regular gold primary
button, centered "Continue", no chevron — it is not the final confirmation,
the slider sheet is. The override link stays plain red text. The phrase
screen's body is one sentence naming the two positions ("Enter words 4 and
9 of your recovery phrase to confirm you have it written down."), the
"Word N" labels are title-size semibold, and its button is the same gold
style labelled **"Verify"** (DECIDED 2026-10-15), falling back to
"Continue" in the no-phrase state where there is nothing to verify.

### 4.5 Strings

New keys, all `defaultValue:` at the call site (Shared view, no
`bundle: .module`):

| Key | Default |
|---|---|
| `settings_delete_phrase_title` | Confirm your recovery phrase |
| `settings_delete_phrase_body_positions %lld %lld` | Enter words %lld and %lld of your recovery phrase to confirm you have it written down. |
| `settings_delete_phrase_body` | Two words of your recovery phrase confirm you have it written down before it is removed. (loading and no-phrase states) |
| `settings_delete_phrase_word_label %lld` | Word %lld |
| `button_verify` | Verify |
| `settings_delete_phrase_mismatch` | That doesn't match your recovery phrase. |
| `settings_delete_phrase_unreadable` | Your recovery phrase couldn't be read right now, so the deletion can't continue. Try again in a moment. |
| `settings_delete_phrase_missing` | No recovery phrase is stored on this device, so there is nothing to confirm. |
| `settings_delete_warning_everywhere_intro` | the last-device intro (§4.4); replaces `settings_delete_warning_icloud`, which goes stale with its de/ja/zh-Hant |
| `settings_delete_backup_reminder` | orphaned with the box (and its three translations) |
| `button_continue` | Continue (no existing key; added; info-screen button and the phrase screen's no-phrase state) |
| `status_loading_recovery_phrase` | Loading recovery phrase... |
| `error_recovery_phrase_too_short` | The stored recovery phrase is incomplete. (defensive, a phrase under two words) |
| retry | ArkéUI `ErrorBox(onRetry:)`, existing key `button_retry` ("Retry"); no new key |

The word fields take the "Word N" string as their title, so no empty key
is extracted (the first build extracted `""` from `TextField("", …)`; the
rebuild dropped it, confirmed in the catalog).

Translations through `Scripts/apply_translations.py` +
`Scripts/translation_lint.py` after the build re-extracts the catalog; they
do not gate the item.

## 5. Claims the design rests on

- **verified** the full wipe deletes the synchronizable seed and it is the
  last destructive step (`WalletDataCleanupService.swift:359-380`).
- **verified** `getMnemonic()` needs no bark handle (trace step 6–7), so a
  read-only secondary on the override route can be checked.
- **verified** scope policy is `includesCloudData(strategy:overrideConfirmed:)`
  with exactly two inputs the info screen holds (trace step 5), so the
  "is required" predicate can mirror it without new plumbing.
- **verified** the keychain status enum has a definitive `.notFound`
  (trace step 8), which the fail-closed rule needs.
- **derived, not executed** the settings stack pushes
  `navigationDestination`s from the delete screen: the delete screen is
  itself a pushed destination (`SettingsView_iOS.swift:496-500`,
  `NavigationLink(destination:)` rows at `:68-263`) inside the typed-path
  `NavigationStack` in `WalletView_iOS.swift:146`, so a
  `navigationDestination(isPresented:)` on it should resolve in the same
  stack; and the slider `.sheet` should present from the covered info
  screen. A build proves compilation only (review 2026-10-15 corrected the
  earlier wording). Settled by §9 steps 1 and 3 — if the push fails, "Delete
  wallet" on a last device is a no-op, which the device step would show at
  once.
- **assumed** nothing about bark, CloudKit or keychain behaviour beyond the
  reads above; no bark call is involved.

## 6. Sweep — paths into a full wipe

| Site | Status |
|---|---|
| `DeleteWalletSettingView` "Delete wallet" button, strategy `.promptForCloudData` | covered (pushes the check) |
| `DeleteWalletSettingView` "Delete from the account anyway…" | covered (pushes the check with `overrideRequested`) |
| `DeleteWalletSettingView` "Delete wallet", strategy `.localOnly` | exempt — scope `.localOnly`, seed stays on the account |
| `WalletDataCleanupService.deleteWalletData` other callers | to grep at build time; the plan assumes the delete view is the only UI caller (the 2026-10-14 plan verified `WalletManager.deleteWallet()` has one caller) |
| Desktop `SettingsView.swift:291` | covered by the Shared view + macOS sheet island, not built |
| Debug/testing views that wipe (grep `deleteWalletData(` under `Views/Settings/Testing`) | list at build time; a debug-only caller stays exempt and is noted here |

## 7. Tests (`Tests/Shared/PhraseConfirmationTests.swift`, Swift Testing)

Decisions and failure modes, not the implementation:

- required for `.promptForCloudData` with and without override; required
  for `.localOnly` only with override; never required otherwise — and a
  test that `isRequired` equals `includesCloudData` on all four inputs.
- challenge from a 12-word and a 24-word phrase: two distinct positions in
  range, ascending; expected words are the ones at those positions; the
  challenge holds exactly two words.
- `matches`: exact words pass; case and surrounding whitespace are
  forgiven; a wrong word, swapped order, or an empty answer fail.
- a seeded generator yields different positions across two draws (random
  per presentation, decision 5).

No test for the keychain branches: they are a view-level `switch` on the
status enum, pinned by the device step. No test that restates the copy.

## 8. Review

Tier 0: fresh-context adversarial pass by `fault-class-reviewer` on the
commit range before the full mobile suite. Expected attention: path
asymmetry between the two full-wipe entry points, the `.notFound` skip
(must not be reachable from a transient error), state left in the pushed
screen after a pop, and the override reset on dismissal.

## 9. Device check (owed; the item is not done without it)

One phone, primary, wallet with a phrase:

1. Delete wallet → the gold box shows the full-wipe copy → "Delete wallet"
   pushes the phrase screen with two positions.
2. Wrong word → mismatch line, no sheet.
3. Right words → slider sheet; cancel it → back on the phrase screen; pop
   to the info screen → the device re-check runs.
4. Right words → slide → full wipe completes, onboarding.
5. Re-enter from a fresh install: positions differ from run 1.

Two-device set (Device stage): the override route from a secondary whose
blocker is a doubtful mirror entry asks for the words and the toggle;
local-only on a device with a healthy sibling never shows the screen.

### 9.1 Result (Christoph, 2026-10-15, one phone)

Passed on device after the commits: the push from the Delete wallet
screen, the mismatch refusal and the slider sheet on a match all behaved
("works great"). This settles §11 finding 3 (the iOS push-and-sheet
runtime) and the derived claim in §5. The two-device override route stays
on the Device-stage checklist.

## 10. Open

- The `.notFound` note's copy ("No recovery phrase is stored on this
  device, so there is nothing to confirm."): PROPOSED, Christoph to see it
  on device if the state ever arises; it is not reachable on a healthy
  primary.
- `privacySensitive()` on the two fields: deferred to the Tier 0
  screen-capture item, which decides for all phrase surfaces at once.
- Translations (de/ja/zh-Hant) for the nine new keys: next translation
  batch, not gating.

## 11. Review record (2026-10-15, `fault-class-reviewer`, same session, on the uncommitted diff)

1. **CONFIRMED, class 2 (and 5 for the plan's claim) — fixed.** The abort's
   error was erased: `deleteWallet` set `deleteError` and dismissed the
   sheet in one transaction, the sheet's `onDismiss` re-ran
   `checkDevices()`, whose first line was `deleteError = nil`. Pre-existing
   at HEAD; the pushed screen added a second trigger (the info screen's
   `.task` restarts on pop). Fix: `checkDevices()` no longer touches the
   error; `startDeletion(override:)` clears it when a new attempt begins.
   Ledger line 2026-10-15.
2. **PLAUSIBLE, class 4 (macOS) — fixed by reading, not executed.** Sibling
   sheets on one view: the phrase sheet's close reset the override before
   the queued slider appeared, so the override route would have run
   local-only (the sheet would still have shown local-only, so no wrong
   scope executes). Fix in §4.3. Desktop parked, unverified.
3. **PLAUSIBLE, class 4 (iOS runtime) — owed to the device step.** The
   push from a `NavigationLink(destination:)`-pushed view and the sheet
   presenting from the covered info screen were derived, not run. §9 steps
   1 and 3 settle it; the claim in §5 is relabelled.
4. **Class 5, trusted claims — corrected in this doc:** `.notFound` waits
   for Continue rather than auto-presenting (§4.2); status lines said "not
   built" after the build; `button_retry` not `button_try_again` (§4.5);
   the `.notFound` rationale now covers the seed-not-synced secondary
   (§4.2).
5. **Minor — fixed.** `TextField("", …)` extracted an empty catalog key; the
   field now takes the "Word N" string as its title. Focus is set once the
   fields exist, not during the load.

Reviewer's sibling sweep matched §6 and added: `deleteWalletData(` and
`deleteWallet(scope:)` each have exactly one caller (the delete view);
both keychain queries target the same item, so the status check after a
thrown read cannot disagree with it except when the item vanished in
between, in which case `.notFound` is true. Not verified by the reviewer:
iOS runtime behaviour above, macOS, the two-device override route from a
seed-not-synced secondary, and whether iCloud Keychain can return
`errSecItemNotFound` transiently for a synced item (the app already treats
it as definitive at launch; this change inherits that).
