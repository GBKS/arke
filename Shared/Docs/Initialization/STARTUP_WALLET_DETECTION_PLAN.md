# Startup Wallet Detection — Hardening Plan

## Status — IN PROGRESS (created 2026-07-07)

- **Phase 1 — Tri-state keychain check + logging: DONE 2026-07-07.**
  `MnemonicKeychainStatus` (found / notFound / unavailable(OSStatus)) with
  bounded retry in `performWalletStateDetection()`;
  `SecurityService.lastDetectionWasDefinitive` flags low-confidence results;
  iOS re-checks on `protectedDataDidBecomeAvailable` + foreground; late
  detection now starts CloudKit sync / notification registration (and the iOS
  APNs observer is installed unconditionally); "Launch verdict" log line on
  both platforms. Builds clean; simulated-failure verification still pending
  (see Verification).
- **Phase 2 — Local "wallet ran here" evidence: DONE 2026-07-07.**
  `SecurityService.hasLocalWalletEvidence()` = UserDefaults breadcrumb
  (`com.arke.wallet.hasRunLocally`) OR bark.sqlite on disk. Set in
  `saveMnemonic` (covers create + import) and self-healingly when detection
  confirms the mnemonic; cleared in `deleteWalletData()` and
  `WalletManager.deleteWallet()`. Detection's keychain-unavailable branch now
  treats evidence like the KVS hash: any signal → low-confidence
  wallet-exists, never onboarding.
- **Phase 3 — Biometric save-path fix: DONE 2026-07-07.**
  `saveMnemonic` no longer takes `requireBiometric`; the ACL branch and the
  `useBiometric` auto-detection in `storeMnemonic` are deleted. The write is
  now atomic: `SecItemUpdate`, falling back to `SecItemAdd` only on
  `errSecItemNotFound` — a failed write never deletes the existing item.
  Migration note: no on-disk migration needed. ACL-protected items should not
  exist (the old add would have failed), and if one somehow does, the update
  path rewrites it in place on the next save, while the Phase 1/2 detection
  handles its unreadable existence checks gracefully in the meantime.
- **Phase 4 — Dissolve `.walletWithoutSeed` into read-only mode: DONE 2026-07-07**
  (ultra-simple variant agreed with Christoph — reuses the existing
  connection-status indicator + `ConnectionInfoSheet` instead of a new banner).
  - `.walletWithoutSeed` deleted from `WalletState`; detection routes
    no-seed-with-hash to `.walletActiveElsewhere`. Cover variants + trash
    button deleted from both FirstUseViews; delete plumbing
    (`onDeleteWallet`/`onWalletDeleted`/`walletState` params) stripped from
    both OnboardingFlows. Settings danger-zone deletion is untouched.
  - Reason carried as `ConnectionStatus.readOnlyReason`
    (`notPrimary`/`seedNotSynced`, ArkéUI), computed by WalletManager from
    `securityService.hasMnemonic()` at every read-only transition.
  - `ConnectionInfoSheet` read-only section is reason-aware; `seedNotSynced`
    explains the pending iCloud Keychain sync and offers "Enter Recovery
    Phrase" (hosts `ImportWalletView_iOS` in a sheet; on success updates
    registration `hasSeed` + re-initializes). Strings hardcoded English,
    matching the rest of that file.
  - Promotion: iOS foreground re-check runs when `seedNotSynced` and the
    mnemonic is now readable → `checkForExistingWallet()` re-derives mode and
    updates the registration. Corrected expectation: a *secondary* device
    gaining the seed stays view-only (reason flips to `notPrimary`) until
    "Make Primary" — only a primary device exits read-only entirely.
  - Consciously skipped: desktop import CTA and promotion re-check (macOS
    relaunches re-derive; add if it ever matters), empty-CloudKit syncing
    indicator (existing skeleton loaders deemed sufficient), promotion toast.
  - Needs on-device verification: import flow from read-only mode
    (`importWalletWithBackup` while wallet not open).
- **Phase 5 — `StartupCoordinator` extraction: not started** *(optional; everything above works without it)*

## Review follow-ups (code review 2026-07-07, none blocking)

1. **Notification observer removal is a no-op** (`MainView_iOS.swift`,
   `unsubscribeFromProtectedDataNotifications` and friends).
   `NotificationCenter.removeObserver(self, name:...)` does not remove
   block-based observers added with `addObserver(forName:queue:using:)` — the
   returned token must be retained and removed. The new protected-data
   unsubscribe copied the pre-existing broken pattern (foreground + KVS
   unsubscribes have the same issue). Latent because MainView never actually
   disappears; fix all three together, ideally as part of Phase 5.
2. **`currentReadOnlyReason()` can transiently misreport**
   (`WalletManager.swift`). It uses `hasMnemonic()`, which collapses
   `.unavailable` to `false`, so a seeded secondary device hitting a transient
   keychain error at a read-only transition briefly shows `seedNotSynced` (and
   the recovery-phrase CTA) instead of `notPrimary`. Cosmetic and
   self-correcting, but it is the one remaining spot that treats a keychain
   miss as proof of absence (invariant 3 in spirit). Fix: switch to
   `mnemonicKeychainStatus()` and map `.unavailable` to `.notPrimary`.
3. **Orphaned strings marked stale, not removed**
   (`Shared/Localizable.xcstrings`): `button_delete_wallet_data`,
   `action_delete_existing_wallet`, `accessibility_delete_wallet_hint`,
   `alert_delete_wallet_permanently` have no code references (Xcode flagged
   them `extractionState: stale`). `button_delete_wallet` is still used by
   settings — keep it. Delete the four stale entries.
4. **macOS has no re-check trigger** beyond the in-detection backoff: the
   Phase 1 spec mentioned scene-activation re-checks for macOS, but none was
   added — a low-confidence desktop detection stays wrong until relaunch.
   Accept as a conscious scope cut (aligned with the skipped desktop promotion
   re-check) or add an `NSApplication.didBecomeActiveNotification` re-check
   mirroring the iOS foreground one.
5. **Silent failure in the import promotion path**
   (`ActivityView_iOS.swift` sheet `onWalletImported`):
   `try? await updateCurrentDeviceHasSeed(true)` swallows errors. Self-heals
   on the next `registerDeviceIfNeeded()`, but add a log line on failure to
   keep the diagnostic story consistent.
6. **Verification watch-item** (extends the Phase 4 on-device check): the
   import sheet derives `isMainnet` from `manager.networkConfig`, which comes
   from the wallet object built at launch from persisted config. Should be
   correct in read-only mode, but explicitly cover a brand-new read-only
   device on signet when testing `importWalletWithBackup`.
7. **The danger zone MUST stay reachable in read-only mode**
   (`SettingsView_iOS.swift` ~line 412). The orphaned-KVS-hash user (wallet
   deleted everywhere, hash lingering) now lands in an empty read-only wallet
   instead of the old cover screen, and the settings danger zone is their
   *only* path back to create/import. That works today only because the
   `if !manager.isReadOnlyMode` wrapper around the danger-zone section is
   commented out — but the comment above it still says "(only in primary
   mode)". Delete the stale gate + comment so nobody reinstates it, and
   verify wallet deletion actually completes from read-only mode (no open
   wallet) — see Verification.
8. **Atomic write is less forgiving than delete-then-add for ACL items.**
   If a legacy ACL-protected seed item exists (Decision B says it shouldn't —
   the old add should have rejected the attribute combination, but that's
   from documentation, not observation), `SecItemUpdate` against it may fail
   with an auth/interaction error, and the add fallback only triggers on
   `errSecItemNotFound` — so re-import over such an item would fail where the
   old delete-then-add would have replaced it. Detection still degrades
   gracefully (no misrouting). If wanted: fall back to delete-then-add
   specifically on `errSecAuthFailed`/`errSecInteractionNotAllowed` from the
   update.

## The bug this fixes

**Symptom (observed ~2× in early July 2026, iOS):** launching the app with a
fully set-up wallet intermittently lands on the FirstUse cover screen showing
only an "Import wallet" button (the `.walletWithoutSeed` variant, which also
has a trash button). Relaunching goes to the wallet as normal.

**Failure chain:**

1. `SecurityService.hasMnemonicInKeychain()` (called in `Arke_mobile.init()`,
   `ArkeMobile/ArkeMobile.swift`) and `hasMnemonic()` both reduce
   `SecItemCopyMatching` to `status == errSecSuccess`. Any other status —
   including transient ones like `errSecInteractionNotAllowed` (-25308, keychain
   protected data not yet available: launch right at unlock, iOS prewarming) or
   hiccups while iCloud Keychain syncs the synchronizable item — is treated as
   "no wallet".
2. Early check fails → `initialWalletDetected = false` (frozen in a `let` for
   the process lifetime).
3. Deep check (`performWalletStateDetection()`, `SecurityService.swift`) runs
   milliseconds later in the same launch window and fails the same way.
4. Detection falls through to `getUbiquitousHash()`. NSUbiquitousKeyValueStore
   is cached locally on disk, so the hash **is** readable → returns
   `.walletWithoutSeed`.
5. `MainView_iOS` / `MainView` route to onboarding. Nothing re-checks the
   keychain later in the session (no `protectedDataDidBecomeAvailable` or
   scene-active re-check), so the app stays there until relaunch.

**Confirming the hypothesis:** the OSStatus is currently discarded, so logs
can't prove it yet. Phase 1 adds status logging; the next occurrence will show
the actual code in Console (subsystem `com.arke`, categories `SecurityService`
/ `MainView`).

## Invariants (do not violate in any phase, or in future work)

1. **Never route to onboarding without a definitive `errSecItemNotFound`.**
   An indeterminate keychain read must keep the user on the loading view (with
   retries), or an explicit error state — never the create/import cover.
   Sole exception: retries exhausted *and* no KVS hash *and* no local evidence
   (invariant 2) — i.e. every signal says fresh install — may proceed to
   onboarding; wallet creation will surface keychain errors on its own.
2. **On a device with local evidence that a wallet ran here** (bark.sqlite on
   disk / the Phase 2 flag), treat "no mnemonic" as suspect: retry, and if
   unrecoverable show a "can't unlock your wallet" error state, not onboarding.
3. **A positive keychain hit is trustworthy; a miss is not.** The early-check
   fast path may only short-circuit on *positive* results.
4. **No destructive affordances on launch/onboarding screens.** Wallet
   deletion lives only behind the settings danger zone, never on a cover
   screen reached by automatic detection.

## Decisions

### Decision A — fate of `.walletWithoutSeed` — DECIDED 2026-07-07 (revised same day)

**Remove the state entirely.** A definitive `errSecItemNotFound` + KVS hash
present routes into **registered read-only mode in the same launch**: register
the device (`hasSeed: false`) and initialize with `forceReadOnly: true`,
exactly as `.walletActiveElsewhere` already does. The FirstUse cover then only
ever means `.noWallet` (create/import). The dedicated cover variant, its
import-only layout, and its trash button are all deleted.

Why: the code already converges there. The `.walletWithoutSeed` branch in both
MainViews calls `registerDeviceIfNeeded()`, so on the *next* launch detection
finds the registration and returns `.walletActiveElsewhere` → read-only wallet
UI. The cover screen was never a stable destination — just a one-launch
transient racing the app's own device registration. Making the transition
immediate is strictly more coherent, and it turns the most common legitimate
cause (iCloud Keychain lagging behind KVS sync by minutes) into a self-healing
wait instead of a scary "import your recovery phrase" demand: the user sees
their balances and history via CloudKit, and the device promotes itself to
full mode when the seed arrives.

Requirements this creates (scoped in Phase 4):
- Read-only mode gains a **reason** (`notPrimary` vs `seedNotSynced`) so the
  banner copy and CTAs differ: `seedNotSynced` explains "this device doesn't
  have your wallet key yet — enable iCloud Keychain or import your recovery
  phrase" with an import CTA; `notPrimary` keeps today's behavior.
- A **seed-arrival promotion path**: re-check the keychain on foreground /
  `protectedDataDidBecomeAvailable` (Phase 1 builds these triggers); when the
  mnemonic appears, update the registration (`hasSeed: true`) and flip out of
  read-only without requiring a relaunch.
- **Empty-CloudKit presentation**: a brand-new device may enter read-only mode
  before CloudKit has synced; show a syncing indicator rather than a zero
  balance. The orphaned-KVS-hash case (wallet deleted everywhere, stale hash)
  lands in an empty read-only wallet; "start fresh" lives in the settings
  danger zone, not on a launch screen.

Rejected alternatives, for the record: (a) keep the state, rename to
`seedNotSyncedToThisDevice`, reword the cover, remove the trash button —
cheaper, but preserves the incoherent launch-1/launch-2 split and still tells
a user with funds that they have no wallet; (b) gate the trash button behind
typed confirmation — still a destructive affordance in the least certain
state.

Background: the state predates iCloud Keychain sync of the mnemonic (it used
to be saved ThisDeviceOnly). Legitimate ways to hit "hash but no seed": new
device where KVS has synced but iCloud Keychain is off or lagging; a device
whose registration was deleted; an orphaned hash after the wallet was deleted
elsewhere.

### Decision B — seed protection policy — DECIDED 2026-07-07

The seed is always synchronizable and *not* ACL-protected; biometric gating is
enforced at the app level (`authenticateUser()` already exists). Delete the
`requireBiometric` keychain branch and the `useBiometric` auto-detection in
`storeMnemonic`.

Background: `saveMnemonic(requireBiometric: true)` (`SecurityService.swift`)
combines `kSecAttrSynchronizable: true` with a
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `.biometryCurrentSet` access
control. These are contradictory (ThisDeviceOnly items can't sync);
`SecItemAdd` rejects the combination with `errSecParam`, so the biometric
import path (`BarkWalletFFI+Mnemonic.swift` `storeMnemonic`, which auto-enables
it whenever biometrics are available) likely fails outright. Rationale for the
chosen policy: the whole multi-device story (secondary devices, read-only mode,
device registry) is built on keychain sync; an ACL-protected item would also
permanently break the existence checks (same failure class as the main bug).

## Phases

### Phase 1 — Tri-state keychain check + logging (the bug fix)

- Replace the Bool returns of `hasMnemonic()` and the static
  `hasMnemonicInKeychain()` with a tri-state result:
  - `errSecSuccess` → **found**
  - `errSecItemNotFound` → **definitively absent** (only this may lead to onboarding)
  - anything else → **indeterminate(OSStatus)**
- On indeterminate at startup: stay on `LoadingView`, retry on
  `UIApplication.protectedDataDidBecomeAvailableNotification` (iOS only —
  macOS keychain is available after login, so backoff + scene activation
  suffice there) and on `scenePhase == .active`, plus a small bounded backoff
  (~3 attempts over ~2 s). After retries exhaust: KVS hash present → treat as
  wallet-exists-low-confidence (feeds invariant 2; post-Phase-4 this lands in
  read-only mode); no hash and no local evidence → invariant 1's fresh-install
  exception applies.
- **Late-detection side effects:** CloudKit sync start and push-notification
  registration are gated on the frozen `initialWalletDetected` in both App
  bodies (`ArkeMobile.swift` `onAppear`/`task`, `ArkeDesktop.swift` same).
  If the early check missed but a later check finds the wallet, those must
  fire then — today they silently don't for the rest of the session.
- Log the raw OSStatus on every non-success path (both check functions and
  `loadMnemonic()`).
- Add one structured "launch verdict" log line: early-check result, deep-check
  result + timing, chosen route.

Files: `Shared/Services/SecurityService.swift`,
`ArkeMobile/Views/MainView_iOS.swift`, `ArkeMobile/ArkeMobile.swift`,
`ArkeDesktop/Views/MainView.swift`, `ArkeDesktop/ArkeDesktop.swift`.

### Phase 2 — Local "wallet ran here" evidence

- Set a UserDefaults flag when a wallet is created/imported; clear it on
  deliberate wallet deletion. Existence of bark.sqlite on disk serves as a
  second signal for wallets that predate the flag.
- Wire into detection per invariant 2: evidence present + non-definitive
  "no mnemonic" → never onboarding; retry, then explicit error state.

Files: `Shared/Services/SecurityService.swift`, wallet create/import/delete
paths in `Shared/Data/WalletManager/`.

### Phase 3 — Biometric save-path fix (Decision B)

- Implement Decision B: remove the contradictory ACL branch from
  `saveMnemonic` and the `useBiometric` auto-detection in `storeMnemonic`.
- **Make the keychain write atomic.** `saveMnemonic` currently does
  `SecItemDelete` *before* `SecItemAdd` on the synchronizable item — if the
  add fails (as the biometric branch likely does), the previously stored seed
  has already been deleted, and that deletion can propagate via iCloud
  Keychain to other devices. Use update-or-add (`SecItemUpdate`, falling back
  to `SecItemAdd`) so a failed write never destroys the existing item.
- Before assuming the biometric add fails, verify actual behavior on a real
  device (import with Face ID/Touch ID available) — the `errSecParam`
  expectation is from documentation, not observed. Also check whether any
  existing installs could hold an ACL-protected item needing a one-time
  rewrite on next successful unlock.

Files: `Shared/Services/SecurityService.swift`,
`Shared/Data/BarkWalletFFI/BarkWalletFFI+Mnemonic.swift`.

### Phase 4 — Dissolve `.walletWithoutSeed` into read-only mode (Decision A)

- Delete the `.walletWithoutSeed` case from `WalletState`. In
  `performWalletStateDetection()`, definitive not-found + KVS hash returns
  `.walletActiveElsewhere` semantics with a new **reason** (`seedNotSynced`
  vs `notPrimary`) — either as an associated value or a parallel property.
- In both MainViews: the former `.walletWithoutSeed` branch registers the
  device (`hasSeed: false`) and enters read-only mode in the same launch
  (register **before** `initialize(forceReadOnly: true)`, matching the
  existing `.walletActiveElsewhere` path).
- Read-only banner becomes reason-aware: `seedNotSynced` copy explains the
  missing key and offers an "import recovery phrase" CTA; `notPrimary` keeps
  current copy. Scope note: the import flow currently only exists inside
  onboarding (`OnboardingFlow`/`ImportWalletView` on both platforms), so the
  CTA needs a presentation path from within the wallet UI — likely a sheet
  hosting the existing import view rather than a new flow.
- Seed-arrival promotion: on the Phase 1 re-check triggers (foreground,
  `protectedDataDidBecomeAvailable`), if the mnemonic now exists, update the
  device registration (`hasSeed: true`) and leave read-only mode without a
  relaunch (build on the existing promote/demote notification handling).
- Empty-CloudKit presentation: syncing indicator for read-only mode before
  first CloudKit data arrives, so a fresh device doesn't render a zero
  balance.
- Delete the `walletState == .walletWithoutSeed` cover variant (import-only
  layout + trash button) from both FirstUseViews; the cover only ever renders
  for `.noWallet`.
- Remove now-unused strings; add banner copy to `Shared/Localizable.xcstrings`
  (+ ArkéUI package strings if any copy lives there — remember
  `bundle: .module`).

Files: `Shared/Services/SecurityService.swift` (WalletState + detection),
`Shared/Data/WalletManager/` (read-only reason, promotion),
`Shared/Services/DeviceRegistrationService.swift` (hasSeed update on
promotion), `ArkeMobile/Views/FirstUse/FirstUseView_iOS.swift`,
`ArkeDesktop/Views/FirstUse/FirstUseView.swift`, both MainViews,
`Shared/Localizable.xcstrings`.

### Phase 5 — `StartupCoordinator` extraction (optional refactor)

Startup routing is currently smeared across `App.init()` early check,
`checkForExistingWallet()` (two branches, three separate
`walletManager.initialize()` call sites — note the cached path calls
`initialize()` where the deep path calls `initialize(forceReadOnly: true)` for
the same `.walletActiveElsewhere` state), `detectWalletState()`, and the KVS
change handler — duplicated across iOS and macOS MainViews.

- Extract an `@Observable StartupCoordinator` in `Shared/` owning a single
  phase enum: `checking → walletReady | readOnly(reason) |
  needsOnboarding` (after Phase 4, read-only carries the
  `notPrimary`/`seedNotSynced` reason and onboarding only means no wallet).
- Both MainViews become thin switches over the phase. The coordinator is the
  sole caller of `walletManager.initialize()` and service activation.
- Re-detection triggers (KVS change, wallet deleted, demote/promote) become
  inputs to the machine instead of ad-hoc state mutations in view callbacks.
- Unit-test the machine with injected keychain results (indeterminate-then-
  found sequences, evidence flag on/off, KVS hash present/absent) in
  `Tests/Shared/`.

## Verification

- Phase 1: simulate an indeterminate read (inject a failing status) and verify
  the app stays on loading and recovers when the next read succeeds; verify a
  genuine fresh install (errSecItemNotFound everywhere) still reaches
  onboarding promptly.
- Field confirmation: after Phase 1 ships, the next occurrence of the symptom
  should log the offending OSStatus instead of misrouting.
- Phase 4: fresh device with iCloud Keychain off lands in read-only mode with
  the `seedNotSynced` banner and a working import CTA; fresh device with
  iCloud Keychain on but lagging promotes itself to full mode without user
  action once the seed syncs; genuine fresh install (no KVS hash) still
  reaches the create/import cover promptly.
- Delete-from-read-only (follow-up 7): from a read-only device, the settings
  danger zone is visible and the full wallet deletion flow completes without
  an open wallet / local seed, clearing the KVS hash so a subsequent launch
  reaches the create/import cover. This is the orphaned-hash user's only
  escape hatch now that the cover's trash button is gone.

## Related docs

- `INITIALIZATION_FLOWS.md`, `WALLET_FIRST_INITIALIZATION.md` (this folder) —
  update if Phase 5 changes the flow they describe.
- `../READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` — secondary-device behavior that
  `detectWalletState()` feeds.
