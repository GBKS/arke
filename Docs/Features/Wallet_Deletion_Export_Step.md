# Delete Everywhere: Export Step and the Four-Letter Rule

**Status: DONE 2026-11-12 (Tier 2 export step, Tier 3 four-letter rule, the
latter REMOVED 2026-11-12 (Christoph, same day: an unannounced shortcut reads as a broken check when a partial word is accepted; whole-word matching restored, `Phrase_Entry_Autocomplete.md` §8);
both DECIDED by Christoph 2026-11-12 in one message, multiple choice for
the two words declined the same message). One-phone device check passed
the same afternoon (§8.1, "works well"); the two-device half stays on the
deletion set's Device-stage checklist. Fourth round the same day: metadata
row hidden when nothing user-added exists (§11, DECIDED and built),
autocomplete on the verification screen DECIDED for its own session, then declined there (2026-11-12, `Phrase_Entry_Autocomplete.md`). Adversarial
pass in §9: one CONFIRMED finding fixed in-session (newest-wins between the
local file and the iCloud slot), one PLAUSIBLE closed defensively (nested
flag reset), the rest owed to the device step. Scoped suites 17/17; full
mobile suite 657/657 (§10). Uncommitted.**

Backlog entry: `Open_Follow_Ups.md`, Tier 2 "Other on-device looks",
"Deletion export step + four-letter rule". Sibling plan:
`Wallet_Deletion_Phrase_Confirmation.md` (the two-word check this builds
on; its §3 and §4 carry the 2026-11-12 amendments). Area doc:
`Wallet_Deletion_And_Rejoin.md`; contract rules 17–21 in
`../Initialization/Launch_Sequence_Contract.md`.

## 1. The two questions (Christoph, 2026-11-12)

1. Make the two-word check multiple choice, three options per word?
   **Declined.** Nine combinations with unlimited retries is enumerable in
   at most nine taps; and recognition is not possession: a user who saw the
   phrase screen last week recognises the words without a written copy,
   which is who the gate is for. Keeping typed input and easing the typing
   instead: **the first four letters of each word are accepted** (every
   word of the BIP39 English list is unique in its first four letters, so a
   guess gains nothing and a typo after the fourth letter is forgiven).
   The 2026-10-15 ruling against per-field word-list checking stands; the
   prefix rule is invisible to the user and is not a second mechanism.
   **Reversed the same day:** the invisibility is the problem; a user who
   sees four letters accepted wonders why the check passed. Whole-word
   matching is back (`Phrase_Entry_Autocomplete.md` §8).
2. A screen in the flow to download the backup file, instead of the "Back
   up Wallet" link into the three-page manual backup section and back?
   **Yes**, as an optional step before the phrase check, exporting the
   **live database** rather than the iCloud slot copy, plus the contacts &
   metadata export, since the manual backup page says the phrase alone does
   not restore everything.

### 1.1 Second round (Christoph, 2026-11-12, after the first screenshots)

DECIDED, all four: (a) the intro's second paragraph becomes a **three-step
list** (save the wallet backup file, confirm two words, slide to delete)
with a **divider** before the forfeit row; (b) **recovery framing**: the
normal restore is phrase **plus** wallet backup file, the phrase alone is
the emergency path (the server can import from seed only), so the file is
"wallet backup file", not "wallet state file", the backup row is
*recommended* and the metadata row *optional*, "Both are optional" is
gone, and Continue reads **"Continue without backup file"** until the
backup row is ticked (no gate: the tick cannot prove where the file went);
(c) the **tab bar is hidden** from the export step onward and stays on the
Delete wallet page; (d) the slider stays a **sheet** (the commitment looks
different from the navigation before it), and the swipe-down-during-wipe
question was traced (§9.1). Open question from the same message, metadata
row only when there is data: PROPOSED in §11.

### 1.2 Third round (Christoph, 2026-11-12, second screenshots)

DECIDED: (a) the step list at the intro's size (title3, 28 pt numbers);
(b) third step **"Delete permanently"**, the sheet's own title, not the
gesture; (c) the **wallet backup file is required**: Continue is disabled
until the backup row reports a completed share; fail-open when there is nothing to export
(the row's failure line shows and Continue is enabled, or the wallet would
be undeletable). Christoph noted an alternative, a Skip in the corner with
its own confirmation, not built; (d) the body shrinks to two sentences and
the rows carry the specifics ("Needed to restore the wallet with your
recovery phrase" / "Optional. Contacts, tags, notes, and profile.");
(e) **autocomplete on the verification screen filed** as a Tier 3 item
(Settings, devices, deletion) with the recommendation against; never
decided before, distinct from the 2026-10-15 ruling on per-field
word-list checking and from the Tier 3 import-screen autocomplete item.
Declined the same day after the plan (`Phrase_Entry_Autocomplete.md`).

## 2. Trace (all **verified**, read 2026-11-12)

| Step | Where | What |
|---|---|---|
| 1 | `DeleteWalletSettingView.startDeletion(override:)` | full wipe (`PhraseConfirmation.isRequired`) opened the phrase screen; local-only opens the slider sheet directly |
| 2 | `DeleteWalletSettingView` intro, full-wipe path | gold "Back up Wallet" link pushed `ManualBackupView_iOS` (three sub-pages); the user walked back by hand |
| 3 | `BackupStatusSectionView_iOS.exportBackupFile()` → `WalletBackupService.getShareableBackupFileURL()` | the Download button copies `existingBackupFile`, i.e. the **iCloud Drive slot**, never the local `db.sqlite`; disabled when the slot is empty (iCloud Drive off: nothing to download) |
| 4 | `WalletBackupService.performBackup()` | plain `copyItem` of the live file into the slot; needs the ubiquity container |
| 5 | `BarkWalletFFI.backupWallet()` | refused while `opportunisticBackupsSuspended` (contract rule 17), which `deleteWallet` sets only after the slider |
| 6 | `MetadataBackupSectionView.exportMetadata()` | `MetadataExportService.writeTemporaryExportFile(context:)` + `ShareHelper.share` |
| 7 | `ShareHelper.share` | `completionWithItemsHandler` ignored the `completed` flag |
| 8 | `PhraseConfirmation.Challenge.matches` | exact compare per position after trim + lowercase |
| 9 | `WalletManager.closeWalletForMigration` / restore path | a demoted device keeps its `db.sqlite`; the launch restore replaces the local file when the slot is newer (newest-wins) — found by the review, §9 F1 |

## 3. Design

### 3.1 Four-letter rule (`PhraseConfirmation`) — removed the same day

*History; `matches` is an exact compare again and `wordMatches`,
`identifyingPrefixLength` and the premise test are gone.*

`wordMatches(answer:expected:)`: whole-word equality, or both at least
`identifyingPrefixLength` (4) letters and equal in their first four. Words
shorter than four letters match whole. A test pins the premise against the
BIP39 package's English list (2048 words, 2048 distinct four-letter
prefixes), so the rule cannot outlive the word list silently. The screen,
copy and mismatch handling are unchanged; the rule is not announced.

### 3.2 Export step (`DeleteExportStepView`, Shared)

Pushed by `startDeletion` in place of the phrase screen on the full-wipe
path (same predicate as before: `.promptForCloudData`, or `.localOnly`
with the override). Plain settings style like its neighbours:

- Title "Take your data with you"; body (§1.2): "Deleting everything also
  removes the wallet's iCloud backup. Save your own copy first."
- Two rows with the manual backup page's icon tiles: **Wallet backup file**
  ("Needed to restore the wallet with your recovery phrase") and
  **Contacts & Metadata** ("Optional. Contacts, tags, notes, and
  profile."). Each has a glass **Download** button that becomes a green
  **Saved** tick when the share sheet reports a completed activity; it
  stays tappable for a second copy. A failure shows one red line under the
  row.
- Gold **Continue** pushes the phrase screen. **Disabled** until the backup
  row is `.saved` or `.failed` (`canContinue`), no caption under it
  (Christoph, fourth tweak: the body and the Download button say what is
  missing, and the screen needs attention anyway). `.failed` enables it: no local
  database and no slot file, or a copy failure, means nothing to save and
  the wallet must stay deletable (same fail-open shape as the phrase
  screen's `.missing` keychain state). The metadata row never gates.
- The tab bar is hidden on this screen and the phrase screen
  (`.toolbar(.hidden, for: .tabBar)`); the Delete wallet page keeps it.

Wallet file source (`WalletBackupService.getShareableWalletFileURL()`,
static `shareableWalletFileURL()` for callers without a handle): the
**newer** of the local `db.sqlite` and the iCloud slot file by modification
date, local on a tie or an unreadable date, whichever exists when only one
does, nil when neither. Rationale per case: an open primary's live file
postdates the slot by up to one payment and needs no iCloud; a demoted
device's file is frozen at demotion while the promoted device keeps
writing the slot (§9 F1); a never-opened secondary has only the slot;
iCloud Drive off with no local file yields the "No wallet state file"
line. Same plain copy as the automatic backup, same mid-write caveat
(`Backup_Restore.md` §1), no new integrity check (§9 F6).

`ShareHelper.share` now passes `completed && error == nil` to its optional
completion; no existing caller passed one. "Copy" counts as completed, so
the tick can mean "copied the file URL" (§9 F7, accepted).

### 3.3 Flow ownership (`DeleteWalletSettingView`)

Three flags on the info screen: `showingExportStep` (root of the sub-flow),
`showingPhraseConfirmation` (a `navigationDestination(isPresented:)`
nested on the export step's content, so back from the words lands on the
exports), `showingDeletionConfirmation` (the slider sheet, still on the
info screen). The override lifecycle moved from the phrase flag to the
export flag: leaving the sub-flow at its root without the sheet up drops
the override; popping from the words to the exports keeps it; the sheet's
`onDismiss` keeps it while the sub-flow is up. When the export flag goes
false the phrase flag is reset too (§9 F3). Abort and completion pop all
three. The info screen's intro moved to a new key
(`settings_delete_warning_everywhere_intro_recovery`, second round; the
first-round `_intro_steps` key lived for an hour and was purged before it
was committed; the original key had translations and would have kept its
English value); the gold link is gone. Under the intro, last-device path
only, a numbered **three-step list** (`fullWipeSteps`, title3 with 28 pt
gold numbers; "Save your wallet backup file", "Confirm two words of your
recovery phrase", "Delete permanently") and a divider before the forfeit
row. The two last-device forfeit variants now say
"recovered and refreshed" instead of "recovered from its recovery phrase
and refreshed" (English value edited in the catalog as well as in
`defaultValue:`, since the catalog wins for a translated key).

macOS island: the export step is a sheet, the phrase screen a sheet nested
on it, and a pass sets the slider flag and closes both. Desktop parked;
compile-only, nothing executed (§9 F5).

## 4. Claims the design rests on

- **verified** BIP39 English four-letter uniqueness (test executed against
  the package's list; the test was deleted with the rule the same day).
- **verified** the slot export is a copy of the ubiquity-container file and
  the restore path is newest-wins (trace steps 3, 9).
- **verified** rule 17's suspension starts inside `deleteWallet`, after the
  slider, so an export before it is never refused (trace step 5).
- **derived, not executed** two nested `navigationDestination(isPresented:)`
  levels plus the slider sheet presenting from the covered info screen; one
  level was device-checked 2026-10-15 (§9 F4). If the nested push failed,
  Continue on the export step would be a no-op and the full wipe
  unreachable — fails closed; the device step shows it at once.
- **assumed** bark rejects non-English phrases (reviewer read bark's
  `bip39` crate features on master, not at the deployed tag); the app's
  own validator is not English-only. If a non-English phrase were ever
  stored, the four-letter rule would be weaker for that list; not a
  regression against exact matching for English phrases.

## 5. Sweep

| Site | Status |
|---|---|
| `startDeletion` full-wipe branch | covered (pushes the export step) |
| `startDeletion` local-only branch | exempt — seed stays on the account, slot rewritten by the deletion itself |
| `ShareHelper.share` callers (`BackupStatusSectionView_iOS`, `DebugLogExportButton_iOS`, `MetadataBackupSectionView`, `ShareButton`) | covered — none passed a completion; default `nil` |
| `getShareableBackupFileURL` callers (`BackupStatusSectionView_iOS`, desktop `ManualBackupView`) | exempt-because — they export the slot deliberately; body unchanged, shared copy helper factored out |
| `settings_delete_warning_everywhere_intro`, `button_manual_backup`, `isFullWipePath` | no other users; the first goes stale with its translations, the second stays (Settings) |
| Local-and-slot-both-present | covered after §9 F1 (newest-wins, tested on the rule) |

## 6. Strings

New keys, `defaultValue:` at the call site: `settings_delete_export_title`,
`settings_delete_export_body`, `settings_delete_export_wallet_file`,
`settings_delete_export_wallet_file_subtitle`,
`settings_delete_export_metadata_subtitle`,
`settings_delete_export_wallet_file_missing`, `status_saved`,
`settings_delete_warning_everywhere_intro_recovery`,
`settings_delete_step_save_backup`, `settings_delete_step_confirm_words`,
`settings_delete_step_delete_permanently`,
`accessibility_step_number %lld %@` (`button_continue_without_backup_file`
and `settings_delete_step_slide` lived for the second round only and were
purged before commit).
Changed English: the two `settings_delete_forfeit_last_device*` keys.
Reused: `settings_metadata_backup`, `button_continue`, `button_download`,
`error_file_picker`. de/ja/zh-Hant applied through
`Scripts/apply_translations.py` the same day (needs_review, native
sign-off pending with the rest); glossary row for "wallet backup file".

## 7. Tests

`PhraseConfirmationTests`: four letters pass and three fail; a typo after
the fourth letter passes and one inside fails; words under four letters
match whole; the word-list uniqueness premise (all four replaced by one
test that partial words fail when the rule was removed the same day). `WalletFileExportTests`:
the live file is copied, not handed out; the legacy name is exported; live
beats legacy; the newest-wins rule between local and slot (strictly newer
wins, tie and unreadable date keep local, missing side yields the other).
No view tests; the flow is pinned by the device step.

## 8. Device check (owed)

One phone, primary, wallet with a phrase, mainnet or signet:

1. Delete wallet: intro, three-step list, divider, forfeit row → Continue
   → the export step, not the words; the tab bar disappears there and is
   back on the Delete wallet page.
2. Export step: Continue is disabled. Wallet backup file → Download →
   cancel the share sheet → still disabled. Download → Save to Files → the
   row shows Saved, Continue is enabled; the saved file opens as SQLite
   (size > 0). Contacts & Metadata → Download works, never gates.
3. Continue → the phrase screen; back → the export step with the ticks
   kept; Continue → the words again.
4. Phrase screen → long-press Back → Delete wallet → Continue → the export
   step again, not the words (§9 F3).
5. Type the first four letters of each word → Verify passes; three letters
   → refused. *(Rule removed after this check ran; whole words again.)*
6. Right words → slider → Cancel → back on the words; pop twice → the
   device re-check runs; Continue → export step → Continue → words.
7. Right words → slide → full wipe completes, onboarding.

Two-device set (Device stage, with the deletion set): the override route
from a secondary offers the export step; on a demoted device the exported
file is the slot's (newer) copy, not the frozen local one.

### 8.1 Result (Christoph, 2026-11-12, one phone)

Passed after the fourth tweak (no caption under the disabled Continue):
"works well". Steps were not reported one by one; treat the one-phone list
as passed in aggregate, which also settles §9 F3 (long-press back) and F4
(two-level push plus the sheet) for iOS. The two-device half stays owed to
the deletion set's Device stage.

## 9. Review record (2026-11-12, `fault-class-reviewer`, same session, on the uncommitted diff)

- **F1 CONFIRMED, class 2 — fixed.** Demoted device: local `db.sqlite`
  frozen at demotion, slot newer; the export preferred local
  unconditionally, so after the wipe deleted the slot the only state file
  left would have been the stale one. Fix: newest-wins by modification
  date (§3.2), two tests on the rule. Ledger line 2026-11-12.
- **F2 CONFIRMED, class 5 — fixed by this doc** and the amendments in
  `Wallet_Deletion_Phrase_Confirmation.md` (the plan said "no prefix
  matching", described the gold link and the old intro key).
- **F3 PLAUSIBLE, class 3 — closed defensively.** Long-press back jump
  might leave the nested phrase flag true and push the words straight
  over the next export step. The export flag's `onChange` now resets it;
  device step 4 confirms.
- **F4 PLAUSIBLE, class 4 — owed to the device step** (two-level push,
  sheet from two levels deep).
- **F5 PLAUSIBLE, class 4, macOS — parked, not run** (three-sheet chain,
  `NSSavePanel.runModal()` from a sheet).
- **F6 PLAUSIBLE, class 4 — accepted, shared with the background backup.**
  The copy is taken while bark's daemon may be mid-transaction; the
  shutdown backup stops the daemon first, the background hook and this
  export do not. A `quick_check` on the copy would make the tick honest;
  noted in `Backup_Restore.md` §1 with the existing caveat, not built.
- **F7 minor.** Old intro key stale with its translations (expected); the
  new keys English-only at review time (translated after); "Copy" counts
  as Saved (accepted).

Reviewer's lifecycle check: only two sites set the slider flag (phrase
pass, non-required direct path); an override can never take the direct
path because `isRequired` is true for both strategies with the override;
cancelled sheet, back gestures, long-press jump, abort and completion all
leave `overrideRequested` false or inside the sub-flow. Not verified by the
reviewer: any on-device run, the two-device scenarios, macOS, the bark-ffi
crate's `bip39` features at the deployed tag, iCloud placeholder files on
the slot fallback, the full suite.

### 9.1 Swipe-down on the slider sheet during the wipe (traced 2026-11-12)

Christoph asked whether the final screen should stay a sheet; while
checking, the sheet turned out to have no `interactiveDismissDisabled`.
Trace (all **verified**, read): the slider's completion runs `Task { await
performDeletion() }` (`DeletePermanentlyConfirmationView`), an unstructured
task that calls `onConfirm` → the info screen's `deleteWallet(strategy:
overrideConfirmed:)`. A swipe down while it runs dismisses the sheet; the
task is not tied to the sheet's view and continues; the info screen's
`isDeleting` stays true (Continue disabled, deletion progress bar visible);
`onDismiss` re-runs `checkDevices()`; completion routes through
`onWalletDeleted` regardless of what is on screen. So the wipe neither
stops nor repeats, and no seed step is skipped. What is lost: the sheet's
own `isDeleting` state and the "no way back" framing; the back chevron on
the info screen is not disabled either, so the user can wander through
Settings during the wipe until the routing fires. Only Cancel is disabled
today. **DECIDED 2026-11-12 and applied:**
`.interactiveDismissDisabled(isDeleting)` on the sheet content, a one-line
guard in the spirit of the disabled Cancel; `isDeleting` is the sheet's own
state, set when the slide completes and never reset because the sheet
leaves with the routing or the abort. Not executed on device (the wipe
cannot be rehearsed without a wallet to lose); the modifier is standard
SwiftUI. The info screen's back button during the wipe stays as it is,
not asked.

## 10. Full suite

Run after the review fixes, 2026-11-12 11:10 on the `Arke Tests` simulator
(`xcodebuild test … -only-testing:ArkeMobileTests`, parallel testing off):
**657 tests in 94 suites passed**, `** TEST SUCCEEDED **`. Re-run after
the second round (§1.1, copy, list, labels, tab bar) at 11:38 and after
the third (§1.2, required backup file, list size, copy) at 14:12: 657/657
each time. Desktop not built or run (parked).

## 11. Metadata row only when there is user data (DECIDED 2026-11-12, built)

Christoph's question (2026-11-12): offer Contacts & Metadata only if there
is actually data in there? Facts (**verified** in
`MetadataExportService.buildExportFile`): the profile travels only when
`isConfigured`; **all** contacts travel, including app-provisioned ones
(`ContactType.faucet`, `.developer`), so a signet wallet is rarely empty;
all tags travel, including system tags (`isSystemTag`, provisioned by
auto-tagging), so tags are never empty; annotations only for transactions
with notes, tags or contacts. An "empty" file therefore still has rows,
and "data in there" has to mean **user-added**: a configured profile, a
contact of type `.standard`, a tag with `isSystemTag == false`, or any
annotation. Proposal: hide the row when none of those exist, computed in
the screen's `.task` by the same fetches the export runs (cheap for
profile, contacts and tags; the annotation pass walks transactions with
the `live*` accessors as the export does). Alternative: keep the row and
show "Nothing to export yet" with the button disabled. Recommendation:
hide; an empty export is a non-choice on a screen about committing, and
the row would otherwise invite a pointless share sheet.

**Built:** `MetadataExportService.hasUserAddedMetadata(context:)`, four
counted fetches with `fetchLimit = 1` (configured profile, `.standard`
contact, non-system tag, non-empty note). Assignments are deliberately not
counted: auto-tagging and auto-assign create them without the user, and a
user-made one presupposes a user tag or contact that already counts. The
row starts hidden and appears from the screen's `.task`; a thrown check
shows the row (fail toward offering). `MetadataPresenceTests`: empty
store false; faucet contact + system tag + blank profile + note-less
transactions false; each user-added kind true on its own.
