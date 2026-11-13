# Device Linking

**Status:** scope pass DECIDED 2026-11-13 (Christoph, in session). Build
pending; order of work decided below. Nothing in this document has been
built, run or tested. Code claims are read from the tree at `8904ca2`.

Parent: `Architecture/Multi_Device_Design.md` (principles, scenario catalog,
failure modes). This document is the design the 2026-10-10 "explicit device
linking" decision called for, widened on 2026-11-13 from one screen to the
per-device state model and the flows that move a device between states.

## 1. Why a state model, not a screen

The app never holds one explicit answer to "what is this install's
relationship to the account's wallet". It infers that answer at every launch
from six scattered signals: seed in the keychain, wallet hash in iCloud KVS,
the device's own registry row, its KVS primary flag, the local demotion flag
and the local-deletion tombstone. Every multi-device defect in the November
contract audit (`Development/Contract_Audit_2026_11.md` A.1–A.3, A.10–11)
and every "device is there but not quite synced" message in the Devices
screen is a symptom of that gap. A link screen alone would add a seventh
signal. The state model replaces the inference with a record and makes the
flows transitions between named states.

## 2. The per-device state model (DECIDED 2026-11-13)

Each install is in exactly one state. The evidence column is the invariant
the code enforces; anything that does not match a row is "not linked" and
must not open bark.

| State | User sees | Evidence that defines it |
|---|---|---|
| No wallet | Onboarding | No seed, no account hash |
| Found, not linked | Link screen | Account hash or seed present, no valid link record |
| Secondary (linked) | Read-only wallet | Valid link record, own row not primary |
| Primary (linked) | Full wallet | Valid link record, own row primary |
| Linked to a wallet the account no longer has | Launch-check screen | Link record present, account hash gone and seed definitively absent, or account hash differs |

The former "Left" state (local delete → rejoin screen) is removed
(DECIDED 2026-11-13, see §6.4). "Unlinked by another device" is not a
separate state: it is "Found, not linked" with a reason, see §3.

### 2.1 The link record

Per-install, in UserDefaults, so that app deletion removes it (absence must
mean "ask"). Fields: the wallet hash this install linked, the link date.
Written by create, import and the link screen's acknowledgement. Cleared by
"Delete from this device". Never synced.

A separate breadcrumb survives a local delete: the hash of the wallet this
install last held plus the deletion date. It exists for one purpose: when
the keychain is unreadable and KVS is blank, route to the link screen's
waiting variant instead of onboarding. It replaces the tombstone's
KVS-transient job (§6.4).

### 2.2 The link record is valid when

- its hash equals the account hash in KVS, **or** KVS holds no hash while
  the seed is present (a KVS blank is a known transient; see §7.4), and
- the device's own registry row exists in the local store.

Rows are written locally at registration and deleted only by the registry
service (`unlinkDevice`, `unregisterCurrentDevice`, `dedupeOwnRecords`) or
the cleanup service (contract rule 23), so a present record with a missing
own row means another device unlinked this one. That routes to the link
screen with the "removed by another device" copy, and the device can only
re-link as a secondary.

### 2.3 The evidence rule (DECIDED 2026-11-13)

No path opens bark without a valid link record and an own row that says
primary. This closes three items at once:

- Tier 0 "`checkReadOnlyMode()` infers primary": a missing or unreadable row
  becomes read-only, not primary. The sibling `shouldBlockWalletAccess`
  returns `true` when the device ID is unreadable or when no layer has an
  opinion, instead of `false`.
- The open question "must a background or push wake refuse to initialise
  the wallet on an unlinked install": yes, and today it would not.
  `BackgroundTaskCoordinator.scheduleRefresh` is called on every
  backgrounding with no wallet check (verified, `ArkeMobile.swift`
  scenePhase handler), and the headless open in
  `refreshRelayAuthInBackground` passes `shouldBlockWalletAccess` on a
  fresh install because no layer has written anything (verified by reading
  both bodies). Today the window is small because detection registers the
  device before the first initialize, which writes the mirror flag; under
  linking an unlinked install writes nothing, so the gate must fail closed.
- S4's returning lost primary (audit A.1): its row is gone, so it lands on
  the link screen. The device run of 2026-11-13 showed no spend window,
  only a primary-layout flash before the mode check caught up
  (`Read_Only_Mode.md`); the rule turns that race into a decision.

Proposed contract rule text, to be added to
`Initialization/Launch_Sequence_Contract.md` when step 1 of the build
lands (not before; the contract records enforced invariants):

> **28. No path opens bark without a valid link record and a primary own
> row; "unknown" is read-only.** The link record is per-install state
> whose absence means "ask", written only by create, import and the link
> screen. A missing or unreadable registry row, an unreadable device ID, or
> a mirror with no opinion all resolve to read-only, never to primary. The
> launch path, the promotion path and the headless background open all run
> the same check before `openWalletIfNeeded`.

## 3. Vocabulary (DECIDED 2026-11-13)

- **Primary** and **Secondary** are the only role words in UI copy.
  "Primary device", "Secondary device", "Make this device primary", "Make
  this device secondary". No "spending device", "viewing device", "main
  device" or "hand over".
- **Link**, not join. "Link this device", "linked on 3 November", "Unlink".
- Sync state is shown only where it gates an action the user can take, and
  there it is specific with the action beside it. Everywhere else the UI
  shows the data it has and labels it by what it is ("Last seen 2 hours
  ago" from the registry row, "Linked 3 November" from the fast entry).
  No "Syncing devices…" in lists, no "Unrecognized device", no explainer
  text about stores (§5.3).

## 4. Flows

Five flows. Each is a transition in §2; each has no state of its own, so
every screen is derived from the registry, the backup slot and the link
record, and killing the app mid-flow is harmless.

### 4.1 Create or import (exists)

Unchanged except for one line: a successful create or import writes the
link record. Both already register with `allowPrimaryClaim: true`
(verified, three call sites in `WalletManager+Wallet.swift`). The
in-wallet phrase sheet stops using this path, see 4.2.

### 4.2 Link this device (new)

**Trigger.** Any launch where the account has a wallet, by KVS hash or
synced seed, and this install holds no valid link record. Also when the
hash appears while the user sits in onboarding; `MainView_iOS`'s KVS
observer already re-runs detection on that key (verified). Never on a
launch with a valid record, so set-up devices keep the fast path.

**One screen, one action, four copy variants** on the same view:

| Reason | Copy (first draft) |
|---|---|
| New here | "This iCloud account has a wallet, created on Christoph's iPhone on 12 March. This iPhone will show it. Spending stays on the primary device until you move it here." |
| This device before (own old row found after the import) | "This iPhone was the primary device for this wallet. Continue as before." |
| Removed by another device (record present, own row gone) | "This iPhone was removed from the wallet's device list on Christoph's Mac. Link it again to keep viewing." |
| Removed by the user here (breadcrumb present) | "You removed this wallet from this iPhone on 3 November. Link it again to keep viewing." |

**Acknowledging** writes the link record, registers the device with
`allowPrimaryClaim: false`, and starts normal initialisation. If the
device's own old row says primary, `dedupeOwnRecords` keeps it primary as
today (verified), so a reinstalled primary regains spend rights through
an explicit tap. Other devices receive the "new device joined" local
notification (DECIDED 2026-10-10 as the receiving end of this event).

**The wait.** The screen hosts the first CloudKit import pass, which is
where the origin details and the device's own old row come from. The
action enables when the import pass lands or after about 30 seconds,
whichever is first (DECIDED 2026-11-13); on timeout the copy switches to
"iCloud is slow right now. You can continue; details fill in later." The
gate is `CloudKitFirstImportGate`, already used by rule 26 seeding.

**The seed.** If present, nothing more. If absent, the screen says iCloud
Keychain has not delivered the key yet and offers "Enter recovery phrase".
That entry saves the seed and updates the row's `hasSeed`; it never calls
bark's import. Today's in-wallet sheet goes through `importWallet`, which
creates a local bark database and registers with the primary claim
allowed (verified: `ActivityView_iOS` → `ImportWalletSheet_iOS` →
`ImportBackupFileView_iOS.importWallet` → `WalletManager.importWallet`),
which is the surprise primary claim in S2's sub-case. The in-wallet sheet
switches to the same seed-only save.

**Rulings (DECIDED 2026-11-13):**

- A primary device reinstalling sees the screen, with the "this device
  before" copy once its row has imported.
- No decline button. One wallet per account means there is nothing to
  decline into; closing the app is "not now".
- A seed arriving later is not a second acknowledgement.
- Existing installs on upgrade self-heal silently: seed found, own row in
  the local store, detection definitive → write the record without a
  screen. Everyone else sees the screen once.
- Background and push wakes refuse to open bark on an unlinked install
  (§2.3).

### 4.3 Make this device primary (replaces promote/demote sheets)

**Entry.** Devices screen on any secondary, "Make this device primary",
always visible. Later also from the link screen as "this is my new phone"
(the S5 migration assistant, DECIDED 2026-11-13: after the flow exists,
not in the first build), and from the deferred no-primary banner.

**Step 0: this device is able.** Seed present, else the seed-only phrase
entry from 4.2. Closes audit A.2 (a seedless device promoting into the
seed-missing branch; verified that neither the button nor
`promoteThisDeviceToPrimary` checks the mnemonic).

**Step 1: branch on the registry, wallet-scoped.** If a primary row exists
for this wallet: "Do you still have Christoph's iPhone?" with its last-seen
date, so a stale row reads as the hint it is. Yes → A. No → B. No primary
row → C. This fixes audit A.10 (the button's check is unscoped today while
the warning's is wallet-scoped).

**Branch A, handover.** Instruction: "On Christoph's iPhone, open Arké, go
to Settings › Devices and tap Make this device secondary. Keep both
devices online." Then a waiting state with two conditions, in order:

1. The old primary's flag flips to not primary. Fast signal: the other
   device's `device_<id>_isPrimary` KVS key, which any device in the
   account may read (only writing another device's flag is forbidden;
   verified `writeOwnPrimaryFlag` is the sole writer). Confirmed by the
   row.
2. The backup in iCloud Drive is newer than that flip **and downloaded
   here**. Today `WalletBackupService` reads the ubiquity-container file
   with plain `FileManager` attributes and never requests a download or
   queries iCloud metadata (verified), so a promotion right after the flag
   flip would restore whatever stale copy the local container holds, or
   find none and fall into rule 3's create. New code: an `NSMetadataQuery`
   over the ubiquity container, waiting for
   `NSMetadataUbiquitousItemDownloadingStatusCurrent` after
   `startDownloadingUbiquitousItem`; the demote side waits on
   `NSMetadataUbiquitousItemIsUploadedKey` (API names checked against the
   Apple docs 2026-11-13, not yet exercised in this project).

Only then "Make this device primary" enables, re-checks from fresh
evidence that no primary row exists (same shape as
`fullWipeStillJustified`), promotes and restores. Timeout after a few
minutes: "Still waiting. Make sure Christoph's iPhone is online with Arké
open. Don't have it anymore?" leads into B.

Why this order is a funds requirement, not a preference (derived): demotion
closes bark on the old primary via `closeWalletForMigration` →
`shutdownWallet`, which writes the final backup; `restoreWalletIfNeeded`
restores it when newer than the local file. A one-sided swap from the
secondary would promote before that backup exists, and bark's offchain
state cannot be rebuilt from the seed.

**The old primary's side.** "Make this device secondary" (today's demote,
renamed) waits for its own backup upload to complete before reporting
done, then says "Now continue on your other device". It stays a standalone
action because the handover instruction points at it (DECIDED 2026-11-13).

**Branch B, takeover (lost primary).** One screen, two honest statements:
"If someone could unlock Christoph's iPhone, they can read this wallet's
recovery phrase. Consider moving your funds to a new wallet afterwards."
and "This device continues from the last backup Christoph's iPhone made on
3 November." Then one action that unlinks that device and promotes.
Confirmation strength: plain confirm plus the future presence check, no
phrase words (DECIDED 2026-11-13; nothing irreversible to funds happens
here). If the lost device resurfaces, its row is gone, it lands on the link
screen and can only link as a secondary.

**What a stale backup sees, verified 2026-11-13** by source research at
bark `lib-0.8.0` / `server-0.8.0` and bark-ffi `4a1c1c0` (the revision the
built bindings pin; details in §7). Incoming state recovers on its own:
the server mailbox is read from the client's own checkpoint and a fetch
never consumes a message, so a restored database replays arkoor receives
and round-completion notices from its old checkpoint, as long as the
server still holds the rows (production retention not verified). Outgoing
state does not: nothing in a normal sync reconciles locally spendable
VTXOs against the server, so amounts the lost device spent after the
backup still show as spendable until a round notice touches them or a
spend is rejected with `vtxo … is not spendable (state: spent)`. There is
no full rescan for an existing database; `recoverVtxos(vtxoIds:gapLimit:)`
takes known ids. So:

- Branch A has no stale window by construction, which is the second
  reason the handover order is required.
- Branch B's copy says: "This device continues from the backup Christoph's
  iPhone made on 3 November. Payments received since then appear after the
  first sync. Amounts sent from that device since then may still show here
  until the next refresh." Build step 4 checks whether calling
  `recoverVtxos` with every locally spendable id marks server-spent ones as
  spent; if it does, run it once after takeover and drop the last sentence.

**Branch C, direct promotion (no primary row).** Confirm with the backup
date shown, promote, restore. Today's "No Active Wallet" case.

**Security check.** Promote, demote and takeover are rows in the
gated-actions table (Tier 0 "Security checks first"). The flow leaves the
presence-check slot so it is born gated when that item lands.

### 4.4 Delete wallet (exists; two outcomes, no new flow)

The single delete flow stays: the assessment decides the scope and the copy
says which one the user gets. Phrase confirmation, export step and the
override for an unreadable registry are unchanged.

**Local outcome** (other devices linked): local wipe, device unregistered,
link record cleared, breadcrumb written. Routing afterwards goes to the
link screen's "you removed this wallet" variant, which doubles as the
completion screen. On a primary the first screen gains one line: "This is
the primary device. Make another device primary first, or the wallet
continues from this device's last backup." Removal stays allowed on the
primary (DECIDED 2026-11-13): a user with one device must be able to
remove the wallet without another device being online, and the local-only
delete still writes its final backup (contract rule 17), so a secondary
then takes branch C.

**Full outcome** (last device): unchanged.

**Blocked case addition** (DECIDED 2026-11-13): each named blocker gets
"I no longer have this device", which runs the existing `unlinkDevice` and
re-assesses. Clear the last one and the same flow reaches the full outcome
with the phrase check still in front. This is the S7 "unlink-in-flow"
piece deferred in September because unlink looked like a gentler door to
an irreversible outcome; under the state model unlinking a live device
only sends it to the link screen, so the irreversible step keeps its own
gate. With fast entries carrying names (§5.2) the blockers read "Still
linked: Christoph's Mac, last seen 2 hours ago. iPhone 17, linked 3
November."

### 4.5 Launch check and its screen (new; absorbs S10 and S7's aftermath)

The link-record validation at launch is one pure function over five inputs:
record hash, account hash, seed status, iCloud identity present, own row
present. It replaces `tombstoneRouting`. Three of its outcomes share one
view with two safe exits, "Remove from this iPhone" and a second exit per
case; nothing happens without a tap.

| Case | Inputs | Copy | Second exit |
|---|---|---|---|
| Deleted elsewhere (full wipe on another device after this one was unlinked) | record X, no hash, seed `.notFound`, iCloud identity present | "This wallet was deleted from your iCloud account on another device. Its data is still on this iPhone." | "Restore with recovery phrase" (import) |
| Signed out of iCloud | record X, no hash, no iCloud identity | "You are signed out of iCloud. Spending and sync need the wallet's account." | "Sign back in" (re-detects on return) |
| Different iCloud account | record X, hash Y | "This iPhone is signed in to a different iCloud account than this wallet's." | "Sign back in" |

Rulings (DECIDED 2026-11-13): the aftermath screen is shown only on
definitive absence (hash gone and seed `.notFound`, the same corroboration
rule the tombstone used); the signed-out and different-account cases of
S10 (DECIDED 2026-08-19) share the view; detection re-runs on the KVS
`NSUbiquitousKeyValueStoreAccountChange` reason, which today is only
logged (verified, `MainView_iOS.handleUbiquitousStoreChange`). Linking the
new account's wallet is possible only after removing X; local files are
never paired with another account's data.

Checked 2026-11-13 against the Apple docs: the sign-out signal is
`CKContainer.accountStatus()` returning `.noAccount`, with `CKAccountChanged`
as the second re-detection trigger; Apple says CloudKit clients must not use
`ubiquityIdentityToken` for this. The per-app iCloud toggle is only partly
settled: `userRecordID()` returns `.notAuthenticated` when "the user
disables iCloud" with an account present, and whether that covers the
per-app switch needs one device check. Needed only for the optional hint.

## 5. The Devices screen

### 5.1 Shape (DECIDED 2026-11-13)

Status plus one action.

- **This device:** name, "Primary device" or "Secondary device", and only
  when the seed is missing: "Wallet key not on this device yet" with the
  seed-only phrase entry.
- **One action by role.** Secondary: "Make this device primary" → flow 4.3.
  Primary: "Make this device secondary", which waits for its upload.
- **Other devices:** name, role, "Last seen …" or "Linked …", unlink in the
  context menu as today.
- **Removed:** the "No Active Wallet" section (flow 4.3 branch C has a
  visible button), the promote and demote sheets, the two scoping bugs
  (A.10, A.11) since nothing depends on them any more.

Desktop keeps its current screen until parity resumes; the Shared pieces
are written so it can adopt them.

### 5.2 Fast entries carry identity (DECIDED 2026-11-13)

Today the KVS mirror entry `com.arke.device.registered.<hash>.<id>` stores a
`Double` registration timestamp (verified, `registerDeviceInKVStore`). It
gains device name and platform; the role is already readable from
`device_<id>_isPrimary`. Readers (`otherRegisteredDeviceIds`,
`otherDeviceReport`) accept both value shapes, since existing entries stay.
A device known only from its fast entry then draws a complete row: name,
platform, role, "Linked 3 November". The only thing the registry row adds
is the heartbeat.

### 5.3 No sync state in the list (DECIDED 2026-11-13)

Rows are drawn from whichever store answers. The 48 h `mirrorSettleWindow`
keeps governing the delete flow's override offer but is no longer visible
in the Devices screen. Pre-fix ghost entries without a name show "Device
linked 3 November", unlinkable. The only place sync state is spoken is the
blocked delete case, beside its remedy, and the two bounded waits (link
screen, handover), which end in a specific instruction.

## 6. What this removes

1. **The local-deletion tombstone** (`SecurityService.localDeletionTombstoneKey`,
   `tombstoneRouting`, `TombstoneRoutingTests`, `TombstonePersistenceTests`)
   and the `.walletAvailableToRejoin` route. Replaced by record absence
   plus the breadcrumb (§2.1).
2. **`RejoinWalletView`.** Its job is the link screen's "removed by you"
   variant.
3. **`DemoteDeviceSheet`, `PromoteDeviceSheet`** and the "No Active Wallet"
   section, replaced by flow 4.3.
4. **The "Left" state** and S6's rejoin walkthrough. Contract rule 20 is
   reworded from "routes to the rejoin screen" to "routes to the link
   screen". `Features/Wallet_Deletion_And_Rejoin.md` Phase 2 is marked
   superseded. Its Tier 2 two-device verification debt ("Deletion +
   rejoin") is retired with it rather than paid.
5. **The 2026-10-10 record's clause** "retires the pre-open network
   reconcile patch": wrong. Rule 22 runs on every open including headless
   (audit B); the link gate only moves a fresh install's reconcile behind
   the screen. Corrected in the Done log entry of 2026-11-13.

## 7. Facts this design rests on

Labelled per `Development/Change_Review_Playbook.md`.

**Verified (read at `8904ca2`):**

- `performWalletStateDetection` routes: tombstone → keychain `.found` →
  `checkDevicePrimaryStatus` → `walletWithSeed` / `walletActiveElsewhere`;
  `.notFound` + KVS hash → `walletActiveElsewhere`; neither → `noWallet`.
- `registerDeviceIfNeeded` runs on every launch and foreground path in
  `MainView_iOS` (five call sites) with `allowPrimaryClaim: false`;
  create and import register with `true`.
- `checkReadOnlyMode` sets `isReadOnlyMode = false` on a nil row and on
  error; `shouldBlockWalletAccess` returns `false` on an unreadable device
  ID and when no layer blocks.
- `unlinkDevice` removes mirror keys matching `.<deviceId>` and the row;
  `mirrorKeys` does not match `device_<id>_isPrimary`.
- `promoteThisDeviceToPrimary` refuses while a wallet-scoped primary row
  exists; `LinkedDevicesView_iOS.checkForPrimaryDevice` calls
  `getPrimaryDevice()` unscoped.
- `demoteThisDevice` → `.deviceDemotedFromPrimary` → `closeWalletForMigration`
  → `shutdownWallet`; `restoreWalletIfNeeded` compares file modification
  dates; `WalletBackupService` reads the ubiquity file with
  `attributesOfItem`, no download or metadata query.
- The device-ID keychain item is `WhenUnlockedThisDeviceOnly`,
  non-synchronizable; `dedupeOwnRecords` keeps a primary row over a fresh
  secondary one and rewrites the KVS flag.
- `scheduleRefresh` is called on every `.background` scene phase with no
  wallet check; the headless open checks `mnemonicKeychainStatus` then
  `shouldBlockWalletAccess` then opens.
- The KVS account-change reason is logged and not acted on.
- The mirror entry value is a `Double` timestamp.

**Derived (traced, not run):**

- An ex-primary unlinked by another device re-registers before its mode
  check reads the row, so the relaunch goes read-only after a UI flash
  (device run 2026-11-13; the earlier trace predicted a full session and
  was wrong about ordering, `Features/Read_Only_Mode.md`).
- Promotion before the old primary's final backup has synced restores
  stale or no offchain state.

**Checked 2026-11-13 (Apple docs via DocumentationSearch; none exercised
in this project yet):**

- Sign-out signal: `CKContainer.accountStatus() == .noAccount`, re-detect on
  `CKAccountChanged`. `ubiquityIdentityToken` is nil for sign-out *and* for
  iCloud Drive unavailable, and Apple tells CloudKit clients not to use it.
- Backup arrival: `NSMetadataUbiquitousItemDownloadingStatusKey` with values
  not-downloaded / downloaded / current; `startDownloadingUbiquitousItem`
  fetches; `NSMetadataUbiquitousItemIsUploadedKey` for the demote side.
- Keychain deletion: deleting a synchronizable item "affects all copies of
  the item". Guaranteed, no timing bound; the §7.4 window stays.
- Per-app iCloud toggle: `userRecordID()` → `.notAuthenticated` when "the
  user disables iCloud" with an account present. Whether that is the per-app
  switch: one device check, optional hint only.

**Verified by source research 2026-11-13** (bark `lib-0.8.0`,
`server-0.8.0`, bark-ffi `4a1c1c0` = the revision pinned by the built
bindings `golang/v0.26.1`; run as a read-only prompt against the local
checkouts, every item file-cited there):

- Normal sync runs mailbox processing, pending rounds, boards, force-exit
  detection and a catch-up for VTXOs already in the database. No key scan;
  the xpub scan runs only in `recover_from_seed` on a creating open.
- Mailbox reads are non-consuming and the checkpoint is client-local, so a
  restored database re-fetches everything after its old checkpoint.
- No sync-time reconciliation of locally spendable VTXOs against server
  spend state; rejection comes at spend time (`not spendable (state:
  spent)`, round: `input vtxo(s) not spendable`).
- Round outputs after the backup arrive through the round-completion
  mailbox notice, which rebuilds the participation from server data.
- `recoverVtxos(vtxoIds:gapLimit:)` exists in the bindings and takes known
  ids; cost scales with the ids supplied. Whether it marks known-but-spent
  VTXOs spent is **not yet verified** (step 4).
- Open loads stale exit state; `syncExits()` is the explicit status sync.
- bark's `sync` logs branch errors instead of returning them, so an FFI
  `sync()` success does not prove every branch ran.
- Not verified: production mailbox retention, and the 0.8.1 bindings
  (`v0.31.0+bark-0.8.1`) exist but change nothing in this area.

## 8. Order of work (DECIDED 2026-11-13)

Each step is Tier 0 or Tier 1 and gets its own adversarial pass; the full
mobile suite runs once per step after the pass. Steps 1–2 and 4–5 each end
in a two-phone device day (`Release_Train.md`, Device stage).

1. **Evidence rule and link record.** Pure routing function with its
   matrix test; `checkReadOnlyMode` and `shouldBlockWalletAccess` fail
   closed; registration and the headless open gated on the record; upgrade
   self-heal. Closes "`checkReadOnlyMode()` infers primary" (moved from
   Tier 0 to Tier 1 on 2026-11-13 after the device run showed a race and a
   UI flash, not a spend window).
2. **Link screen.** Four copy variants, first-import wait, seed-only phrase
   entry (also replacing the in-wallet sheet's bark import), "new device
   joined" notification, tombstone and rejoin removal, post-delete routing.
3. **Fast entries carry identity; Devices screen rework.**
4. **Make this device primary.** Branches A/B/C, backup-arrival wait with
   metadata query and download, demote waits for upload, fresh re-check
   before the write, presence-check slots. Includes the `recoverVtxos`
   check from 4.3 B, which decides the takeover copy's last sentence.
5. **Delete flow blocker remedy and the launch-check screen.** Per-blocker
   unlink, aftermath / signed-out / different-account view, re-detection on
   account change.
6. **Docs.** Contract rule 28 and rule 20 rewording, S2–S10 walkthrough
   rewrites, `Read_Only_Mode.md` and `Device_Registry_Reference.md`
   updates, de/ja/zh-Hant for the new keys.

## 9. Sweep list for the build

Every site the pattern touches, to be marked covered / exempt / missed at
each step:

- Detection: `SecurityService.performWalletStateDetection`,
  `checkDevicePrimaryStatus`, `tombstoneRouting`, `WalletState`.
- Routing: `MainView_iOS.checkForExistingWallet` (both branches),
  `handleUbiquitousStoreChange`, `ArkeDesktop/Views/MainView.swift`
  (same five registration sites; desktop parked but must compile).
- Gates: `WalletManager.performInitialization`, `checkReadOnlyMode`,
  `shouldBlockWalletAccess`, `WalletManager+Notifications.refreshRelayAuthInBackground`,
  `BackgroundTaskCoordinator.handleRefreshTask` / `handleAuthWakePush`.
- Registration writers: `registerCurrentDevice`, `registerDeviceInKVStore`,
  `writeOwnPrimaryFlag`, `updateCurrentDeviceHasSeed`, `dedupeOwnRecords`,
  `reconcilePrimaryConflicts`.
- Role changes: `promoteThisDeviceToPrimary`, `demoteThisDevice`,
  `unlinkDevice`, `unlinkAllOtherDevices` (desktop).
- Deletion: `WalletDataCleanupService.performDeleteWalletData`,
  `SharedStateWipeCoverage` (new entries: link record, breadcrumb; both
  `deviceLocal`), `recordLocalDeletionTombstone` callers.
- Readers of the mirror: `otherRegisteredDeviceIds`, `otherDeviceReport`,
  `shouldOfferOverride`, `UnsyncedDeviceRow`, both `LinkedDevicesView`s.
- Strings: every new key with `defaultValue:`, then
  `Scripts/apply_translations.py`.

## 10. Device verification (owed before any step is called done)

Two phones on signet, never the simulator for anything seed-touching.

1. Fresh install on B with A primary: link screen, origin named after the
   import, acknowledge, read-only wallet, A gets the notification.
2. B with iCloud Keychain off: link screen without seed, "Enter recovery
   phrase", seed-only save, B stays secondary, no bark import in B's log.
3. Handover A → B: instruction on B, demote on A completes after upload,
   B's wait ends on both conditions, B promotes and restores the newest
   state, A read-only. Repeat with A offline to see the timeout path.
4. Takeover: unlink A from B, promote B; power A back on: link screen,
   links as secondary, never spends (the Tier 0 window closed).
5. Delete from B (local): link screen with "you removed" copy; relaunch
   stays there; acknowledge re-links as secondary.
6. Delete everywhere from A with B unlinked and offline: B's next launch
   shows the aftermath screen; remove, then onboarding.
7. Upgrade: an existing linked install on the new build opens with no
   screen (self-heal line in the log).
8. BGTask on an unlinked install: back-grounded link screen, forced BGTask
   run from Xcode, log shows the refusal and no bark open.
