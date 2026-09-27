# Launch Sequence Contract

Ordering invariants around app startup, wallet open/create/import, first
sync, exit progression, and multi-device detection. Each rule was learned
from an incident — the "or else" column is not hypothetical. This is a
contract, not a narrative: for flow walkthroughs see
`INITIALIZATION_FLOWS.md`.

**Maintenance:** when a startup-shaped bug is fixed, add its rule here (same
reflex as updating `Open_Follow_Ups.md`). Any PR that touches launch
ordering must check itself against this list. A rule whose Test column says
*none* is enforced by comments alone — that column doubles as the extraction
backlog for the pure-logic pattern (`ExitProgressionLogic` /
`ExitClaimSequence` style).

## Opening the wallet

**1. One single-step `Wallet.open` performs creation — never `initWallet()` first.**
A prior `initWallet` writes the properties row, turning the open into a
"subsequent" open and permanently disabling bark's seed-recovery scan (gated
on `created_now`), with no error and no re-scan API. We shipped this shape
for months; imports silently never recovered (2026-08-10, feedback §1.7).
Enforced: `BarkWalletFFI+WalletCreation.swift`. Test: none.

**2. Seed-only import: a nil recovery report means wipe-and-reopen, and `skipRecovery` stays false.**
A failed scan is indistinguishable from a skipped one, and the scan runs only
on the creating open — so on nil report, stop the daemon, wipe the
seconds-old database, redo the creating open (bounded retries). Fresh-seed
*creation* uses `skipRecovery: true`; import must never.
Enforced: `BarkWalletFFI+WalletCreation.swift` (`openImportedWallet`,
decision in `ImportRecoveryLogic`). Test: `ImportRecoveryLogicTests`
(decision matrix; the wipe-before-reopen mechanics remain code-only).

**3. Wallet existence is `db.sqlite` OR `bark.sqlite` — never recreate-from-seed on a "missing" database.**
bark 0.11+ creates `db.sqlite`; a `bark.sqlite`-only probe false-detected "no
wallet" and restored a stale backup over a fresh wallet.
Enforced: `WalletBackupService.swift`. Test: none.

**4. Backup restore runs only when no wallet is open.**
An open wallet is authoritative; restoring over it pairs the keychain
mnemonic with a foreign database (e.g. a stale backup from a previously
deleted wallet, right after creation).
Enforced: `WalletManager.swift` (`restoreWalletIfNeeded`). Test: none.

**5. Network mismatch: seed-only import wipes stale data and retries; backup import surfaces the error and never wipes.**
Leftover data from another network can't be the wallet being seed-imported —
but a user-picked backup file is precious and the mismatch is user error.
Enforced: `WalletManager+Wallet.swift` (`importWallet` vs
`importWalletWithBackup`). Test: none.

**6. The mnemonic keychain item migrates to `afterFirstUnlock` at launch (idempotent).**
Background sync needs the seed after one unlock per boot; `whenUnlocked`
starves background tasks.
Enforced: `SecurityService.swift`. Test: `KeychainAccessibilityMigrationTests`.

## First refresh and sync

**7. Load/reveal addresses before the onchain history and balance reads.**
bark's revealed-SPK sync scans nothing until at least one address is
revealed; on a fresh import the first balance read must come after the
reveal or it reports zero (fixed 2026-08-12, commit `fc9a006`-adjacent).
Enforced: `WalletManager.swift` (`performRefresh`, addresses-first step). Test: none.

**7a. `vtxoRefreshService.start()` must come after the first `refresh()`.**
`start()` runs an immediate `checkAndRefreshVTXOs()`, whose Guard C
exclusion reads `WalletManager.transactions` — the unified service's
*stored* merge, populated by `performRefresh()`. Start the service first and
the launch-time check sees an empty transaction list, so Guard C is silently
inert. That matters more than it sounds: the immediate check is the service's
**only** trigger besides the hourly timer (nothing restarts it on
foreground), so the launch check is a large share of all checks ever run.
The same dependency is why `refreshAfterVTXOChange()` must call
`mergeTransactions()` and not just the Ark-only refetch (2026-09-21,
`Features/Refresh_Deduplication.md` §§1, 3.2).
Enforced: `WalletManager.performInitialization()` (`await refresh()` precedes
the `start()` block). Test: none — ordering is positional.

## Exit progression and Live Activities (iOS)

**8. Launch order: reattach → first `checkAndProgressExits` → `recreateMissingActivities` → reminder re-arm.**
On a fresh seed import bark replays already-completed exits through the
state machine, so they read as in-flight until the first pass settles them —
recreating earlier spawned a "Move complete 5/5" lock-screen activity for an
exit finished long ago (2026-08-13).
Enforced: `ExitProgressionLogic.swift` (`LaunchSequence.run`, called from
`ExitProgressionService.start`). Test: `ExitProgressTests`
(`LaunchSequenceTests/launchOrderIsPinned`).

**9. Activity recreation filters on `isInFlight`, never `isActive`.**
Claimed and cancelled exits stay in bark's exit list; an `isActive` filter
respawns a "complete" activity on every launch.
Enforced: `ExitProgressionService+LiveActivity.swift`
(`recreateMissingActivities`). Test: none.

**10. `endLiveActivity` recomputes step totals from fresh statuses when the caller has them.**
The last pushed update can predate the transaction chain becoming known
(fresh-import replay), freezing a short step estimate into the final banner
(the 5/5-instead-of-6/6 half of the 2026-08-13 incident).
Enforced: `ExitProgressionService+LiveActivity.swift` (`endLiveActivity`).
Test: none (aggregate math itself: `ExitProgressTests`).

**11. Claim sequence order is load-bearing: `recordClaim` immediately after broadcast; `snapshotStatuses` after `progressExits`.**
bark purges claimed exits from `getExitVtxos()` shortly after the claim —
the drained VTXO ids and the `ClaimInProgress` state carrying the claim txid
exist only in that window; miss it and the fee and claim links are gone
(feedback §1.5).
Enforced: `ExitProgressionLogic.swift` (`ExitClaimSequence.run`).
Test: `ExitProgressTests` (`testSequenceOrder`).

**12. Already-cancelled movements keep their date frozen on upsert.**
bark re-finishes cancelled exits on every sync where the tip advanced,
bumping `completed_at`; only the first transition into cancelled may set the
date (feedback §1.4).
Enforced: `WalletManager+Transactions.swift` (upsert).
Test: `TransactionUpsertDateFreezeTests`.

**13. Check-in reminders re-arm on every launch/backgrounding while exits are in flight, and clear when none are — after the first progression pass.**
Reminders used to be scheduled only at exit start and cancelled on launch,
so any relaunch mid-exit permanently disarmed them; re-arming before the
first pass arms them for replayed already-finished exits.
Enforced: `ExitProgressionService+LiveActivity.swift`
(`rescheduleCheckInRemindersIfNeeded`), `ArkeMobile.swift` (scene phase). Test: none.

## Multi-device

**14. Check demotion before opening the wallet.**
A demoted device must fall back to read-only mode without touching the seed;
the layered check (UserDefaults → iCloud KV → CloudKit cache) runs as step 0
of initialization. Since 2026-09-25 the background wake path honors it too:
its headless open (`refreshRelayAuthInBackground`) checks
`shouldBlockWalletAccess()` before opening and answers `.nothingToDo` — a
demoted ex-primary with a leftover local db must not open bark on every wake,
and the new primary owns the mailbox, so retrying would never succeed.
Enforced: `WalletManager.swift` (`performInitialization`,
`shouldBlockWalletAccess`), `WalletManager+Notifications.swift`
(`refreshRelayAuthInBackground`, headless open). Test: none (reconciliation
half is tested, see 15).

**15. Primary status is claimed only by explicit create/import — never inferred by detection paths.**
"First device" inference under sync lag created two primaries; detection
paths pass `allowPrimaryClaim: false`, and duplicates converge via
deterministic self-demoting reconciliation (earliest `becamePrimaryAt`,
deviceId tiebreak).
Enforced: `DeviceRegistrationService.swift` (`registerCurrentDevice`,
`reconcilePrimaryConflicts`). Test: `PrimaryDeviceReconciliationTests`.

**16. The device ID keychain item is non-synchronizable.**
It distinguishes "this device was wiped" from "the seed arrived on a new
device" — syncing it would collapse that distinction.
Enforced: `DeviceRegistrationService.swift` (`getOrCreateDeviceId`). Test: none.

## Deletion

**17. Deletion order: reset manager state → end Live Activities immediately (sweep all, not just the tracked one) → clear notifications → unregister push → settle → delete files → clear local evidence.**
State reset first prevents operations mid-deletion; the *immediate* activity
end matters because the standard end shows an hour-long summary advertising
an exit of a wallet that no longer exists, and the sweep catches orphans
from failed reattaches.
Enforced: `WalletManager+Wallet.swift` (`deleteWallet`),
`ExitProgressionService+LiveActivity.swift` (`endLiveActivityImmediately`). Test: none.

**18. `includeCloudData` is strategy-derived; the seed is deleted only on a last-device full wipe.**
A fixed value either orphaned secondaries or destroyed the only seed copy
(fixed 2026-08-12).
Enforced: `WalletManager+Wallet.swift` (deletion strategy). Test: none.

**19. Only `WalletDataCleanupService` may delete the mnemonic keychain item.**
A second deletion site inside `BarkWalletFFI.deleteWallet()` deleted the
synchronizable seed on *every* deletion — including local-only — propagating
account-wide via iCloud Keychain and defeating rule 18 one call later
(found 2026-08-19). The FFI layer deletes files only; keychain policy is the
cleanup service's alone. Legitimate `SecItemDelete` owners: the cleanup
service, `removeMnemonic()` (import rollback), and the accessibility
migration's delete-and-re-add fallback.
Enforced: `BarkWalletFFI+WalletCreation.swift` (comment),
`BarkWalletProtocol.swift` (contract). Test: none (sweep: grep `SecItemDelete`).

**20. Post-deletion routing re-runs full detection; a local-only deletion routes to the rejoin screen, never onboarding.**
`onWalletDeleted` used to set `hasWallet = false` blindly, exposing
onboarding's Create path — which overwrites the account's synchronizable
seed. The local-deletion tombstone (UserDefaults, stores the wallet hash)
suppresses seed-based resurrection at relaunch and routes to
`.walletAvailableToRejoin`; `createWallet` independently refuses when any
account-level wallet signal exists (`Wallet_Deletion_And_Rejoin.md`).
Enforced: `SecurityService.swift` (`tombstoneRouting`, detection step 0),
`MainView_iOS.swift` / `MainView.swift` (`onWalletDeleted`),
`WalletManager+Wallet.swift` (`accountHasWalletSignals` guard).
Test: `WalletDeletionRejoinTests`.

**21. Account-shared key-value state (KVS network config, KVS wallet hash, keychain seed) is deleted only by WalletDataCleanupService on a full wipe — never by device-scoped deletion paths.**
`WalletManager.deleteWallet()` used to call `NetworkConfigPersistence.clear()`
unconditionally, removing the shared network config from iCloud KVS on every
deletion: a local-only delete on one device stranded the live secondary on
default-mainnet, whose signet db then failed to open with a network mismatch
that looked like total data loss (2026-08-20). Same fault class as rule 19.
`clearLocal()` vs `clearEverywhere()` make the scope explicit; the inventory
of shared keys and their scopes lives in `SharedStateWipeCoverage`. Related:
rule 22 reconciles the wallet's network against that shared config before the
first open instead of silently defaulting to mainnet.
Enforced: `NetworkConfigPersistence.swift`, `WalletDataCleanupService.swift`
(`SharedStateWipeCoverage`), `WalletManager.swift` (step 0-pre).
Test: `WalletDeletionRejoinTests` (inventory consistency).

**22. Every path that opens the wallet reconciles its network against the account first — and no path reconciles after.**
The wallet object is built in `WalletManager.init` from the UserDefaults
cache, which can be absent (reinstall, local deletion + rejoin) or
stale-but-present (a switch that reached iCloud but not this device). Either
way bark opens on the wrong network: a full session against the wrong chain,
then rule 21's mismatch refusal on the next launch. Gating the recovery on
"no local config" is what allowed it — `syncFromiCloud()` writes the very key
the guard read, so MainView's `.task` sync disarmed it seconds before
`initialize()` ran (2026-09-23). The second half of the rule is not optional:
create/import set the network, save it locally, and mirror to iCloud
*asynchronously*, then call `initialize()` with the wallet already open — so
after an open the local value is the newer one, and syncing would overwrite a
just-saved config with a stale iCloud id and re-point a live wallet. Hence the
skip-when-open guard, and hence `reconciliation()` returning `.noUsableConfig`
rather than `load()`'s mainnet fallback for an unresolvable id. Network config
is the *only* class of state where the account's value overwrites this
device's (bark's wallet database is device-authoritative and never overwritten
by the account — transaction *metadata* does sync, see rule 23; the primary
flag uses a deterministic winner rule) — and only in the window before an
open. Two 2026-09-25 hardenings: the `.reapply` branch re-checks
`isWalletOpen` after its awaits (the top guard goes stale across suspension
points, and the background wake path isn't serialized with the "initialize"
funnel), and MainView's unconditional `syncFromiCloud()` was removed on both
platforms — redundant pre-open, and when it lost the race with the open it
flipped the cache under runtime `load()` readers (metadata export/import
network stamping) while the wallet ran on the old network.
Enforced: `WalletManager.swift`
(`reconcileNetworkConfigBeforeWalletOpen`, step 0-pre),
`WalletManager+Notifications.swift` (background wake open),
`NetworkConfigPersistence.swift` (`reconciliation`).
Test: `NetworkConfigReconciliationTests` (the decision; the skip-when-open
guard and the call-before-open ordering are code-only — sweep: grep
`openWalletIfNeeded`, every call site must reconcile first).

**23. Only `WalletDataCleanupService` deletes CloudKit-mirrored rows; every service-level reset is in-memory.**
`WalletManager.deleteWallet()` takes no strategy parameter, so its
`resetManagerState()` ran identically for a local-only delete and a full wipe
— and it called `TransactionService.clearTransactionModels()` plus
`BalanceService.resetBalancesAndDeletePersisted()`. Those models are in
`appSchemaModels` with `cloudKitDatabase: .private`, so the deletes replicated
account-wide: deleting the wallet on a secondary blanked the primary's activity
list, and because `PersistentTransaction` cascades to
`TransactionTagAssignment` and `TransactionContactAssignment`, it destroyed
every tag and contact assignment in the account (2026-09-23). The transactions
returned on the primary's next refresh — re-upserted from bark movements — but
the assignments are unrecoverable, since bark knows nothing about them. Same
fault class as rules 19 and 21: a device-scoped action destroying
account-scoped state, one call after the strategy-aware service did the right
thing. Both dangerous methods were deleted rather than gated —
`resetBalancesInMemory()` already existed for this and had never been wired up.
Note the limit of the existing coverage test: it asserts that
`WalletWipeCoverage` accounts for every schema model, which says nothing about
strays in other files.
Enforced: `WalletManager+Wallet.swift` (`resetManagerState`),
`TransactionService+Utilities.swift` (comment in place of the method),
`BalanceService.swift` (`resetBalancesInMemory` is the only reset).
Test: `TransactionDeletionBlastRadiusTests` (the cascade, not the call site —
sweep: `grep "modelContext.delete"`, every hit outside
`WalletDataCleanupService` must be a single-row delete, a dedup
(`TransactionService+Upsert`, `SwiftDataHelper`, `BackupStatus`), or a
user-initiated bulk action. The sweep as of 2026-09-23 has two of the last
kind, both currently unwired: `TagService.deleteAllTags()` and
`ContactService.deleteAllContacts()`. Account-wide is *correct* for those —
the user is asking to delete their tags everywhere — but neither may ever be
called from a deletion, reset, or migration path.)

**24. Evidence that blocks an irreversible action must be nameable on screen and overridable by the user.**
The counterpart to rule 23's lesson: rule 23 keeps a device-scoped action from
destroying account-scoped state, and this one keeps the *guard* against that
from becoming a cage. `hasOtherActiveDevices(walletHash:)` reads the fast iCloud
KVS mirror before the CloudKit registry — correct and load-bearing, since a
joining secondary reading the slower store would be told it was the last device
and would wipe the account's shared seed. But the mirror has no staleness cutoff
(its timestamp is written at registration and heartbeats never refresh it), so a
mirror entry for a device that is genuinely gone blocked the full wipe forever,
and S7's informed override had never been built. Result: **the wallet could not
be deleted from the account at all**, and every reinstall re-adopted it
(2026-09-23). Worse, the two surfaces disagreed — Linked Devices read the
registry and said "1 device" while the delete dialog read the mirror and said
others kept access — so the state was undiagnosable from inside the app.
Three obligations follow. (a) One source: anything the UI says about other
devices comes from `otherDeviceReport(walletHash:)`, which merges both stores
and marks mirror-only entries, never from one store per screen. (b) Name the
blockers, including "unrecognized device" when only the mirror knows one — an
unnameable blocker is the case the override exists for. (c) `.localOnly` reaches
a full wipe only through an explicit, acknowledged override
(`includesCloudData(strategy:overrideConfirmed:)`); no error, timeout or retry
may reach one — and that override is *offered* only where the block is doubtful
(`shouldOfferOverride(strategy:report:)`: a mirror-only blocker, a stale row the
mirror keeps alive, or an unreadable registry). Gating it on `.localOnly` alone
shipped it onto healthy two-device accounts, which inverts the rule: an
escape hatch presented as a routine option is its own hazard. Also fixed here: `unregisterCurrentDevice()` cleared the mirror
only inside `if let registration`, so a device whose row hadn't imported (fresh
adopt) or had already been deduped left a permanent ghost that each reinstall
re-wrote.
Enforced: `DeviceRegistrationService.swift`
(`otherDeviceReport`, `mirrorKeys(forDeviceId:in:)`, `unregisterCurrentDevice`),
`WalletDataCleanupService.swift` (`assessDeletion`, `includesCloudData`),
`DeleteWalletSettingView.swift` / `DeletePermanentlyConfirmationView.swift`
(named blockers, acknowledged override), `LinkedDevicesView*.swift`
(mirror-only rows, wallet-hash scoping).
Test: `OtherDeviceReportTests`, `FullWipeOverrideTests`,
`MirrorKeySelectionTests`.

**25. Store and file writes on background-reachable paths hold a task assertion; `App.init()` does no filesystem probing.**
A process suspended while holding a SQLite or file lock is killed outright —
`RUNNINGBOARD 0xdead10cc` — and two of the three TestFlight crash signatures on
build 23 were exactly that, on background runs: a SwiftData save in
`registerCurrentDevice`, and `BarkWalletFFI.getWalletDirectory()`'s `.test`
writability probe 1.8s into a background launch while CloudKit's metadata
migrator held a connection on another thread (2026-09-24, found in Organizer,
never in our own logs). The kill is invisible from inside the app: the journal
records the wake and no completion, which reads as "iOS never granted us time"
rather than "we were killed mid-write". Two halves: take the assertion
*before* starting the write (`withBackgroundActivityAssertion`, per Apple's
guidance), and don't do avoidable filesystem work in the App's initializer,
which a background launch runs in full before anything knows the launch is
headless. The assertion is best-effort — a refused one runs the work
unprotected — so it lowers the odds rather than closing the hole; the real fix
for the launch half is lazy wallet construction, deliberately deferred.
Enforced: `BackgroundActivityAssertion.swift`,
`DeviceRegistrationService.swift` (`registerCurrentDevice`),
`WalletManager+Notifications.swift` (background wallet open),
`BarkWalletFFI.swift` (`getWalletDirectory`).
Test: none — the failure is a system kill, only observable in Organizer.

**26. Default data is seeded only after the first CloudKit import pass completes, or when provably nothing can import — device role alone is not the guard.**
The seeding condition is "no local rows", which is briefly true on ANY fresh
install of an existing account: the store is empty until the first import
lands. The first guard (2026-09-23) was role-based and only covered
secondaries — a reinstalled primary (delete app → reinstall → import seed)
still seeded 9 fresh-UUID tags plus the faucet contact seconds before the
account's originals imported, and the duplicates synced account-wide
(2026-09-24 review finding). The decision is now
`defaultDataSeedingDecision(isReadOnlyMode:origin:firstImportCompleted:)`:
read-only never seeds; `.created` seeds immediately (creation refuses when any
account wallet signal exists, so a created wallet provably has nothing to
import); everything else waits for `CloudKitFirstImportGate` — a finished,
successful `NSPersistentCloudKitContainer` import event, which fires on fresh
accounts too (the import completes having found nothing) — with a 90 s timeout
so an iCloud-signed-out import doesn't starve. The timeout residual is capped
by insert-time dedup against the STORE: tags always fetched per name;
contacts fetch for an existing faucet row since 2026-09-25 (the in-memory
`contactCount` check can be stale against a just-landed import). The TagsView
"add default tags" button stays ungated — explicit user intent.
Enforced: `WalletManager.swift` (`defaultDataSeedingDecision`,
`seedDefaultDataIfAppropriate`), `CloudKitObserver.swift`
(`CloudKitFirstImportGate`), `ContactService+DefaultContacts.swift`
(insert-time dedup), `TagService.swift` (per-name fetch, pre-existing).
Test: `DefaultDataSeedingDecisionTests` (decision matrix + gate filter truth
table). On-device gate: reinstalled primary must end at exactly 9 tags +
1 faucet contact + customs.

**27. Relay push registration at launch and foreground is gated by the persisted authorization state — it mints only when renewal is due, never unconditionally.**
The mailbox authorization the relay holds lives 30 days (bark-ffi 0.25,
`RelayRegistrationService.mailboxAuthorizationExpirySecs`) and cannot be
revoked early, so re-minting on every launch is pure churn. The launch
`.task`, the `.active` scenePhase return and the APNs token observer all
route through `mintAndRegisterWithRelay`, which consults
`RelayRegistrationService.needsRenewal` against state persisted in
UserDefaults (`com.arke.relay.*`): renew only when no registration is
known, the device token changed, the registration was for another wallet's
mailbox, or the token is past the midpoint of its actual life. The
solicited paths (timer, BGTask, wake push) `forceRefresh()` first and are
exempt — they run because something asked for a refresh. Wallet deletion
and unregister clear the persisted state so a new wallet cannot inherit
"not due". Added 2026-09-26 (`Migrations/Bark-0.24.0-to-0.25.0/`).
Enforced: `WalletManager+Notifications.swift` (`mintAndRegisterWithRelay`),
`RelayRegistrationService.swift` (`needsRenewal`, `PersistedRegistration`),
`WalletDataCleanupService.swift` (`clearUserDefaults`). Tests:
`RelayRegistrationRenewalTests`, `RelayRegistrationPersistenceTests`.

## Test gaps

Rules with no pinning test, roughly by risk: 1, 3, 4, 14, 17, 22 (decision
covered, ordering not), 23 (blast radius covered, call sites not), 25 (not
testable in-process — a system kill), 26 (decision covered; the gate's wiring
to real import events is on-device only). Covered since
2026-08-14: rule 8 (`LaunchSequence`, `ExitProgressionLogic.swift`) and
rule 2's decision matrix (`ImportRecoveryLogic`,
`BarkWalletFFI+WalletCreation.swift`) — the pattern to follow for the rest.
Next candidate: wallet-detection decisions (rules 3/4/14, overlaps the
optional startup-detection Phase 5 refactor).
