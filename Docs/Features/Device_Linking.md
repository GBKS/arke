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
observer already re-runs detection on that key (verified). Also when a
running session is live-unlinked (§11.6): the closure ends by re-running
detection, so the device goes from the open wallet to the link screen's
"removed by another device" variant instead of sitting read-only until
relaunch (DECIDED 2026-11-14, Christoph's question). Never on a launch
with a valid record, so set-up devices keep the fast path.

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
  before" copy once its row has imported. If that row has already imported
  before the first detection runs, the install self-heals silently instead
  (same predicate as the upgrade cohort; noted 2026-11-14, F6).
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

## 11. Step 1 build plan (2026-11-13)

Scope: the evidence rule and the link record, nothing visible. The link
screen, the tombstone removal and the route changes are step 2. Claims
labelled as in §7; everything below was read at `cca502d`.

### 11.1 Two facts that shape the design

- **The headless background path has no registry.** A BGTask or wake-push
  launch runs `App.init`, which wires only the BGTask coordinator; nothing
  on that path calls `configureServices` (verified; its callers are the two
  `MainView` `.task` bodies, `onWalletReady`, `WalletManager.setModelContext`,
  `setPreviewContext` and the unused `ServiceConfigurationView`, none
  headless). Layer 3 of the old gate threw `noModelContext` there, which
  `try?` turned into "no row" and read as "pass". Fix: `App.init` also
  hands the model container to `WalletManager.headlessModelContainer`, and
  `DeviceRegistrationService.ownRowEvidence` reads the row through a fresh
  context on it when no context is configured. Only when even that is
  missing (desktop) does the gate fall back to the KVS mirror's own
  `primary` flag, and that flag is now removed by unlink, unregister and
  the full wipe, so it can only be as stale as the device's last KVS sync
  (adversarial pass 2026-11-13, F1). A device that was offline when it was
  unlinked still holds its old row and flag until a sync arrives; no local
  rule can know better, and the first foreground launch settles it.
- **The device-ID keychain item is `WhenUnlockedThisDeviceOnly`**
  (verified, `getOrCreateDeviceId`), while the seed is `AfterFirstUnlock`.
  On a locked phone the headless gate cannot read the ID; today that
  returns "pass", under the rule it must block, and that would end
  background refresh while locked. Step 1 migrates the item to
  `AfterFirstUnlockThisDeviceOnly` through the existing
  `migrateItemToAfterFirstUnlock` helper, generalised for a
  non-synchronizable item and a target class. The `ThisDeviceOnly` half
  is unchanged, so contract rule 16 holds (Apple: items of that class "do
  not migrate to a new device", checked 2026-11-13).

### 11.2 Changes

1. **`DeviceLinkStore`** (new, `Shared/Services/DeviceLinkStore.swift`):
   UserDefaults record `com.arke.link.walletHash` + `com.arke.link.linkedAt`;
   `recordLink(walletHash:)`, `clearLink()`, `record()`. Pure
   `validity(record:accountHash:seedPresent:ownRow:) -> LinkValidity`
   with `.valid`, `.noRecord`, `.walletChanged`, `.ownRowMissing`, and the
   §2.2 rule that a blank KVS with the seed present is still valid. Written
   by `registerCurrentDevice` after its save (one choke point for create,
   import, both platforms' detection paths; the detection write is the
   step-1 stand-in for the link screen and is narrowed to the upgrade
   self-heal in step 2). Cleared by the cleanup service on every deletion.
   Inventory entry in `SharedStateWipeCoverage`, scope `deviceLocal`.
2. **Access verdict** (`WalletManager`): the three layers become a pure
   `accessVerdict(deviceId:wasDemoted:mirror:ownRow:) -> AccessVerdict`
   with `.allow` and `.block(reason)`, reasons `demoted`, `secondary`,
   `noRegistration`, `deviceIdUnreadable`, `registryUnavailable`. Rules:
   unreadable ID blocks; demotion flag blocks; mirror not-primary blocks;
   own row secondary or absent blocks; registry unavailable blocks unless
   the mirror says primary. `shouldBlockWalletAccess` returns the verdict;
   the launch path treats every block as read-only, the headless path maps
   `demoted` / `secondary` to `.nothingToDo` and the unknowns to `.failed`
   so the wake chain retries once the phone is unlocked.
3. **`checkReadOnlyMode`**: nil row or error → read-only, with the log
   line "no device registration yet, read-only until this device
   registers". The "assuming primary" line goes away.
4. **Headless gate**: `refreshRelayAuthInBackground` adds the link-record
   check before the access check: no valid record → `.nothingToDo` with
   its own log line (nothing to refresh for an install that never linked).
5. **Device-ID migration**: run once per launch where the keychain is
   readable, from `getOrCreateDeviceId` after a successful read.
6. **Tests** (`Tests/Shared`): `DeviceLinkValidityTests` (matrix),
   `WalletAccessVerdictTests` (every reason, the unavailable + primary
   mirror exception, the fresh-primary case where mirror and row agree),
   `DeviceIdAccessibilityMigrationTests` for the non-synchronizable item
   migrating to `AfterFirstUnlockThisDeviceOnly` with the re-add fallback
   disabled (F5: a lost device ID would split the device's identity).
7. **Docs**: contract rule 28 added, rule 14 and 16 amended; the Tier 1
   "`checkReadOnlyMode()` infers primary" entry closes to the Done log.

### 11.3 Known step-1 interim behaviour

- **Reinstalled primary (S9):** the first launch after a reinstall finds no
  own row, registers a *secondary* row with the flag false, and is a
  settled secondary (headless wakes return `.nothingToDo`) until CloudKit
  imports the old primary row and `dedupeOwnRecords` runs from the CloudKit
  observer or a heartbeat; the next launch is then primary. If the import
  never arrives, the user promotes from Devices. Today it opens as primary
  immediately by assumption. Step 2's link screen hosts that import and
  shows "this device before". Accepted for the interim.
- **Create or import whose registration threw:** the row is missing, the
  wallet opens read-only; the launch path's detection registration then
  writes a secondary row, after which the Devices screen offers promotion
  (no primary row visible). Two steps, not one; promotion with no row at
  all throws `deviceNotFound`. The registrations in create and import now
  hash the phrase in hand instead of reading the hash back from KVS, so a
  nil KVS read (no iCloud account) no longer skips them (F4).
- **Account switch (S10):** until step 2 narrows the detection-path write,
  a device signed into a different account registers under that account's
  hash and the link record follows, so `.walletChanged` is not reachable
  in step 1. Step 5 owns this case.
- **The UI flash** (route chosen before the mode is known) stays until
  step 2 decides route and mode together.

### 11.4 Sweep

`shouldBlockWalletAccess` callers: `performInitialization`,
`refreshRelayAuthInBackground` (both covered). `checkReadOnlyMode`: one
caller (covered). `getOrCreateDeviceId`: the registration service and the
duplicate reader `SecurityService.getDeviceIdFromKeychain` (reads by
service and account, class-agnostic; exempt). Registration writers: all
through `registerCurrentDeviceUnprotected` (covered by the single write).
Deletion: `performDeleteWalletData` Step 5 area (covered), `clearUserDefaults`
(covered, same call). Desktop `MainView.swift`: no change needed, the
record write sits in the Shared service.

### 11.5 Build record (2026-11-13)

Built as planned in §11.2 with four review-driven additions. Changes:
`DeviceLinkStore` (new), `DeviceRegistrationService` (record write,
`ownRowEvidence`, `getCurrentDevice` propagates, `primaryFlagKey`, flag
removal in `removeMirrorEntries` and `clearDeviceRegistrationsFromKVStore`,
device-ID migration), `SecurityService.migrateItemToAfterFirstUnlock`
(parametrised, `allowReaddFallback`), `WalletManager` (`AccessVerdict`,
`accessVerdict`, `walletAccessVerdict`, `headlessModelContainer`,
`checkReadOnlyMode` fails closed), `WalletManager+Notifications`
(link-record check, verdict mapping), `WalletManager+Wallet` (three
registrations hash the phrase), `WalletDataCleanupService` (clear record,
inventory), `ArkeMobile.swift` (container wiring), contract rules 14, 16,
28.

**Adversarial pass** (fault-class-reviewer, uncommitted diff): seven
findings, dispositions:

- F1 CONFIRMED: headless exception trusted the self-written, never-cleared
  mirror flag → registry read through the app container on headless
  launches; unlink, unregister and full wipe remove the flag; rule 28 and
  §2.3 reworded to evidence as received. Ledger row.
- F2 CONFIRMED: `clearLink()` sits after the fallible deletion steps →
  kept there deliberately, consistent with the tombstone and the
  2026-10-16 partial-failure decision (a throwing deletion leaves a
  working, still-linked wallet); rule 28 says so instead of "every".
- F3 CONFIRMED: fetch error read as "no row" → `getCurrentDevice`
  propagates, `ownRowEvidence` maps to `.unavailable`. Ledger row.
- F4 CONFIRMED (doc) + PLAUSIBLE (lockout): promote with no row throws,
  nil KVS read-back skipped the primary registration → registrations hash
  the phrase in hand; §11.3 corrected. Ledger row.
- F5 PLAUSIBLE: device-ID loss on the re-add fallback → fallback disabled
  for that item. Ledger row.
- F6 CONFIRMED: §11.1 caller list → corrected.
- F7 PLAUSIBLE-low: S9 interim wording → §11.3 corrected.

**Tests:** `DeviceLinkValidityTests` (9), `WalletAccessVerdictTests` (10),
`DeviceIdAccessibilityMigrationTests` (2), `OwnRowEvidenceTests` (5),
`LiveUnlinkDemotionTests` (5), plus the neighbouring suites on the `Arke
Tests` simulator; full mobile suite after §11.6: 694 tests, 689 passed, 5
skipped (live probes), 0 failed (2026-11-14).

**Device checks done (2026-11-14, Christoph):** an existing primary's first
launch on this build migrated the device-ID item and opened as primary; a
plain create-wallet run registered and opened as primary.

**Device checks (2026-11-14).** Christoph ran the unlink-then-forced-BGTask
recipe on two phones. The unlink arrived (A's log shows "Loaded 1 registered
devices" twice after B's unlink), but the forced pass ran inside the
foreground-launched process whose wallet was already open, and
`refreshRelayAuthInBackground` only runs the gate on its headless open
branch (`if !isInitialized`). The pass minted and reported `refreshed`,
which is the expected behaviour for a live primary session and says
nothing about the gate. Lesson: `_simulateLaunchForTaskWithIdentifier`
exercises the handler, not a cold background launch, so the headless gate
cannot be forced from Xcode. Two consequences:

- The headless registry read is covered by `OwnRowEvidenceTests` instead:
  a service with no configured context reads its own row through the
  fallback container (primary, secondary, absent) and reports
  `.unavailable` only when there is no container either.
- The remaining device evidence is passive: after an unlink, leave A
  backgrounded (not force-quit) for a day; the Background Activity screen's
  BGTask entries must then show `nothingToDo` or `failed`, never
  `refreshed`.

**Residual surfaced by the run, DECIDED and built 2026-11-14:** a running
primary session was not re-evaluated when its own row disappeared, so an
unlinked device kept bark open until relaunch. Built as §11.6.

**Still owed on device:** an existing primary's first launch on this build
logs "Device ID accessibility migration: migrated" and opens as primary; a
plain create-wallet run registers and opens as primary.

### 11.6 Live unlink: a running primary whose own row disappears (built 2026-11-14, DECIDED by Christoph the same day)

**Why.** The 2026-11-14 device run showed the gap: after B unlinked A, A's
running session kept bark open and syncing until relaunch. In flow 4.3
branch B the surviving device unlinks the lost primary and promotes itself
in one step, so a lost device that is in fact alive leaves two wallets open
against the server, the hazard contract rule 14 exists to prevent.

**What.** `DeviceRegistrationService.loadRegisteredDevices` remembers
whether the last load found this device's own row primary
(`ownRowWasPrimary`). When a later load finds no own row, and no deletion
of this device is in progress, the pure `liveDemotionVerdict` says demote
and the service posts `.deviceUnlinkedWhileRunning`. `WalletManager`
answers with `closeWalletForMigration(backingUp: false)`: manager state
reset, read-only, push unregistered, bark shut down **without** the final
backup. No local demotion breadcrumb is written: the row is already absent
locally, so the next launch is blocked by the gate (`noRegistration`) and
registers as a secondary.

**Why no backup.** A removed device must not write into the account's
backup slot: a takeover's new primary restores from that slot and would
pick up the lost device's state over its own, and a full wipe elsewhere
may just have emptied it (rule 17 by proxy, review F5).

**Why only the registry row, not the KVS flag.** A first build also acted
on the removal of this device's KVS primary flag as a fast signal. The
adversarial pass (2026-11-14) showed three faults in that branch: it left
no trace, so a relaunch before the row deletion arrived reopened bark as
primary and re-wrote the flag (CONFIRMED); KVS reports absent keys on
initial sync and account change too, which would have demoted a healthy
fresh primary and backed its database up into another account's iCloud
Drive on an account switch (PLAUSIBLE); and the two hooks could run two
overlapping shutdowns (PLAUSIBLE). The branch was removed. The registry
row arrives within about a minute, which is what the flow promises.

**Row deletion is never import lag.** Rows are deleted by explicit actions
(another device's unlink, this device's own deletion flow, the reinstall
dedupe that keeps one) or by a store reset (CloudKit zone reset, possibly
iCloud sign-out). A reset demotes a running primary to read-only until the
user promotes again, which is the safe direction and the S10 decision.
Whether NSPersistentCloudKitContainer purges the local store on sign-out
was not verified; both outcomes are acceptable.

**Also fixed (review F2):** `initializePrimaryMode` re-checks
`isReadOnlyMode` right after the FFI open. A demotion that lands while the
open is awaiting finds no handle to shut down and only flips the mode;
without the re-check the daemon would start under a read-only UI. Now the
handle is shut down again without a backup and initialisation stops.

**Guards.** `registrationSuspended` (the deletion switch) suppresses the
check, because the deletion deletes its own row and `runBackupNow`
bypasses the backup suspension; `unregisterCurrentDevice` clears
`ownRowWasPrimary` before its fetch. Promote and demote keep the flag in
step; a failed promote save is corrected by the next load.

**Every role, not only the primary (device run 2026-11-14).** Christoph's
step 2 checks showed a live-unlinked *secondary* staying in the wallet UI:
the first build watched only a vanished primary row, because its job was
closing bark. `liveUnlinkVerdict` now acts on any known-present own row
that vanishes: `.closeWalletAndReroute` for a primary (close bark without
backup, then `.walletClosedAfterUnlink`), `.reroute` for a secondary
(nothing to close, `.walletClosedAfterUnlink` at once). The main view
re-runs detection on that notification and lands on the link screen.
Ledger row (class 1, found on device).

**Tests:** `LiveUnlinkDemotionTests` (six cases: close-and-reroute for a
vanished primary, reroute for a vanished secondary; present rows,
unavailable registry, never-present row and deletion-in-progress all do
nothing).

**Device check (2026-11-14, Christoph):** B unlinked A while A was in the
foreground; A's log showed the "Own registration row is gone" line, A
dropped to read-only with no backup after it, and the relaunch was blocked
with `Wallet access blocked (secondary)`: the detection-path registration
won the launch race again and had already written a secondary row, so the
gate blocked one layer earlier than `noRegistration`. Same outcome, both
settled blocks. The F2 race was hit on the first try the same day: A
force-quit, B's unlink, A launched within ten seconds; the log showed
"Wallet opened successfully", then "Own registration row is gone", then
"Mode changed to read-only during the open — shutting the wallet down
again", no daemon start, A read-only. Step 1 has no open device checks.

## 12. Step 2 build plan (2026-11-14)

Scope: the link screen and everything the state model needs for it to be
the only way an install adopts the account's wallet. Read at `1e89039`.

### 12.1 Changes

1. **Launch route** (`DeviceLinkStore.launchRoute`, pure, matrix-tested):
   inputs record, left-breadcrumb, account hash, mnemonic status, own row.
   Outcomes: `.noAccountWallet` (onboarding), `.awaitingLink(reason)` with
   reasons `newDevice`, `removedHere(date)`, `removedByAnotherDevice`,
   `waitingForICloud` (keychain unreadable, KVS blank, breadcrumb present),
   `.selfHeal` (no record but own row present: an install from before the
   record existed, written silently), `.linked`, and `.walletChanged`
   (record names another wallet; step 5 owns its screen, step 2 logs and
   falls through to today's detection). `SecurityService.performWalletStateDetection`
   evaluates it first; `WalletState` gains `.accountWalletAwaitingLink(reason)`
   and loses `.walletAvailableToRejoin`.
2. **Link screen** (`LinkWalletView`, Shared, replaces `RejoinWalletView`):
   one action, copy by reason, waits on `CloudKitFirstImportGate` or 30 s,
   then re-reads the own row (→ "this device before" when the old row is
   primary) and the primary device's name. When the seed is absent it says
   so and offers "Enter recovery phrase" (iOS island). Acknowledging writes
   the record (replacing any), clears the breadcrumb, registers with
   `allowPrimaryClaim: false`, re-runs detection. Both main views call
   `activateLateDetectedWalletServices()` on this route so the import can
   land behind the screen.
3. **Seed-only phrase entry** (`SeedEntrySheet_iOS`): `ImportPhraseView_iOS`
   plus validate-against-account-hash (`.valid` only), `handleSeedImport`,
   `updateCurrentDeviceHasSeed(true)`, then `initialize()`. Replaces the
   bark import in the read-only sheet; `ImportWalletSheet_iOS` is deleted.
4. **Record ownership**: `registerCurrentDevice` writes the record only
   when none exists or the hash matches (never re-points an install at
   another wallet); create, import and the link screen write it explicitly
   with replacement.
5. **Tombstone and rejoin removed**: `SecurityService` tombstone functions
   and `tombstoneRouting`, the rejoin route and view, both main views'
   rejoin branches, the two tombstone test suites. The creation guard takes
   `leftBreadcrumbPresent` instead of `tombstonePresent`. The left
   breadcrumb (`com.arke.link.left*`) is written by the local-only deletion
   and cleared by the full wipe and by every link write.
6. **New-device notification**: the registry's load diffs other devices'
   ids; a row first seen this session and registered within the last day
   posts a local notification "iPhone 17 linked to your wallet" through
   `DeviceLinkNotifications` (skips when notifications are not authorised).
7. **Live unlink ends on the link screen**: `closeWalletForMigration(backingUp: false)`
   posts `.walletClosedAfterUnlink`; the main view re-runs detection, which
   now routes to `.awaitingLink(.removedByAnotherDevice)`.
8. **Docs**: contract rule 20 reworded, `Wallet_Deletion_And_Rejoin.md`
   Phase 2 superseded, `SharedStateWipeCoverage` entries, README.

### 12.2 Interim and risks

- Desktop (parked) gets the Shared screen without the phrase island and
  must compile.
- `.walletChanged` keeps today's behaviour until step 5.
- The rejoin strings and their translations are dropped by the build; the
  new keys ship in English until the next translation batch.

### 12.3 Build record (2026-11-14)

Built as §12.1 with three review-driven changes. Files: `DeviceLinkStore`
(left breadcrumb, `launchRoute`, `leftBreadcrumbIsStale`, replacing flag on
`recordLink`), `SecurityService` (detection step 0; tombstone section,
`tombstoneRouting` and `.walletAvailableToRejoin` removed;
`.accountWalletAwaitingLink(reason:)` added), `LinkWalletView` (new, Shared;
`RejoinWalletView` deleted), `SeedEntrySheet_iOS` (new;
`ImportWalletSheet_iOS` deleted), `DeviceLinkNotifications` (new),
`DeviceRegistrationService` (non-replacing record write, new-device
notification), `WalletManager` (`.walletClosedAfterUnlink`),
`WalletManager+Wallet` (explicit record writes, `leftBreadcrumbPresent`),
`WalletDataCleanupService` (Step 5 breadcrumb, inventory), both main views
(`linkThisDevice`, routes, loading state), `ActivityView_iOS` (seed-only
sheet), contract rule 20, `Wallet_Deletion_And_Rejoin.md` superseded note.

**Adversarial pass** (fault-class-reviewer, uncommitted diff): six findings.

- F1 CONFIRMED: the left breadcrumb was never cleared when the account
  wallet was definitively gone, so the creation guard would refuse forever
  after a wipe elsewhere → `leftBreadcrumbIsStale` and a clear at detection
  step 0, tested. Ledger row.
- F2 CONFIRMED: the screen's own `isLinking` never reset after a failed
  registration, and the record written before it re-routed to "removed by
  another device" → loading state owned by the main view; record rolled
  back when registration does not complete; the waiting and mismatch
  variants only re-run detection. Ledger row.
- F3 CONFIRMED: `.walletChanged` fell through to detection, registering the
  device under the account's new wallet while the record kept the old
  hash, which froze the headless path and silently adopted a replaced
  wallet → new `.awaitingLink(.walletMismatch)` blocks with its own copy
  and a "Check Again" button; step 5 adds the exits. Ledger row.
- F4 PLAUSIBLE: a freshly linked device could announce the long-standing
  primary when the import landed after the link → notification cutoff is
  the later of 24 h ago and this install's link date.
- F5 PLAUSIBLE: a primary whose device-ID item alone is unreadable would
  see the link screen for one session → detection marks that launch
  non-definitive so the protected-data event re-runs it; residual needs a
  keychain fault on one item only.
- F6: the "primary reinstall sees the screen" ruling holds only when its
  row has not imported before detection; §4.2 amended.

Pre-existing, not changed: the breadcrumb is written only when the KVS
hash is readable at deletion time; `"Another Device"` hard-coded in
`checkDevicePrimaryStatus`.

**Tests:** `LinkLaunchRouteTests` (12), `DeviceLinkValidityTests` (10),
`AccountWalletSignalsTests` (renamed parameter), the two tombstone suites
removed; full mobile suite 700 tests, 695 passed, 5 skipped, 0 failed.
Catalog after the build: 22 new keys extracted with their default values,
the four `rejoin_*` keys dropped.

**Device checks (2026-11-14, Christoph, two phones):** the upgrade
self-heal, the fresh-install link screen, the local removal and the live
unlink of the primary all behaved as designed ("generally works well and
feels right as a user"). One gap: a live-unlinked *secondary* stayed in
the wallet UI, fixed the same day (§11.6, `.reroute`; full suite after the
fix 701 tests, 696 passed, 5 skipped, 0 failed). The secondary live unlink
re-run passed the same day. Not run: the iCloud-Keychain-off seed entry
(`SeedEntrySheet_iOS`); Christoph has no device set-up for it, so it is
filed as Tier 2 verification debt rather than counted as done. Step 2
otherwise has no open device checks.

## 13. Step 3 build plan and record (2026-11-14)

Scope (§5.2, §5.3): the fast KVS entry carries the device's identity, and the
Devices list draws every row from whichever store answers, with no sync
state spoken. The screen's "one action by role" shape (§5.1) lands with
step 4, which replaces the promote and demote sheets by the guided flow;
until then the current buttons and the no-primary notice stay, with their
visibility check fixed to the wallet scope (audit A.10).

### 13.1 Changes

1. **`FastRegistryEntry`** (pure, in `DeviceRegistrationService.swift`): the
   value under `com.arke.device.registered.<hash>.<id>` becomes a dictionary
   `registeredAt`, `name`, `platform`. `parse` accepts the old `Double`
   (timestamp only) and the new shape; anything else parses to an entry
   with no fields, so an unreadable value still blocks (unchanged rule).
   `registerDeviceInKVStore` writes the new shape with this device's name
   and platform.
2. **`OtherWalletDevice`** gains `platform` and `isPrimary` (optional, nil
   for registry-backed entries, which the views draw from the model). The
   report fills them for mirror-only entries from the parsed entry and the
   device's own `device_<id>_isPrimary` flag, which any device may read.
3. **`UnsyncedDeviceRow`** is redrawn as an ordinary device row: platform
   icon, name, platform, "Linked 3 November", Primary or Secondary badge
   when the flag is known. No warning colour, no "Unrecognized device", no
   explainer. A pre-fix entry without a name reads "Device linked 3
   November" or "Device linked earlier". Unlink stays in the context menu.
4. **Devices list (iOS)**: the unlink dialog names the device from the row;
   `checkForPrimaryDevice` is wallet-scoped like its sibling.
5. **Tests**: `FastRegistryEntryTests` (parse both shapes, garbage, round
   trip, identity through `otherDeviceReport`).

Desktop (parked) keeps its "Not Yet Synced" header and orange frame around
the redrawn row; its parity pass removes them.

### 13.2 Build record (2026-11-14)

**Correction to §13.1 item 1 and §5.2 after the adversarial pass.** The
identity does **not** replace the value under the registration key. The
deployed build (27) reads that value `as? Double`; a dictionary there would
read as a timestamp-less entry, which `isDoubtfulBlocker` treats as doubtful
at once, so an old-build device would have been *offered* the full-wipe
override during a live new-build device's import window, the exact case the
48 h settle window exists for (F1, CONFIRMED, class 2; ledger row). The
identity now lives under a sibling key, `com.arke.device.identity.<hash>.<id>`,
a dictionary of `name` and `platform`. Old builds never read it (their scans
match the `registered.` prefix only); `mirrorKeys` removes both keys on
unlink and unregister, the full wipe clears both prefixes, and an identity
key alone never counts as a device (`FastRegistryEntryTests.identityKeysAreMirrorState`).
`FastRegistryEntry.parse(registered:identity:)` merges the two. §5.2's
"readers accept both value shapes" is withdrawn: there is one shape per key.

Other findings: F2 PLAUSIBLE, the role badge reads the device's per-device
flag while entries are per-wallet, so a multi-wallet *test* device can show
the badge of its other wallet; accepted, test devices only. F3 the unlink
dialog said "Unlink this device" for an unnamed entry → it now uses the
row's title ("Device linked 3 November"). F4 the promote-button check used
the KVS hash while the notice used the own row's hash → both now call the
same `checkForNoPrimaryDevice`. F5 an old entry without a platform showed
an iPhone icon → neutral placeholder. Also: an unnamed entry's title carries
the date, so its date line is omitted.

**Tests:** `FastRegistryEntryTests` (8), the registry report, scan, override
and mirror-key suites; full mobile suite 709 tests, 704 passed, 5 skipped,
0 failed.

**Owed on device** (two phones): after both update, B's row on A shows
name, platform and role while B's CloudKit row is still importing (fresh
reinstall of B is the easiest way to see a mirror-only row); the delete
screen on A names B by that name during the same window; unlinking B from A
removes both of B's keys (A's Devices list shows no B after B's row and
entry are gone). Not reproducible on device: the old-build reader (F1) — it
is settled by reading build 27's code.

## 14. Step 4 build plan (2026-11-14)

Scope: flow 4.3, "Make this device primary", replacing the promote and
demote sheets; the Devices screen takes its §5.1 shape (one action by
role). Read at `6c1aa69`.

### 14.1 Facts settled for this step

- **`recoverVtxos` reconciles spent state** (verified at bark `lib-0.8.0`,
  `bark/src/recovery.rs` `recover_candidates` → `store_recovered_vtxos`):
  the ids are fetched from the server regardless of local state, the
  server's spend state is "final", and a VTXO it reports spent is stored
  `Spent` and `mark_vtxos_as_spent`. So after a takeover the app can pass
  every locally spendable id once and the balance stops overstating.
  Bound to the bindings' `recoverVtxos(vtxoIds:gapLimit:)` (bark-ffi
  `4a1c1c0`, already used by the import scan). The takeover copy therefore
  says payments received since the backup appear after the first sync and
  amounts sent since then are reconciled with the server.
- **Backup slot observation**: `NSMetadataQuery` with
  `NSMetadataQueryUbiquitousDataScope` on the slot file; `NSMetadataUbiquitousItemIsUploadedKey`
  for the demoting side, `NSMetadataUbiquitousItemDownloadingStatusKey`
  plus `NSMetadataItemFSContentChangeDateKey` for the promoting side, with
  `startDownloadingUbiquitousItem` when the item is not local (Apple docs,
  checked 2026-11-13; first exercised in this step).
- **The old primary writes its flag before its backup**: `demoteThisDevice`
  saves the row, writes the flag, then posts; `closeWalletForMigration`
  then shuts bark down with the final backup (verified). So "backup newer
  than the moment the flag flipped" is the right second condition.

### 14.2 Changes

1. **`BackupSlotMonitor`** (new, Shared): one-shot metadata gathers polled
   every few seconds; `waitForUpload(after:timeout:)` and
   `waitForDownloadedBackup(newerThan:timeout:)`; pure predicates over a
   `Snapshot` for tests.
2. **`MakePrimaryFlowView_iOS`** (new): step 0 seed check with the
   seed-only entry; branch question when a primary row exists; branch A
   instruction and two-condition wait with a timeout that offers branch B;
   branch B warning and one-tap take-over (unlink then promote); branch C
   direct. After promotion it waits for the wallet to open as primary and,
   on a takeover, runs `WalletManager.reconcileAfterTakeover()`.
3. **`MakeSecondaryView_iOS`** (new): demotes, then waits for the final
   backup's upload before saying "Now continue on your other device".
4. **Devices screen**: one action by role, always visible; the no-primary
   notice and `DeviceAssignmentSheets_iOS` go.
5. **`DeviceRegistrationService.takeOver(lostDeviceId:)`**: unlink then
   promote; `otherDevicePrimaryFlag(deviceId:)` for the fast signal.
6. **`BarkWalletProtocol.recoverVtxos`** mirrors the binding;
   `WalletManager.reconcileAfterTakeover()` passes the spendable ids and
   logs the report's buckets.
7. **Tests**: `HandoverReadinessTests` (the wait's state machine),
   `BackupSlotMonitorTests` (snapshot predicates).

Security-check slots: the three confirmations (demote, promote, take over)
each sit behind one tap today; the gated-actions item adds the presence
check in front of that tap.

### 14.3 Build record (2026-11-14/15)

Built as §14.2. The adversarial pass (fault-class-reviewer, cut off once by
a rate limit and resumed) returned eight findings; dispositions:

- F1 CONFIRMED: the post-promote wait polled `isInitialized && !isReadOnlyMode`,
  which a secondary already satisfies the instant the mode flips, before the
  restore and the open; the takeover reconcile then ran against a closed
  handle and "done" showed early → the wait now requires the FFI handle to
  be present, the mode flipped, and no initialisation in flight, and a
  timeout surfaces an error instead of "done". Ledger row.
- F2 PLAUSIBLE (strong): `copyItem` preserves the database's modification
  date, so the slot's date was the last db write, not the backup time; an
  idle primary's final backup would never have read as newer than the
  handover, stalling a correct handover into a takeover → `performBackup`
  stamps the slot's date with the backup time on every pass, including the
  byte-identical one; `restoreWalletIfNeeded` skips a "newer" backup whose
  bytes equal the local file, so the stamp cannot cause a self-restore.
  Ledger row.
- F3 PLAUSIBLE: the predicate accepted iCloud's `Downloaded`, a stale local
  copy → `Current` only, and a download is requested for missing and stale
  copies. Ledger row (with F4).
- F4 PLAUSIBLE: branches B and C had no download gate, so a never-downloaded
  slot read as "no backup" and the open would have created from the seed →
  both branches make the slot local before promoting when a slot item
  exists; no item means nothing to restore.
- F5 PLAUSIBLE: a 120 s skew tolerance let a periodic backup from before the
  demotion count → the reference is now the old primary's `demotedAt`,
  written by the same clock that stamps its backup; no tolerance.
- F6 PLAUSIBLE: the promote-triggered `initialize` could join an in-flight
  one → covered by F1's fix: a joined run that does not end with the handle
  open times out into the error state.
- F7 PLAUSIBLE: the primary lookup used the KVS hash (nil → unscoped) while
  promote used the own row's → the flow uses the own row's hash first.
- F8 PLAUSIBLE: `unlinkDevice` deleted one row for the id; a reinstalled
  lost device can hold two and the takeover's promote would refuse → every
  row for the id is deleted.
- Minor: a metadata gather that never finishes now times out after ten
  seconds instead of parking the flow's task.

Not verified by the pass and still open as assumptions: `FileManager.copyItem`
mtime preservation (now moot, the stamp overrides it); iOS placeholder
semantics for a never-downloaded slot; `NSMetadataItemFSContentChangeDateKey`
for `Downloaded` items (now moot, `Downloaded` is rejected).

**Tests:** `HandoverReadinessTests` (5), `BackupSlotMonitorTests` (3); full
mobile suite 717 tests, 712 passed, 5 skipped, 0 failed.

**Owed on device** (two phones, A primary, B secondary, the §10 scenario 3
and 4 set):

1. Handover: on B, Devices › Make Device Primary → "Do you still have A?" →
   Yes. On A, Devices › Make Device Secondary → confirm; A shows "Closing
   the wallet…", "Uploading the final backup…", then "Now continue on your
   other device" (log: `Backup slot wait` lines, no timeout). B's status
   moves through "Waiting for A to hand over…", "Handover started…",
   "Waiting for the latest backup…", "Latest backup received." and the
   button enables; tap; B opens as primary with A's latest state (send a
   small signet payment on A before the handover and check it shows on B).
   Repeat once with A idle for an hour before the handover: the same path,
   no timeout (F2).
2. Timeout path: start the handover on B and do nothing on A for four
   minutes; "I Don't Have It Anymore" appears.
3. Takeover: unlink-free start, B on "No, I Lost It" → warning copy names A
   and the backup date; Take Over; B opens as primary; log shows the
   `Takeover reconcile` line with counts; A, when relaunched, lands on the
   link screen (step 2).
4. Direct: with no primary row (A demoted, B not yet promoted), B's flow
   skips the question and shows the direct confirmation.

**Device run 2026-11-15 (Christoph):** handover A → B worked; handing back
B → A left B on the loading screen. B's log showed the demotion, the close
and "Backup skipped - no changes detected", then nothing: the close resets
`isInitialized`, and the main view's secondary branch (B had started the
session as a secondary) shows the loading view until the manager is
initialised. The demotion handler now re-enters read-only mode after the
close. Pre-existing on the old demote sheet for any device promoted in the
same session; the guided flow made it routine. Ledger row. Re-check owed:
hand over A → B, wait, hand back B → A; B must show the read-only wallet.

**Device run 2026-11-15, second finding:** after A became primary again,
X-Ray showed "Wallet operations service not initialized" and no
configuration, while the activity screen reported a live server connection.
`closeWalletForMigration` nils the wallet-scoped services and the
re-promotion's `initializePrimaryMode` reopened bark without rebuilding
them. Fixed by extracting their construction into
`buildWalletScopedServices(wallet:)` and running it again on re-promotion
when they are nil. Pre-existing for any device demoted and promoted in one
session. Ledger row. Re-check owed with the hand-over-and-back: afterwards
X-Ray on the re-promoted device shows VTXOs, Ark info and configuration
without a relaunch. The missing no-connection icon was not a second
defect: the activity icon reads `connectionStatus` off `processStateService`,
which the migration close keeps, and the refresh's server calls run through
`transactionService` and `balanceService`, also kept, so the server really
was reachable. Only the components behind `walletOperationsService` were
gone.

**Device run 2026-11-16 (Christoph, two phones):** hand over A → B, hand
back B → A, X-Ray on A populated without a relaunch. PASSED. Step 4 device
checks complete.
