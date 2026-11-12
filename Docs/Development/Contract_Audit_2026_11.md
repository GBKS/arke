# Contract Audit, November 2026

**Status:** audit complete 2026-11-12. Doc corrections (sections B and C) applied to both contracts the same day; the code findings (section A) are filed in `Open_Follow_Ups.md` at the tiers DECIDED 2026-11-12, and A.3 is folded into the explicit device linking scope pass. No code was changed. Second review the same day (a different session, two read-only agents plus greps): every section A claim, the test names, the bark line and the string claims re-read and confirmed; A.1, A.4, A.6, A.8 and A.13 sharpened below (marked ✔✔), A.4 moved to Tier 1 Data safety.

Claims audit of `Initialization/Launch_Sequence_Contract.md` and
`Architecture/Multi_Device_Design.md` against the code at `99ed3ef` plus the
uncommitted working tree of 2026-11-11. Seven read-only agents each took one
slice and read function bodies; nothing was built, run or tested. Doc line
numbers are those of the two files at that commit.

## Method and limits

- A claim is a present-tense statement about what the code does: a symbol
  exists and behaves as stated, an ordering, an Enforced or Test column, a
  status mark. Rationale, incident history and PROPOSED design were skipped.
- Verdicts: VERIFIED (body read, matches), WRONG (code contradicts), STALE
  (symbol, file or status no longer current), PARTLY (true with a material
  gap), NOT-CHECKED (could not be settled statically).
- **Second read.** The items marked ✔ were re-read in the code by the main
  session after the agents reported. Unmarked items rest on one agent's read.
- **Second review.** Items marked ✔✔ were re-traced by a separate session
  on 2026-11-12 and carry what that trace added. Every section A item and
  every symbol, test and string named in B and C was re-read then; none was
  contradicted. Still nothing executed.
- **Not covered:** bark-side claims (only `Wallet::sync` was read in
  `~/workspace/bark`), runtime timing, anything needing a device, desktop
  beyond grep hits, and most test bodies beyond their titles.
- Findings about behaviour are derived from reading. None was executed.

## Result

| Doc | Claims | Verified | Wrong | Stale | Partly | Not checked |
|---|---|---|---|---|---|---|
| Launch_Sequence_Contract | 173 | 133 | 4 | 2 | 23 | 11 |
| Multi_Device_Design | 140 | 79 | 10 | 12 | 24 | 15 |
| Both | 313 | 212 (68%) | 14 | 14 | 47 | 26 |

Wrong plus stale is 9% of claims; with partly it is 24%. The launch contract
is in much better shape (77% verified) than the multi-device design (56%),
whose S7, failure-mode and derived-work sections still describe October's
state.

## A. Code findings (the doc is right about intent, or the gap is in code)

These are the items that may be more than doc drift. Tiering is Christoph's.

1. ✔ **A lost primary that comes back after being unlinked can open with
   spend rights** (Multi_Device S4, L155-163). `unlinkDevice` deletes the row
   and the `com.arke.device.registered.*` mirror keys; `mirrorKeys` does not
   match `device_<id>_isPrimary`, so the returned device's flag still says
   primary and `wasDemoted` is unset. With the row gone, `checkReadOnlyMode`
   takes its "no registration, assume primary" branch. The open Tier 0 entry
   "`checkReadOnlyMode()` infers primary" calls this reachable via
   self-unlink; self-unlink is no longer offered (`LinkedDevicesView_iOS`
   passes `onUnlink: nil` for the current device), but unlink by another
   device reaches the same state. ✔✔ Traced end to end: on the relaunch
   `performWalletStateDetection` finds no row, so `checkDevicePrimaryStatus`
   returns nil and the state is `walletWithSeed`; `MainView_iOS` calls
   `initialize()` without `forceReadOnly`; `shouldBlockWalletAccess` passes
   all three layers (no `wasDemoted`, mirror flag still true, no row for
   layer 3); `checkReadOnlyMode` assumes primary. The wallet opens with
   spend rights for that session. `registerDeviceIfNeeded` then writes a
   secondary row and `writeOwnPrimaryFlag(false)`, which nothing in the
   running session observes, so the *next* launch is blocked at layer 2.
   One full primary session, then read-only. The device check must look at
   the first relaunch.
2. ✔ **A device without the seed can be promoted to primary** (matrix L56).
   The button condition in `LinkedDevicesView_iOS` and
   `promoteThisDeviceToPrimary` check only "not primary" and "no other
   primary"; nothing checks for the mnemonic. The device then runs
   `initialize(forceReadOnly: false)` into the seed-missing branch.
3. ✔ **The S3 and S4 flows as written cannot be performed.**
   `promoteThisDeviceToPrimary` throws `primaryDeviceAlreadyExists` while a
   primary row is visible and the button is hidden. S3 is really demote on
   the primary, then promote on the secondary; S4 is unlink the lost device
   first, then promote. No device writes another device's
   `device_<id>_isPrimary` (`writeOwnPrimaryFlag` is the sole writer), so the
   "old primary observes the flip" mechanism does not exist. Either the doc
   or the flow needs changing.
4. ✔ **Rule 3 is not enforced at the launch open.** `restoreWalletIfNeeded`
   logs "wallet will start fresh" when there is no local file and no backup,
   and `tryOpenExistingWallet` then opens with the bindings' default
   `createIfNotExists: true` (`WalletOpenArgs`, default read at
   `golang/v0.26.1`). ✔✔ The guard ahead of it tests directory existence,
   and `BarkWalletFFI.getWalletDirectory()` creates the directory in every
   init, so a missing database reaches the create on any device that ran
   once; the import path is the only caller passing `false`. Filed since
   2026-10-29; moved from Tier 4 to Tier 1 Data safety on 2026-11-12. The
   contract's "Enforced: `WalletBackupService.swift`" covers only the probe.
5. ✔ **A second deleter of the KVS wallet hash** (rule 21, L296).
   `SecurityService.deleteHashFromUbiquitousStore()` is called from the
   import rollback in `WalletManager+Wallet`. Rule 19 lists the matching
   `removeMnemonic()` exception for the seed; rule 21 lists none. ✔✔
   `WalletDataCleanupService` also carries its own private
   `deleteHashFromUbiquitousStore()` with the same body: two
   implementations as well as two callers (hygiene only).
6. ✔ **Check-in reminders armed on `isActive`, not `isInFlight`** (sibling
   of rules 9 and 13). `NotificationsSettingView_iOS` arms the sequence when
   any exit `isActive`, which includes cancelled ones; `userCheckedIn` calls
   `scheduleCheckInSequence()` unconditionally. ✔✔ Its foreground caller in
   `ArkeMobile` is gated on `hasActiveExits()`, which returns whether a Live
   Activity exists and reads no exit at all.
7. **Rule 24 (d) is half true.** In `unregisterCurrentDevice`,
   `getOrCreateDeviceId()` can still throw before `removeMirrorEntries`;
   the cleanup service records that as `.failed` ("a ghost entry may block").
8. **Rule 23 sweep has unlisted hits.**
   `TransactionService.cleanupOldPendingMetadata` is an age-based multi-row
   delete of a CloudKit-mirrored model outside the cleanup service;
   `dedupeOwnRecords` is a dedup missing from the list;
   `OnchainTransactionService.clearPersistedTransactions` is dead;
   `TagService.deleteAllTags`' own comment says it is used during wallet
   deletion (it has no callers). ✔✔ Three more from the full
   `modelContext.delete(` sweep: `TransactionService.buildExistingTransactionDictionary`
   deletes duplicate-txid `PersistentTransaction` rows on every upsert,
   `BackupStatus.getSingleton` dedups a mirrored singleton, and
   `SwiftDataHelper.cleanupDuplicateBackupStatus` is dead. Everything else
   outside the cleanup service is a single-row user action or a
   per-transaction replace-all loop; no `.delete(model:)` batch delete
   exists.
9. **Rule 7b has a fourth owner.** `RefreshModalView` creates a
   `BalanceRefreshStatusViewModel` and loads once in `.task` with no
   `isInitialized` hook. User-opened modal, low exposure.
10. **`checkForPrimaryDevice` is unscoped** in `LinkedDevicesView_iOS` while
    `checkForNoPrimaryDevice` is wallet-scoped; a primary row from another
    wallet hides the promote button while the warning still shows.
11. **Linked Devices builds its registry list itself** (rule 24 (a)): only
    `mirrorOnly` comes from `otherDeviceReport`; the row list has no 30-day
    filter, so a stale row is listed there but is not a blocker in the
    report.
12. **Rule 25 title overstates.** `BarkWalletFFI.getWalletDirectory()` still
    runs `createDirectory` and the `.test` write probe inside init when the
    directory is missing; `withBackgroundActivityAssertion` has exactly two
    call sites, other background-reachable saves (`updateHeartbeat`) are
    unwrapped.
13. **Stale code comments** repeat the old "unlink needs a row / iOS menu
    hidden" claim: `unregisterCurrentDevice` and `otherDeviceReport` doc
    comments, `OtherDeviceReport.mirrorOnly`, `shouldOfferOverride`'s doc
    comment, and the desktop `LinkedDevicesView` mirror-only comment. ✔✔
    Two more: the `deviceUnregistrationRecord` doc comment and the
    `rowRetained` case doc in `WalletDataCleanupService`, both "desktop
    today".

## B. Launch_Sequence_Contract: doc corrections

Wrong or stale:

- ✔ **Rule 7a, L77-79** "only trigger besides the hourly timer (nothing
  restarts it on foreground)". `VTXORefreshService.checkAndRescheduleAfterForeground`
  runs the check on every foreground return (called from `ArkeMobile`), and
  `triggerImmediateCheck` exists. The ordering claim still holds.
- **Rule 12, L163** Enforced names `WalletManager+Transactions.swift`; the
  date freeze is `TransactionService.updateExistingTransaction` in
  `TransactionService+Upsert`.
- ✔ **Rule 18, L271** Enforced names `WalletManager+Wallet.swift`; the
  strategy is `deletionStrategy(for:)`, `includesCloudData`,
  `fullWipeStillJustified` in `WalletDataCleanupService`. "Test: none" is
  wrong: `DeletionStrategyTests`, `FullWipeOverrideTests`,
  `FullWipeRevalidationTests`, `DeletionAssessmentOrchestrationTests`.
- **Rule 23, L348-351** "`deleteWallet()` takes no strategy parameter": it
  is `deleteWallet(scope:)`; `clearTransactionModels` and
  `resetBalancesAndDeletePersisted` no longer exist. History written in the
  present tense.
- **Rule 24, L412-414** "desktop today; the iOS row menu is hidden": iOS
  unlink is live for other devices and for mirror-only rows; desktop cannot
  unlink mirror-only rows. The reverse of the text.

Partly true:

- **Rule 7, L58-70**: the reveal is conditional (`getCurrentReceiveAddress`
  returns a saved unused row without calling bark); `syncOnchain` at Step 2c
  and the import-time `initialScan` are not mentioned.
- **Rule 7b, L87-88**: the handle is also set by create, import and the
  background wake. L99-106: owners also reload on `refreshStatusVersion`,
  `reloadTrigger`, `arkInfo`.
- **Rule 7c, L109-111**: cites `bark-0.7.1`; deployed bindings are
  `v0.26.1+bark-0.8.0`. The fact still holds there.
- **Rule 13a, L173-185**: true for the predefined configs; the custom-server
  form at first use has an editable Esplora field.
- **Rule 14, L199-200** "Test: none": `MirrorPrimaryVerdictTests` pins layer
  2 of `shouldBlockWalletAccess`; the check-before-open ordering is untested.
- ✔ **Rule 15, L202-208**: `promoteThisDeviceToPrimary` and
  `dedupeOwnRecords` also make a device primary; the winner rule is
  `becamePrimaryAt ?? registeredAt`; `PrimaryDeviceReconciliationTests`
  covers only the pure winner rule.
- **Rule 17, L246**: the refresh re-check is the last pre-destructive check,
  after the scope guard (`scopeAbortWinsOverRefreshGate`), not the first
  step. L254-256: `unregisterCurrentDevice` has already run and is not
  rolled back on a CloudKit failure.
- **Rules 17/20/21 and Multi_Device L737** "Test: `WalletDeletionRejoinTests`":
  that is a file name. No suite has it, so
  `-only-testing:ArkeMobileTests/WalletDeletionRejoinTests` presumably
  matches nothing (not run). Suites are `TombstoneRoutingTests`,
  `WalletWipeCoverageTests` and others.
- **Rule 20, L284-294**: tests cover the pure decisions only, not the
  detection re-run or the tombstone write.
- **Rule 24, L382-383**: `hasOtherActiveDevices` is a wrapper with no
  callers; `otherDeviceReport` reads the registry first, the mirror second
  (precedence holds, read order does not). L400-402: the override needs
  every blocker doubtful and a mirror-only entry older than the 48 h
  `mirrorSettleWindow`; `OverrideAvailabilityTests` is not named.
- **Rule 27, L495-496**: the timer path sets `registration = .empty` rather
  than calling `forceRefresh()` (deliberate, same effect).
- **Test gaps, L506-509**: omits rules whose own Test column says none (5,
  7a, 7b, 7c, 9, 10, 13, 16, 19); 14 and 17 now have partial coverage.

## C. Multi_Device_Design: doc corrections

Wrong:

- ✔ **Matrix L55** "Show recovery phrase: secondary (seed synced) ✓". The
  settings entry is hidden whenever `isReadOnlyMode`; the only other route
  is the backup link on the full-wipe path. `getMnemonic()` has no role
  guard, so the block is UI-only.
- ✔ **Matrix L56**, **S3 L135-143**, **S4 L151-162**: see A.2 and A.3.
- **S4 L161** quotes "I no longer have this device"; no such string. The
  button is "Make Device Primary".
- ✔ **S7 L332-333** "`forgetUnsyncedDevice(_:)` … `unlinkDevice` can't touch
  a row-less mirror entry". `unlinkDevice` clears mirror entries first and
  `unlinkVerdict` treats that as success; `forgetUnsyncedDevice` does not
  exist.
- ✔ **S7 L335-336, L612-614, L767-769** phrase confirmation "not built":
  `PhraseConfirmation` is built, wired in `DeleteWalletSettingView`, tested.
- **L482** "Whole session on mainnet … still open":
  `reconcileNetworkConfigBeforeWalletOpen` runs as step 0-pre and on the
  headless path (two agents agree).
- **L553-555** vocabulary: the user-facing title is "Devices", "All linked
  devices will lose access" does not exist, and "rejoin" is established
  copy.
- ✔ **L794-795** self-unlink "which `LinkedDevicesView_iOS.swift:46`
  offers": no longer offered on either platform.

Stale (built or deleted since the text was written):

- **L205-212, L776-777, L798-800**: `migrateToThisDevice()` and
  `cleanupStaleDevices` are deleted (2026-10-16). **L407-408** likewise.
- **L418-419, L781**: devices-list scoping is built (`accountWalletHash`);
  automatic stale cleanup is rejected in code, not pending.
- **L607-608, L622, L644, L690-691, L724, L765-767** "S7 proposed / override
  unbuilt": blocker naming, the informed override, revalidation and the
  conservative fallback are built. Still missing: the "wallet deleted
  elsewhere" cleanup offer.
- **L727-730**: the mirror cleanup is no longer nested in the row fetch.
- **L784-789**: the "couldn't check" third state is built.
- **L790** line reference for `checkReadOnlyMode`; the behaviour claim is
  verified.

Partly true:

- **Matrix L54**: Send is hidden, but there is no manager-level role guard;
  the block is the closed bark handle. The Exit screen is reachable on
  secondaries (the read-only guard in `SettingsView_iOS` is commented out).
- **Matrix L57**: desktop mirror-only rows have no unlink; desktop has
  "Unlink All Other Devices", unmentioned.
- **Matrix L59**: omits the override route to a full wipe.
- **S2 L117-126**: seed arrival is noticed only on foreground; the device
  stays in the same read-only mode, only the sheet copy changes. Typing the
  phrase goes through import with `allowPrimaryClaim: true`.
- **S6 L223-225**: quoted copy differs from the shipped strings.
- **S7 L241-242, L246, L249-258, L265-266, L290-291, L304-306, L323-325**:
  each is contradicted or narrowed by later lines of the same section (the
  override is a second way out; names and explanation exist; a stale row
  the mirror corroborates still blocks; a two-word check now sits in front
  of the acknowledgement; local file teardown runs after the seed delete).
- **S10 L401-403**: the account-change reason is only logged.
- **L483**: re-detection is event-driven (foreground, protected data), not
  timed. **L641-644**: no shorter blocking threshold exists; the 48 h window
  is decided in code. **L674-683**: self-promotion is refused while a
  primary row is visible. **L685-691**: blockers are now named, so "goes
  unnoticed" no longer holds. **L715-717**: same wrapper as rule 24.
  **L773-774**: `.showNoPrimaryDeviceBanner` is posted with zero observers;
  a passive notice exists in Linked Devices.

Status marks: S5 ◻, S10 ◻ and S12 ✓ are right. S7 ◻ understates what
shipped. S3 ⚠️ and S4 ⚠️ describe flows the code does not offer. S11's open
items are closed in code.

## D. Not checked

- bark-side facts in rules 1, 7, 8, 10, 12 (replay of completed exits,
  `created_now` gating, purge of claimed exits).
- "Without touching the seed" in rule 14: `initializeReadOnlyMode` and the
  full body of `reconcileNetworkConfigBeforeWalletOpen` were not read for
  mnemonic access.
- Rule 17's cold-launch outcome after a keychain-delete failure; rule 22's
  three direct `Wallet.open` call sites (create, import, restore) end to
  end; rule 26's first-import gate on a fresh account.
- Whether a read-only secondary holds a non-nil wallet for
  `deleteWallet(scope:)`; whether rejoin reaches `restoreWalletIfNeeded`.
- Whether round, exit and VTXO-refresh services stay idle in read-only mode.
- `needsDefaultTags` (may read the in-memory cache); edit gating for tags
  and contacts on secondaries; `DeletePhraseConfirmationView`'s `.missing`
  state on a seedless device.
