# Wallet Deletion: Never Leave This Device's Mirror Entry Behind

**Status: DECIDED 2026-10-16 (Tier 0, Train 1, deletion cluster) — all four
§8 recommendations approved by Christoph the same day ("follow your
recommendations"). BUILT and REVIEWED 2026-10-16 (uncommitted): adversarial
pass in §9, five findings, three fixed in-session, one plan correction, one
pre-existing hazard filed as its own Tier 0 item. Scoped suites green on the
iPhone 17 Pro simulator; full mobile suite 562/562 on the Pro Max (§9).
Device check DONE 2026-10-19 (Christoph, two phones, mainnet, B attached
to Xcode): steps 1, 3, 4 and 5 PASS (§6.1); step 6 skipped on the mainnet
pair. Item closed in the backlog; commits pending.**

Backlog entry: `Open_Follow_Ups.md`, Tier 0, "Ghost-device hardening (1),
residual". Incident: 2026-09-23 (Done log, "The wallet could not be deleted
from the account", defect 5). Area doc: `Wallet_Deletion_And_Rejoin.md`;
contract rules 17 and 24 in `../Initialization/Launch_Sequence_Contract.md`;
sibling plans `Wallet_Deletion_Partial_Failure.md` (whose sweep filed the
race half of this item, §5 row 9 there), `Wallet_Deletion_Backup_Skip.md`,
`Wallet_Deletion_Phrase_Confirmation.md`.

## 1. Problem

The fast device registry in iCloud KVS (one key per device and wallet hash,
`com.arke.device.registered.<hash>.<deviceId>`) is what the deletion
decision reads. A key that outlives its device is a *ghost*: it names a
blocker nobody can unlink, so every remaining device's full wipe stays
local-only for the 48 h settle window and then needs the informed override.
The 2026-09-24 fix made the clear in `unregisterCurrentDevice` unconditional
and cross-hash. Three gaps remain, all in the same function family:

1. **The clear still has three exits in front of it.** `unregisterCurrentDevice`
   throws before the mirror clear when the model context is nil, when the
   device ID cannot be read, or when the row's `save()` throws. The cleanup
   service swallows the throw and continues, so the deletion finishes with
   the ghost in place and `summary.deviceUnregistered == false` as the only
   trace.
2. **`unlinkDevice` has the same shape.** It throws `deviceNotFound` before
   the mirror clear when the row is missing, and a `save()` throw skips the
   clear too.
3. **A device registration can land after the unregister.** Every
   detection-path registration (`MainView.registerDeviceIfNeeded`) is
   outside the deletion's dedup keys and outside `WalletManager`, so a
   registration that runs its write turn after Step 1 re-creates the mirror
   entry *and* the row for a wallet this device is in the middle of leaving.

## 2. Trace

All **verified** 2026-10-16 by reading the files at the lines given, unless
marked. Line numbers are at `be7922f`.

### 2.1 Every writer, clearer and reader of a mirror entry

| # | Role | Where | Fact |
|---|---|---|---|
| 1 | writer | `DeviceRegistrationService.swift:1276-1285` `registerDeviceInKVStore` | The **only** writer of a `registered.` key. Private; called at `:371` (existing row) and `:383` (new row), both inside `registerCurrentDeviceUnprotected`. No literal duplicate of the prefix anywhere else (grep `com.arke.device.registered`: the constant, two doc comments, the inventory string). |
| 2 | writer's entry | `:307-321` `registerCurrentDevice` → `:323-417` | Wrapped in `withBackgroundActivityAssertion` (no suspension of its own, `BackgroundActivityAssertion.swift:34-45`) and the dedup key `"registerCurrentDevice"`. Inside the closure there is **no `await` between the first fetch at `:343` and `save()` at `:406`**: fetch, mirror write, primary flag, insert and save run in one main-actor turn. The awaits at `:412-415` (reload, reconcile) come after the save. |
| 3 | clearer | `:1301-1313` `removeMirrorEntries(deviceId:)` | Cross-hash via `mirrorKeys(forDeviceId:in:)`; synchronizes only when it removed something. Two callers: `:486` and `:955`. |
| 4 | clearer | `:1317-1332` `clearDeviceRegistrationsFromKVStore(walletHash:)` | Clears every device's entry for one hash. One caller: `WalletDataCleanupService.swift:379`, full wipe only, and only when the hash was still readable at `:369` (read before the hash deletion at `:373`). |
| 5 | reader | `:673-720` `otherDeviceReport` → `:795-810` | Mirror IDs via `otherRegisteredDeviceIds`; a stale registry row blocks only when the mirror corroborates it (`:830-831`); a mirror ID with no row becomes a `.kvsOnly` blocker (`:844-856`). Consumers: `assessDeletion` and both Linked Devices views. |
| 6 | not a mirror key | `:1266-1272` `writeOwnPrimaryFlag` | Writes `device_<id>_isPrimary`, a different key family, never read by the registry scan. **Nothing clears it on any path** (grep `_isPrimary` + remove: no hit), although the inventory lists `device_<id>_* (registration mirror)` as `fullWipeOnly` (`WalletDataCleanupService.swift:1087`). Filed, §7. |

### 2.2 `unregisterCurrentDevice` (`:457-491`)

| Line | Step | Mirror clear reached? |
|---|---|---|
| `:458-460` | `guard let modelContext` else throw `noModelContext` | no |
| `:462` | `try getOrCreateDeviceId()` | no, if it throws |
| `:468` | `try? fetch` (a fetch error reads as "no row") | — |
| `:470-473` | `if let registration { delete; try save() }` | no, if `save()` throws |
| `:486` | `removeMirrorEntries(deviceId:)` | the clear |
| `:490` | `loadRegisteredDevices()` | — |

How reachable each exit is:

- **`modelContext == nil`.** Set once in `ServiceContainer.configureServices`
  (`ServiceContainer.swift:113`), which `MainView_iOS` runs in its launch
  `.task` before detection (`MainView_iOS.swift:221`). The cleanup service
  guards *its own* context at `:307`, for the full wipe only. In a running
  app the device service's context is never nil by the time a delete screen
  exists; the ordering is wrong on principle (ledger class 2), not reachable.
- **`getOrCreateDeviceId()` throws.** Only when the keychain read misses
  *and* `SecItemAdd` fails (`:130-184`). The ID is cached in memory at
  `:151`/`:179` on the first success, and `assessDeletion` →
  `otherDeviceReport` → `getOrCreateDeviceId` (`:674`) runs seconds before
  the unregister, so by Step 1 the cache is warm unless the device has never
  read its ID in this process. The item is `WhenUnlockedThisDeviceOnly`; a
  user-driven deletion runs unlocked. **Derived:** not reachable in a
  foreground deletion; if it were, the device could not name its own entry
  and no ordering fix helps. Residual, surfaced by the typed outcome.
- **`save()` throws.** SwiftData save on the shared main context under
  CloudKit import contention. This is the reachable one and the one the
  TestFlight 0xdead10cc signature (rule 25) says is slow in practice.

### 2.3 The cleanup service around Step 1 (`WalletDataCleanupService.swift:315-328`)

The throw is caught and logged in DEBUG only; the deletion continues. On a
**full wipe** the mirror self-heals one step later when
`clearDeviceRegistrationsFromKVStore` runs (`:377-383`), provided the hash
was readable, and `deleteDeviceRegistrations` (`:586`, `:764`) deletes every
row. On a **local-only deletion** nothing after Step 1 touches the registry:
a skipped clear is a permanent ghost. `DeletionSummary.deviceUnregistered`
(`:928`) is the only record, and nothing reads it (the view stores the
summary at `DeleteWalletSettingView.swift:507` and prints its description).

### 2.4 `unlinkDevice` (`:933-960`)

`guard let registration … else throw deviceNotFound` at `:942-944`, row
delete and `try save()` at `:947-948`, mirror clear at `:955`. Callers:
`LinkedDevicesView_iOS.swift:230` and `LinkedDevicesView.swift:231` (both
pass a registry row's ID), `unlinkAllOtherDevices` (`:965-973`, desktop only,
registry rows only), `cleanupStaleDevices` (`:976-989`, **zero callers**).
`UnsyncedDeviceRow` offers no action, so no caller passes a mirror-only ID
today. **Missed in the first trace, caught by Christoph 2026-10-19:** the
iOS caller is dead UI — `DeviceRow`'s menu with the Remove action is
commented out, so `onRemove` never fires and the unlink alert is
unreachable on iPhone. Only the desktop target can unlink.

### 2.5 Who triggers a registration, and when

| Trigger | Where | Reachable while the delete screen is up? |
|---|---|---|
| launch detection | `MainView_iOS.swift:224` → `checkForExistingWallet` → `registerDeviceIfNeeded` at `:438`, `:492`, `:528`, `:548` | **No in practice.** Awaited right after the detached `initialize()` is spawned; its write turn (row 2 above) lands within one hop, while the delete button waits for `isLoadingWalletData` to clear, i.e. for that same `initialize()` to finish. |
| onboarding `onWalletReady` | `:185` | No. Needs a create/import, which needs no wallet. |
| foreground re-check | `:279-285` — only when the launch detection was low-confidence or a read-only secondary's seed just arrived | **Yes.** Re-runs detection; `.walletWithSeed` / `.walletActiveElsewhere` register. |
| protected-data notification | `:249-251` — only after a low-confidence detection | **Yes**, same shape. |
| post-deletion routing | `onWalletDeleted` → `checkForExistingWallet` (`:113`, `:136`) | After the flow. The rejoin and no-wallet branches register nothing (`:447-468`, `:558-569`). The no-tombstone fallback after a local-only deletion with an unreadable hash (`WalletDataCleanupService.swift:447-452`) re-detects the seed and re-registers — that is the documented resurrection residual, not a ghost. |
| create / import / import-with-backup | `WalletManager+Wallet.swift:145`, `:320`, `:445` | No. User actions on a device with no open wallet. |
| pending registration | `DeviceRegistrationService.swift:109-124` | Dead: `schedulePendingRegistration` has no callers. |
| heartbeat, `updateCurrentDeviceHasSeed`, reconcile, dedupe, promote, demote | `:496-543`, `:431-454`, `:1040-1243` | Write the row or the primary flag, never a `registered.` key. Exempt. |
| desktop `MainView.swift:100, 323, 361, 398, 412` | parked target | Same five sites; the fix lives in the shared service, so it covers them. |

**Derived from rows 2 and 2.2:** the register and unregister write blocks
each run in one main-actor turn, so they cannot interleave; the race is
purely which turn comes first. A registration that passed its entry before
the deletion flag flipped and is waiting for its dedup `Task` to start can
still run its turn after Step 1. Checking the flag *inside* the dedup closure,
next to the writes, leaves no window at all.

### 2.6 The deletion flag today

`DeleteWalletSettingView.swift:454-458` sets `walletManager.setWalletDeletionInProgress(true)`
before `deleteWalletData` and clears it in a `defer`; `WalletManager+Wallet.swift:527-530`
flips `isDeletionInProgress` and suspends opportunistic backups. Readers:
`refresh()` (`WalletManager.swift:914`, notice-level skip) and the seeding
funnels (`:838`). `DeviceRegistrationService` has no view of it; it knows
only `ServiceContainer`.

## 3. Design

### 3.1 Unregister: clear first, report what was retained (gaps 1)

`unregisterCurrentDevice` becomes:

1. `getOrCreateDeviceId()` — the one input both halves need. If it throws,
   rethrow as today (nothing can be cleared without it; §2.2 residual).
2. `removeMirrorEntries(deviceId:)` **before** anything that can fail: no
   context guard in front of it, no row fetch, no save.
3. Then the row: `guard let modelContext` → fetch → delete → `save()`,
   with the failure captured instead of thrown.
4. Return a typed outcome rather than `Void`:

   ```swift
   nonisolated enum UnregistrationOutcome: Equatable, Sendable {
       case complete(mirrorEntriesRemoved: Int, rowExisted: Bool)
       /// The mirror is clean; the CloudKit row is still there.
       /// The other devices see a named blocker they can unlink.
       case rowRetained(mirrorEntriesRemoved: Int, reason: String)
   }
   ```

   `rowRetained` covers both the nil-context and the save-failure exits.
   The function no longer throws for the row half; it throws only when the
   device ID is unavailable.
5. `loadRegisteredDevices()` last, as today.

Why not a `defer`: a `defer` runs the clear *after* a failed save, which is
correct but hides the ordering in control flow; putting the clear first
makes the invariant visible at the call site and is what the 2026-09-24
comment already argues ("this device is leaving, so none of its entries are
valid").

No `rollback()` after a failed save, in either function: the main context
is shared and a rollback discards every writer's pending changes (the
partial-failure review's finding 3). The queued row delete is what the user
asked for; a later save commits it, Step 2's rollback on a failed full wipe
discards it. The first draft of this change had the rollbacks; removed
before review.

Added after review (finding 5): `getOrCreateDeviceId` mints a new ID only on
`errSecItemNotFound`. Any other read status used to fall through to
`SecItemAdd`, and a successful add would split the device's identity — a
second registration plus the old ID's mirror entry as a ghost nobody can
name. Now it throws `keychainError(status)`; every caller already handles
the throw.

### 3.2 The cleanup service records the outcome (gap 1, second half)

`DeletionSummary` gains `deviceUnregistration: DeviceUnregistrationRecord`
(Codable; `.complete`, `.rowRetained(reason)`, `.failed(reason)`) and keeps
`deviceUnregistered` as a computed alias so the existing merge rule stays.
Step 1 maps the outcome: `.complete` → `.complete`; `.rowRetained` →
`.rowRetained`, log at **error** level (release builds too, this is the
export's only trace today); a throw → `.failed`, error level. Then, per
Christoph's ruling in §8 (1), either continue or abort:

- **Continue (recommended).** Nothing before Step 1 is destructive and the
  user's intent is to leave; a retained row has a remedy on the other devices
  (Linked Devices → unlink) and a 30-day stale cutoff, and the mirror, the
  part with no remedy, was cleared in 3.1 step 2. **Correction 2026-10-19
  (Christoph):** the unlink remedy is not reachable on iPhone today — the
  row menu is commented out in `DeviceRow`, only desktop calls
  `unlinkDevice`. Until the Tier 1 "forget this device" UI lands, a
  retained row blocks the other devices' full wipe for the 30-day stale
  cutoff with no override (a healthy row is not "doubtful"), which is
  longer than a mirror ghost's 48 h. The ruling stands: abort would not
  help the other device either (the device would still be registered,
  correctly, since it still has the wallet) and would make the wallet
  undeletable under a persistent save failure. The real remedy is the UI
  item, whose priority this raises. A `.failed` outcome (no
  device ID) is the §2.2 residual, unreachable in a foreground deletion.
- **Abort.** Throw a new `WalletCleanupError.deviceUnregistrationFailed`
  before Step 2, nothing deleted, same return-to-info-screen path as the
  refresh gate. Safer bookkeeping, but a persistent save failure would make
  the wallet undeletable from this device, and a user who cannot delete
  their wallet is a worse outcome than a blocker another device can unlink.

No new UI either way: the user is routed off the device the moment the
deletion completes, and the consequence lands on the other devices, which
already name the blocker.

On a full wipe, Step 2's `deleteDeviceRegistrations` deletes every row and
its save commits Step 1's pending delete, so a `.rowRetained` record is
upgraded to `.complete` once Step 2 succeeds (review finding 3); the export
must not report a retained row that is gone.

### 3.3 Registration refuses during a deletion (gap 3)

One check inside the dedup closure of `registerCurrentDeviceUnprotected`,
first line, before the fetch at `:343`:

```swift
guard !self.registrationSuspended else {
    Self.logger.notice("⏭️ [DeviceRegistration] Skipped — wallet deletion in progress")
    return
}
```

Same shape as the `refresh()` skip (rule O3): a notice line, a normal
return, no error to the five callers whose catch blocks log at error level.
The flag is `DeviceRegistrationService.registrationSuspended`, set and
cleared by the one existing switch, `WalletManager.setWalletDeletionInProgress(_:)`,
which already reaches `ServiceContainer.shared.deviceRegistrationService`
from the same file (`WalletManager+Wallet.swift:141`). One switch, three
readers (refresh, seeding, registration), one `defer` in the view. Rejected:
a latch set by `unregisterCurrentDevice` itself and re-armed by create /
import / rejoin — it needs a second site in the rejoin callback and dies
with the process anyway; a check at `registerCurrentDevice`'s entry only —
leaves the hop between entry and the dedup `Task` (§2.5, derived).

The backlog's alternative, "the cleanup re-clears the mirror after its
quiesce", is not taken: the skip closes the window, and the full wipe already
re-clears through `clearDeviceRegistrationsFromKVStore`.

### 3.4 `unlinkDevice`: same ordering, honest result (gap 2)

Mirror clear first — ahead of the nil-context guard too, since the clear
needs no context (review finding 2 caught the guard still sitting in front
of it) — then the row. Throw `deviceNotFound` only when the row
was missing **and** no mirror entry was removed; a row-less ID whose mirror
entries were removed is a successful unlink. A `save()` failure after the
clear rethrows as today (the view shows "Failed to unlink device"), with the
mirror already clean. Pure rule, testable:

```swift
nonisolated static func unlinkVerdict(rowExisted: Bool, mirrorEntriesRemoved: Int) throws
```

Consequence for the Tier 1 "forget this device for mirror-only ghosts"
item: the service side becomes this change; what remains there is the UI
(the confirmed action on `UnsyncedDeviceRow` and the delete screen's blocker
list). Noted in §7, not built here.

### 3.5 Dead code riding along

`migrateToThisDevice()` goes (DECIDED 2026-10-10, "rides with the next
device-registry change"). `cleanupStaleDevices()` has zero callers and is
the only other `unlinkDevice` caller besides the views; proposed to go in the
same commit (§8 (4)).

### 3.6 Contract and inventory

Rule 24 gains one sentence: "`unregisterCurrentDevice` and `unlinkDevice`
clear the mirror before any fallible step and report a retained row as a
typed outcome; detection-path registration skips while a deletion is in
progress." Rule 17's list of `isDeletionInProgress` readers gains device
registration. The inventory comment at `WalletDataCleanupService.swift:1088-1093`
is already right; the `device_<id>_*` entry at `:1087` gets a comment
pointing at the §7 finding rather than a silent relabel.

## 4. Sweep

| Site | Verdict |
|---|---|
| `registerDeviceInKVStore` (`:1276`), two call sites | covered — the only writer, both sites inside the guarded closure |
| `removeMirrorEntries` callers `:486`, `:955` | covered — both move ahead of the fallible steps |
| `clearDeviceRegistrationsFromKVStore` (`:379`) | exempt-because: full-wipe sweep of *other* devices' entries; unchanged. Its hash-unreadable skip is a residual (§7) |
| `unlinkAllOtherDevices` (desktop `:248`) | covered — goes through `unlinkDevice` |
| `cleanupStaleDevices` | dead; removed per §3.5 or left untouched |
| `processPendingRegistrations` | dead path (no scheduler callers); passes through the guarded closure anyway |
| create / import / import-with-backup registrations | exempt-because: cannot overlap a deletion (§2.5); they pass through the same closure, so if the flag were ever stuck they would skip — the view's `defer` is the only writer of `false`, as for the refresh skip |
| heartbeat, hasSeed update, reconcile, dedupe, promote, demote | exempt-because: no `registered.` key written |
| desktop `MainView.swift` five sites | covered by the shared service; desktop stays unbuilt |
| `device_<id>_isPrimary` KVS key | **missed by every clearer**; filed (§7), out of scope here |
| `Docs` claims relied on | rule 24's "cleared unconditionally" (now qualified), inventory `:1087` (wrong, §7), partial-failure §5 row 9 (the race; realism qualified in §2.5) |

## 5. Tests

- **`unlinkVerdict`** (pure): row + mirror → ok; row, no mirror → ok;
  no row + mirror → ok; no row + no mirror → `deviceNotFound`.
- **Step 1 mapping** via a new seam on the cleanup service,
  `deviceUnregistrar: (() async throws -> UnregistrationOutcome)?`, in the
  style of `otherDeviceReportProvider`: `.rowRetained` lands in the summary
  and the deletion continues (DECIDED); a throw lands as `.failed`. Runs on
  the local-only path with a nil context so no store is touched; Step 4's
  `clearUserDefaults()` does run against the test host's defaults. The suite
  is **not** serialized (the first draft of this plan said it was — review
  finding 4); the reviewer checked that no other suite reads those keys
  through `UserDefaults.standard` and that the tombstone write needs a KVS
  hash the test host does not have.
- **Not tested:** the ordering inside `unregisterCurrentDevice` and the
  skip inside the dedup closure. Both need a failing SwiftData save or a
  live KVS store; pinned by review and the device check, as rule 17's
  ordering is.

## 6. Device check (owed after Review)

Two phones, A (primary) and B (secondary), linked on one signet wallet, this
build on both (fingerprint: the info-level `Unregistered current device
(registry row existed: …, mirror entries removed: …)` line did not exist
before). "Export" means the debug log export button in Settings → Data
(`DebugLogExportButton_iOS`, backed by `DebugLogExporter`). It reads
`OSLogStore` in current-process scope, so it covers **this app session
only**: after the local deletion B sits on the rejoin screen with no
Settings, so do not relaunch B — rejoin first (step 5 below), then export
from Settings → Data in the same session and read the step-3 lines there.
A relaunch in between loses them (an attached Xcode console works too).
Device IDs render `<private>`; the counts are what matter.

1. **Baseline.** Linked Devices on A names B and on B names A. The delete
   screen on each names the other as the blocker, no override link.
2. **Unlink — not checkable on iPhone.** The row menu that calls
   `onRemove` is commented out in `DeviceRow`
   (`LinkedDevicesView_iOS.swift`, "Menu button" block), so `unlinkDevice`
   has no live iOS caller; only the parked desktop target reaches it. The
   service change is pinned by `UnlinkVerdictTests` and the hand trace.
   Noted on the Tier 1 "forget this device" item: re-enabling the row
   unlink is part of that UI work.
3. **Local-only deletion.** On B: Settings → Delete wallet → the screen
   names A → slide. B lands on the rejoin screen. B's log:
   `Unregistered current device (registry row existed: true, mirror entries
   removed: 1)` and no error-level `registry row retained` or `Device
   unregistration failed` line. No `⏭️ [DeviceRegistration] Skipped` line
   is expected here either; if one appears, a late registration was caught,
   which is the fix working, not a failure.
4. **A sees no ghost.** Relaunch A. Linked Devices shows A alone, no
   "Unrecognized device" row. The delete screen says last device and offers
   "Delete everything" with no blocker and no override link. This is the
   2026-09-23 incident shape, inverted.
5. **The switch does not stick.** On B tap rejoin. B opens read-only and
   registers; after a relaunch A names B again. Proves registration works
   again after the deletion's `defer` cleared the suspension.
6. **Full wipe self-heal.** Delete locally on B again (step 3), then on A
   take "Delete everything". A's log shows the same unregister line and
   onboarding appears. Import the phrase on B: no blocker is named on B's
   delete screen, Linked Devices on B shows B alone.

Not provokable on device: the failed-save path, the nil-context path, and
the late-registration skip (its only reachable triggers are a low-confidence
launch or a seed arriving on a read-only secondary while the delete screen
is up).

### 6.1 Result (2026-10-19, B's Xcode console, `Docs/debug_logs.txt`)

B was the read-only secondary of a **mainnet** pair (25,250 sats, seed
shared). Line numbers refer to that file.

| Step | Verdict | Evidence |
|---|---|---|
| 1 baseline | pass (B side) | `:218` "Other-device check: 1 device(s) hold this wallet (0 mirror-only)" → local-only, A named |
| 2 unlink | not checkable on iPhone | — |
| 3 local-only deletion | **pass** | `:222` `Unregistered current device (registry row existed: true, mirror entries removed: 1)`; `:223` "Loaded 1 registered devices"; no error-level `registry row behind` / `unregistration failed` line; no skip line (none expected); `:230` tombstone, `:266-270` rejoin route |
| 4 A sees no ghost | **pass** (Christoph, same day) | A was on Linked Devices during B's deletion: B's row vanished within a few seconds. A's delete screen opened right after read the mirror-only copy ("another device… its details haven't reached this device yet"); ten seconds later it offered the full wipe with no blocker. So the CloudKit row deletion reached A *before* the KVS mirror removal did — a short, self-clearing mirror-only window, the opposite order from the one the design assumes (KVS converges first). Not a ghost. Copy follow-up filed in Tier 3 |
| 5 switch does not stick | **pass** | `:402` tombstone cleared → `:417` registration → `:430-431` "Registered device in KV store" + "Created new device registration (isPrimary=false, claimAllowed=false)" in 1.28 s → `:458` B names A again |
| 6 full-wipe self-heal | proposed skip | would wipe the mainnet pair; the path is pre-existing except the record upgrade |

Also seen, recorded rather than fixed:

- `:98-108` the launch registration took **30.42 s** and the launch verdict
  44.77 s on this secondary (CloudKit export/refresh between the KV write
  at `:100` and the completion at `:108`). §2.5's "lands within one hop"
  is true of the *writes* (`:100-101` are at the start, one turn) but not
  of the call; the read-only path awaits the registration before it
  initializes, so no delete screen exists during those 30 s. The
  in-closure guard is unaffected.
- `:131-132` a routine secondary logs "🔒 Read-only: this device is
  registered as a secondary" and, one line later, "⚠️ Device has been
  demoted - switching to read-only mode". The second line is wrong for a
  device that was never primary. Tier 4 log-wording item.
- `:242` SwiftUI: "The `navigationDestination` modifier only works inside a
  `NavigationStack`… presenting `DeletePhraseConfirmationView`… It will
  be ignored", logged while the wallet view tears down after the deletion.
  Cosmetic at teardown; the phrase screen worked on 2026-10-15. Tier 4.
- `:247` "Failed to unregister from push: Wallet has not been created or
  opened" — a read-only secondary never minted a relay registration
  (`:113`), so the manager's Step 3 has nothing to undo. Pre-existing,
  benign.

## 7. Residuals filed (not fixed here)

- `device_<id>_isPrimary` is never removed by unregister, unlink or the
  full wipe; the inventory calls `device_<id>_*` `fullWipeOnly`. Harmless
  for the registry scan; relevant to the Tier 0 `checkReadOnlyMode` item,
  since layer 2 reads it on a reinstall whose breadcrumb is gone. → Tier 4
  line under "Ghost-device hardening (2)–(4)".
- Full wipe with an unreadable KVS hash skips `clearDeviceRegistrationsFromKVStore`
  (`:377`); the other devices' entries survive under a hash that only
  matters again if the same phrase is re-imported. Recorded here.
- `getOrCreateDeviceId` throwing at unregister time (§2.2): the device
  cannot name its own entry; surfaced as `.failed`, not solved.
- The Tier 1 "forget this device" item becomes UI-only after §3.4.
- **A deletion that aborts after Step 1 leaves this device running the
  wallet with its blocker evidence gone** (review finding 1, pre-existing).
  Step 1 clears the mirror and commits the row delete; if Step 2 (CloudKit)
  or Step 3 (keychain) then throws, the view returns to the info screen with
  the wallet intact and nothing re-registers until the next cold launch.
  Until then another device's report sees no blocker and is offered the
  full wipe, which deletes the shared seed while this device still spends.
  And the next launch's detection-path registration creates a *new* row
  with `isPrimaryDevice == false`, so an ex-primary relaunches as a
  secondary. Filed as its own Tier 0 item with a proposed fix: move the
  unregister to after the fallible CloudKit step and before the keychain
  step, so every abort path leaves the registration intact.
- KVS removals are handed to `synchronize()`; whether they reach iCloud when
  the app is killed right after the deletion is the same reliance as before.

## 8. Rulings (Christoph, 2026-10-16) — all four DECIDED as recommended

1. **Unregister failure during a deletion: continue and record, or abort
   with nothing deleted?** Recommended: continue (§3.2). Blocks the Step 1
   code and its test.
2. **Registration during a deletion: skip with a notice line, or throw a
   typed error to the callers?** Recommended: skip (§3.3). Blocks nothing
   else; changes five log lines.
3. **`unlinkDevice` on a row-less ID that still has mirror entries: succeed
   after clearing, or keep throwing `deviceNotFound`?** Recommended: succeed
   (§3.4). Reshapes the Tier 1 "forget this device" item.
4. **Delete `cleanupStaleDevices()` alongside the decided `migrateToThisDevice()`
   removal?** Recommended: yes (§3.5).

## 9. Review record (2026-10-16, `fault-class-reviewer`, same session)

Handed the working-tree diff and the area name. Findings and what was done:

1. **CONFIRMED, class 1, pre-existing** — abort after Step 1 strips this
   device's own blocker evidence (§7). Not widened by this change; filed as
   a Tier 0 item, not fixed here.
2. **CONFIRMED, class 5** — rule 24 (d) and §3.4 said `unlinkDevice` clears
   the mirror before any fallible step, but the nil-context guard still
   preceded it. **Fixed**: clear moved ahead of the guard. Unreachable in
   practice, wrong on principle.
3. **CONFIRMED, class 5** — on a full wipe a `.rowRetained` record survived
   Step 2's deletion of every row, so the export would have reported a
   retained row that was gone. **Fixed**: upgraded to `.complete` after
   Step 2 succeeds, with an info line.
4. **CONFIRMED, class 5** — §5 claimed the orchestration suite is
   `.serialized`; it is not. **Plan corrected**; the reviewer verified the
   test's side effects are harmless to the other suites.
5. **PLAUSIBLE, class 4** — `getOrCreateDeviceId` could mint a *new* ID on
   any non-success read status, splitting the device's identity and
   leaving the old ID's mirror entry as a ghost. **Fixed**: only
   `errSecItemNotFound` mints; other statuses throw.

Sound per the reviewer, with evidence: the suspension flag's lifetime
(single writer pair in the view's `defer`, false before `onWalletDeleted`'s
task runs, rejoin and no-wallet branches register nothing, dies with the
process); the one-turn claim for both write blocks; the no-rollback choice;
`nonisolated enum UnregistrationOutcome` (built and 21 tests executed by the
reviewer); the merge rule; no caller depended on the old throw-before-clear;
the sibling sweep. Not verified by the reviewer: the §6 device check;
whether a SwiftData fetch excludes a pending-deleted object after a failed
save (the rejoin-after-retained-row path depends on it); KVS propagation
after an immediate kill; the desktop target (inspected, unbuilt); the
save-failure path on device; whether a persistent save failure is caused by
another writer's pending change.

After the fixes: `XcodeRefreshCodeIssuesInFile` clean on the three source
files and the test file; `BuildProject` green; full mobile suite
**562 passed, 0 failed** on the iPhone 17 Pro Max simulator. The iPhone 17
Pro simulator refused to spawn the test host twice that day ("Launchd job
spawn failed", before any test ran, after a simulator shutdown too) — a
simulator fault, recorded so the next session does not chase it as a
regression.
