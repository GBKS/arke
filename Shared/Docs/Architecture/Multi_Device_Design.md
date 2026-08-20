# Multi-Device Design

Status: GUIDING DOCUMENT — created 2026-08-19. This is the parent document for
all multi-device behavior. Scenarios here are the acceptance criteria; UI
flows, service APIs, and invariants derive from them. When a multi-device
feature or fix lands, update the scenario's status column; when a new user
journey emerges, add it here FIRST and derive the work from it.

Related: `Features/Read_Only_Mode.md`, `Features/Wallet_Deletion_And_Rejoin.md`,
`Initialization/Launch_Sequence_Contract.md` (rules 14–20),
`Initialization/STARTUP_WALLET_DETECTION_PLAN.md`.

## Principles (the physics of the system)

These are invariants, not preferences — every scenario below must hold them:

1. **One wallet per iCloud account.** The iCloud account IS the wallet
   boundary: one seed in iCloud Keychain, one wallet hash in iCloud KVS, one
   CloudKit data set. Creating a second wallet is refused in code
   (`BarkErrorArke.walletAlreadyOnAccount`).
2. **Exactly one primary device.** Only the primary can spend. Primary is
   claimed by explicit user action (create/import/promote) — never inferred
   by detection (contract rule 15). Conflicts converge via deterministic
   self-demoting reconciliation.
3. **The seed is shared property.** It syncs via iCloud Keychain to every
   device. No single device may destroy it except the last one, on an
   explicit full wipe (contract rules 18–19).
4. **Devices are cattle, the account is the pet.** Any device can be lost,
   wiped, unlinked, or replaced without endangering funds, as long as the
   account (or the written phrase) survives.
5. **Deletion is scoped.** "Delete from this device" never touches shared
   property; "delete everything" is only offered where it is provably safe
   (last device).

## State model

Account-level state (shared): seed in iCloud Keychain (present/absent),
wallet hash in KVS (present/absent), CloudKit data set, device registry
(CloudKit + KVS mirror), iCloud Drive wallet-db backup.

Per-device state: wallet files on disk (present/absent), seed readable
(yes/no/keychain-unavailable), registered (yes/no), role (primary/secondary),
local-deletion tombstone (present/absent).

Detection (`SecurityService.performWalletStateDetection`) maps these to four
routes: wallet (spendable), read-only, rejoin, onboarding.

## Capability matrix

| Capability | Primary | Secondary (seed synced) | Secondary (read-only, no seed) |
|---|---|---|---|
| View balance/history/contacts/tags | ✓ | ✓ | ✓ |
| Receive (show addresses) | ✓ | ✓ | ✓ |
| Send / participate in rounds / exits | ✓ | — | — |
| Show recovery phrase | ✓ | ✓ | — |
| Promote self to primary | n/a | ✓ | — (needs seed first) |
| Unlink another device | ✓ | ✓ | ✓ |
| Delete from this device | ✓ | ✓ | ✓ |
| Delete everything (full wipe) | last device only | last device only | last device only |

(If a row is wrong, fix the row or file the bug — this table is the contract
UI copy should reflect.)

## Security checks (PROPOSED 2026-08-19 — awaiting decision)

Prompted by "we may want to require a Face/Touch ID or other security check
for sensitive actions." Proposal: sensitive actions require a local
user-presence check (Face ID / Touch ID with device passcode/password
fallback) before executing:

| Action | Check |
|---|---|
| Show recovery phrase | required |
| Delete from this device | required |
| Delete everything (incl. the S7 override) | required |
| Promote / demote / unlink a device | required |
| Send | optional, user setting (off by default) |

Design constraints:

- The check is an **app-level confirmation of user presence, not a
  cryptographic gate**. The mnemonic keychain item deliberately carries no
  ACL (Decision B in the startup-detection plan) because an ACL would break
  iCloud Keychain sync and the existence checks that route launch. Biometric
  gating therefore lives at the action layer, via
  `SecurityService.authenticateUser(reason:)`.
- Use `LAPolicy.deviceOwnerAuthentication` (falls back to passcode/password),
  NOT `.deviceOwnerAuthenticationWithBiometrics` — the current implementation
  uses biometrics-only and would hard-fail on Macs without Touch ID and on
  devices without enrolled biometrics.
- Current state: `authenticateUser` exists but its single call site is
  commented out — **nothing is gated today**. Wiring the table above is the
  work item.
- Failure/unavailability behavior: if no auth method exists at all (no
  passcode set), proceed with an extra typed confirmation instead of
  blocking — a user without a passcode chose that posture device-wide.

## Scenario catalog

Legend: ✓ shipped · ⚠️ shipped, on-device verify pending · ◻ missing/gap.

### S1 — First device: create a wallet → becomes primary ✓
User creates a wallet during onboarding. This device registers with
`allowPrimaryClaim: true`; seed saved to iCloud Keychain; hash to KVS.

Walkthrough:
- **Does:** opens the app for the first time, taps through onboarding, chooses "Create wallet".
- **Sees:** intro, server selection, then the wallet home screen.
- **Behind the scenes:** seed generated and saved to iCloud Keychain; wallet hash published to iCloud; device registered as primary.
- **End state:** this device shows the full wallet and can spend.

Status: shipped, in daily use.

### S2 — Add a second device → automatically secondary ⚠️
User installs the app on a second device signed into the same iCloud account.
Detection finds the KVS hash; the device registers as secondary
(`allowPrimaryClaim: false`) and opens read-only. When iCloud Keychain
delivers the seed, it becomes a full secondary (still not primary).
Sub-case: seed not synced yet (iCloud Keychain off/lagging) → read-only with
`seedNotSynced` explanation and manual phrase entry as fallback.

Walkthrough:
- **Does:** installs the app on a second device (same iCloud account) and opens it.
- **Sees:** no onboarding — the wallet appears directly, in read-only mode; balance and history fill in as iCloud syncs.
- **Behind the scenes:** app finds the account's wallet hash, registers this device as secondary; the seed arrives via iCloud Keychain shortly after.
- **Sees (after seed sync):** full wallet view, but sending stays disabled — copy points at the primary device.
- **If the seed never arrives:** a sheet explains iCloud Keychain is off and offers typing the recovery phrase instead.
- **End state:** device is a secondary; the first device remains primary.

Status: shipped (`Read_Only_Mode.md`); part of the standing two-device verify.

### S3 — Deliberate primary swap (both devices accessible) ⚠️
User promotes the secondary; the old primary observes the KVS
`device_<id>_isPrimary` flip, demotes itself, and drops to read-only.
Exposed via Settings → Linked Devices (promote/demote sheets on iOS).

Walkthrough:
- **Does (on the secondary):** Settings → Linked Devices → "Make This Device Primary", confirms (proposed: security check).
- **Sees:** confirmation, then sending unlocks on this device.
- **Behind the scenes:** registry updates; the old primary observes the flip and demotes itself.
- **Sees (old device):** drops to read-only with a pointer to the new primary.
- **If both promoted at once:** reconciliation picks one deterministic winner; the loser self-demotes — no user action needed.

Status: service + iOS UI shipped; two-primary races covered by reconciliation
(`PrimaryDeviceReconciliationTests`). Gaps: desktop promote/demote UI parity;
on-device verify of the live demotion handoff.

### S4 — Lost primary: take over on the secondary, remove the lost device ⚠️/◻
User lost the phone that was primary. On the secondary: promote self
(possible because the seed is synced), then unlink the lost device from the
registry (`unlinkDevice` — exposed on both platforms). The lost device, if it
ever comes back, observes its demotion and drops to read-only.

Walkthrough:
- **Does (on the surviving secondary):** opens Settings → Linked Devices.
- **Sees:** warning that no primary device is active (today only visible here — the proposed banner would surface it on the main view).
- **Does:** taps "Make This Device Primary"; then unlinks the lost phone, confirming "I no longer have this device".
- **Behind the scenes:** this device becomes primary; the lost device's registration is removed.
- **If the lost phone resurfaces:** it sees it was demoted and opens read-only — it cannot spend.
- **Security note:** unlinking does not protect funds. If the lost device may be unlocked in someone else's hands, its keychain still holds the seed — the safe response is moving funds to a fresh wallet.

Status: promote ✓, unlink ✓, demotion-on-return ⚠️. Gaps: the *discovery* of
this path is passive (user must find Linked Devices) — the deferred active
"no primary device" banner is exactly this scenario's entry point; there is
no guided "I lost a device" flow tying promote + unlink together.

### S5 — One-device migration (old device → new device) ◻ (sketch PROPOSED 2026-08-19)
User has one device and replaces it. Every primitive exists (S2 join, S3
promote, S6 local delete, S11 unlink); the migration assistant is
**orchestration and copy only — no new protocol**.

The flow is three states, observable from either device via the registry, so
it gets entry points on both ("Migrate to a new device" in Settings on the
old device; the rejoin/secondary screen offers "Make this my main device" on
the new one):

1. **Join.** New device signs into the same iCloud account and opens the app
   → joins as secondary (S2). The old device's assistant shows live registry
   status: "Waiting for your new device… ✓ iPhone 17 joined."
2. **Hand over.** Promote the new device (security check, see Security
   checks). The old device observes the KVS primary flip and demotes itself
   to read-only (S3). Assistant confirms: "iPhone 17 is now your main
   device."
3. **Retire.** On the old device: "Remove wallet from this device" (S6,
   local-only — reassurance copy: the wallet lives on the new primary). If
   the old device will be erased or sold anyway, note that erasing works too
   and the new device can unlink the ghost later (S11).

Fallback (new device can't use the same iCloud account): recovery-phrase
import, with explicit copy that import claims primary.

Walkthrough (proposed):
- **Does (new device):** signs into iCloud, installs and opens the app.
- **Sees (new device):** the wallet appears, read-only (S2).
- **Does (old device):** Settings → "Migrate to a new device".
- **Sees (old device):** live checklist — "✓ iPhone 17 joined. Make it your main device?"
- **Does:** confirms the handover (security check).
- **Sees (old device):** "Done — iPhone 17 is now your main device. Remove the wallet from this device?" → one tap runs the S6 local delete.
- **End state:** new device is primary; old device is wallet-free (or read-only if kept as-is).

Implementation note: prefer `promoteThisDeviceToPrimary()` and **delete
`migrateToThisDevice()`** — it force-grabs primary by writing
`isPrimaryDevice` directly without the `becamePrimaryAt` bookkeeping the
two-primary reconciliation tiebreak depends on (contract rule 15), so using
it could produce conflicts the reconciler resolves wrongly.
Status: proposed; not built. Gap: the assistant UI + delete-confirmation copy
pointing migrating users at it. (The `migrateToThisDevice()` finding stands
regardless of the flow design — it bypasses reconciliation bookkeeping.)

### S6 — Delete the wallet on a secondary the user keeps using ⚠️
User stops using the wallet on one device (keeps the device). "Delete from
this device": local data wiped, device unregistered, shared property (seed,
KVS hash, CloudKit data, backups) untouched. The install is tombstoned so the
still-synced seed can't silently resurrect the wallet; the device shows the
rejoin screen instead of onboarding, and rejoining is one tap.

Walkthrough:
- **Does:** Settings → Delete Wallet.
- **Sees:** "Other devices have this wallet. It will be removed from this device only." Confirms.
- **Behind the scenes:** local data wiped, device unregistered; seed, iCloud data, and backups untouched; the install is tombstoned.
- **Sees (afterwards, and on every relaunch):** the rejoin screen — "Your wallet is still active on \<device\>" — never onboarding, so no way to accidentally create a second wallet.
- **If they change their mind:** one tap rejoins; the wallet restores from the preserved iCloud backup.

Status: shipped 2026-08-19 (`Wallet_Deletion_And_Rejoin.md`); the two-device
on-device verify is the gate.

### S7 — Delete the wallet everywhere ◻ (PROPOSED 2026-08-19 — awaiting decision)
User wants the wallet gone from all devices and iCloud.

**The stale-ghost question (Christoph): "you lost or sold your old phone and
forgot to deregister it — could that stale registration block the full
deletion?"** Answer, today: yes, for up to 30 days. `hasOtherActiveDevices()`
filters out registrations with no heartbeat for 30+ days, so old ghosts stop
blocking eventually — but inside that window the strategy silently downgrades
to local-only with no device names, no explanation, and no unlink path in the
delete flow. And a sold-but-not-erased phone that someone keeps opening
heartbeats forever: it blocks permanently (see Failure modes §C).

**Proposal:** replace the timeout with recognition. An *active* registered
device blocks the full wipe — but every blocker is shown by name and
last-seen, and the primary remedy is in the flow itself.
"Delete everything" is structurally unavailable while any *other active*
device (fresh heartbeat) is registered. Instead of silently downgrading to
local-only (today's behavior), the delete flow *shows the blockers*: "Your
wallet is still registered on iPhone 13 (last seen June 2)" — leading with
"*Don't have this device anymore?*" → unlink here (S11), or go delete the
wallet there (S6). When no active others remain, the full wipe unlocks. A
forgotten ghost costs a ten-second recognition step instead of a 30-day
wait. Design details:

- *Active* = heartbeat within the staleness threshold (currently 30 days).
  Stale registrations don't block (already true today) but are listed for
  cleanup. With unlink-in-flow as the primary remedy, the exact threshold
  matters much less — recognition replaces waiting either way.
- *Override valve:* "Delete everything anyway" stays available behind the
  security check plus explicit consequence copy — registry ghosts and
  CloudKit outages must not permanently prevent deletion. This also settles
  the open `getDeletionStrategy()` fallback question: with blocking UX, the
  error fallback flips to blocked/local-only (conservative), because full
  wipe is now an explicit, informed choice rather than a default.
- *Remote aftermath:* devices that survive a (overridden) full wipe observe
  the KVS hash removal and show a "wallet was deleted on another device"
  state offering local cleanup. Cleanup is offered, never automatic — a KVS
  glitch must not be able to trigger data destruction remotely.

Walkthrough (proposed):
- **Does:** Settings → Delete Wallet on the device they consider the last one.
- **Sees (if other devices are active):** a list of blockers — "Still active on MacBook Pro (seen 2 hours ago)" — each with two options: *delete the wallet there* or *unlink it here* ("I no longer have this device").
- **Does:** clears each blocker; or takes the guarded escape hatch, "Delete everything anyway".
- **Sees:** final "Delete everything" confirmation (security check), then onboarding.
- **Behind the scenes:** seed removed from iCloud Keychain, wallet hash, iCloud data, and backups deleted, local files wiped.
- **Other devices (override case):** show "This wallet was deleted on another device" and *offer* local cleanup — nothing is destroyed remotely without a tap.

Status: proposed; not built. If accepted, it supersedes the old "bless
device-by-device vs remote wipe" question — the answer would be
device-by-device with visibility, blocking, and an informed override; no
remote-wipe protocol.

### S8 — All devices lost: recover on a brand-new device ⚠️
Two sub-cases. (a) Same iCloud account: the new device syncs the keychain
seed + KVS hash → S2 then S4 (promote, unlink ghosts). Wallet db restores
from the iCloud Drive backup where available; otherwise bark's seed-recovery
scan on the creating open (contract rules 1–2). (b) iCloud account also gone:
manual recovery-phrase import — the only path where the written phrase is
strictly required.

Walkthrough (a — same iCloud account):
- **Does:** signs into iCloud on the replacement device, installs the app.
- **Sees:** the wallet appears read-only (S2); promotes per S4 and unlinks the ghost devices.
- **Behind the scenes:** iCloud Keychain restores the seed; the wallet database restores from the iCloud backup, or rebuilds from the seed.

Walkthrough (b — iCloud account also gone):
- **Does:** onboarding → "Import wallet" → types the written recovery phrase.
- **Sees:** the wallet rebuilds; balances appear after the recovery scan.
- **Behind the scenes:** wallet re-derived from the phrase; device registers as primary (import may claim it).

Status: paths exist; recovery-scan correctness has a known upstream
sharp edge (created_now gate); no dedicated "I lost everything" guidance.

### S9 — App reinstall on the same device ⚠️
iOS deletes the app container (wallet files gone) but the synced keychain
survives → detection finds the seed → wallet reopens (restore from backup or
re-derive). macOS keeps the container across reinstalls → stale-data
handling on import applies (contract rule 5). The non-synchronizable device
ID distinguishes "this device was wiped" from "new device" (rule 16).

Walkthrough:
- **Does:** deletes the app, reinstalls it, opens it.
- **Sees:** the wallet loads normally — no onboarding, no questions.
- **Behind the scenes:** iOS lost the local files but the synced keychain kept the seed; the wallet restores from backup or rebuilds. macOS kept the files outright.
- **Worth knowing:** deleting the app is NOT "delete from this device" — it doesn't unregister the device or remove anything from the account.

Status: works via the detection/restore paths; part of startup-detection
hardening, no dedicated verify.

### S10 — iCloud sign-out or Apple-ID switch on a device ◻ (decided 2026-08-19)
Signing out of iCloud removes synced keychain items and detaches KVS; the
wallet files remain on disk. Switching to a different Apple ID could pair
local wallet files with a foreign account's (absent or different) wallet
hash.

**Decision (Christoph):** read-only + explain; never auto-wipe, never mix
accounts. Concretely: when local wallet files exist but the account signals
are gone or belong to a different wallet hash, the device enters read-only
with a dedicated reason ("signed out of iCloud" / "different iCloud
account"), explains that spending and sync need the original account, and
offers only safe exits: sign back in, or explicitly delete from this device
(S6-style local-only, security check required). Local files are never paired
with a foreign account's data and never deleted automatically.
Walkthrough (decided design):
- **Does:** signs out of iCloud (or switches Apple ID) in system settings, later opens the app.
- **Sees:** the wallet in read-only mode with a clear reason — "You're signed out of iCloud" / "This device is on a different iCloud account".
- **Offered:** two safe exits only — sign back in, or remove the wallet from this device (security check).
- **Behind the scenes:** nothing is deleted automatically; local wallet files are never paired with another account's data.
- **On signing back in:** the app re-detects and returns to the previous role.

Status: decided; not built. Today's behavior is the low-confidence detection
fallback; KVS account-change notifications are observed but only re-run
detection.

### S11 — Device sold/erased without saying goodbye (stale registrations) ⚠️
A device that was wiped externally never unregisters; its heartbeat goes
stale. Any surviving device can unlink it (S4); `cleanupStaleDevices(30d)`
exists for automatic hygiene.

Walkthrough:
- **Sees:** an old device lingering in Settings → Linked Devices ("last seen 3 months ago").
- **Does:** taps unlink, confirms.
- **Behind the scenes:** the registration is removed from the registry.
- **Worth knowing:** unlink is bookkeeping, not revocation — a device that still has the app and seed will simply re-register the next time it launches. Truly removing a device means deleting the wallet there (S6) or erasing the device.

Status: service shipped; open items — devices-list scoping to the current
wallet, and whether stale cleanup runs automatically anywhere.

### S12 — Two devices claim primary under sync lag ✓
Both create/import/promote near-simultaneously before CloudKit converges.
Deterministic self-demoting reconciliation (earliest `becamePrimaryAt`,
deviceId tiebreak) converges every device to the same winner.

Walkthrough:
- **Does:** promotes (or imports) on two devices at nearly the same time.
- **Sees:** briefly, both may claim to be primary.
- **Behind the scenes:** once sync converges, every device independently computes the same winner; the loser demotes itself.
- **Sees (losing device):** read-only, with a pointer to the winner.
- **User action needed:** none — it self-heals.

Status: shipped + unit-tested; server-side arbitration remains a hardening
follow-up.

### S13 — Lost/retired secondary ✓
Trivial case of S4: unlink it from any surviving device. The seed was never
at risk of loss (it lives on every device and in iCloud Keychain).

Walkthrough:
- **Does (on any surviving device):** Settings → Linked Devices → unlink the lost one.
- **Behind the scenes:** registration removed; spending was never possible from the lost device (it wasn't primary).
- **Security note:** same as S4 — if the lost device may be unlocked in someone else's hands, the recovery phrase on it is the real exposure; consider moving funds.

## Failure modes

Organized by fault class, not per scenario — the same fault usually cuts
across many scenarios. Scope: multi-device failures only; bark/protocol-level
failures (rounds, exits, server) live in the feature docs. Format per entry:
what happens → impact → mitigation → status.

### A. User mistakes (most likely class)

- **Wrong deletion scope.** User expects "delete from this device" to remove
  the wallet everywhere, or expects deletion on the last device to be
  recoverable. → Confusion or unintended data loss. → Strategy-aware copy
  (shipped 2026-08-12) + the S7 blocking UX making scope visible. Status:
  copy shipped; S7 proposed.
- **Full wipe without a written phrase.** The last-device full wipe destroys
  the only seed copies (iCloud Keychain + devices); if the user never wrote
  the phrase down, funds are unrecoverable the moment they confirm. →
  Permanent fund loss. → PROPOSED: the final confirmation asks for two words
  of the recovery phrase (e.g. words 4 and 9) — consent check and
  backup-existence proof in one. Status: proposed (see Derived work).
- **"Deleting the app deletes the wallet"** — false in both directions:
  reinstall silently resurrects (S9), and app deletion never unregisters. →
  Surprise resurrection, ghost registrations. → S9/S11 walkthrough copy;
  ghost cleanup via unlink. Status: documented; no in-app education yet.
- **Wrong-order migration.** Wiping the old device before the new one joined.
  → With today's code: harmless if local-only (seed survives); catastrophic
  only via full wipe without a written phrase (see above). → S7 blocking +
  S5 assistant sequence the steps. Status: proposed.
- **Racing promotions.** Two devices promoted near-simultaneously. → Brief
  double-primary. → Deterministic self-demoting reconciliation (S12).
  Status: shipped + tested.

### B. Environment faults (silent, systemic)

- **iCloud Keychain off or lagging.** Seed never reaches a joining device. →
  Device stuck in read-only. → `seedNotSynced` explanation + manual phrase
  entry (S2). Status: shipped.
- **Transient KVS blank clears the tombstone.** FINDING (2026-08-19), FIXED
  (2026-08-20): `tombstoneRouting` treated "no account hash" as "wallet gone
  → clear tombstone", but KVS can be momentarily empty (fresh cache after
  iCloud sign-out/in, pre-initial-sync) — a wrongly cleared tombstone
  silently resurrects the wallet. Fix: hash absence only clears the
  tombstone when the keychain corroborates it with a definitive `.notFound`
  (a full wipe elsewhere removes both signals; a KVS glitch leaves the
  synced seed readable; an unreadable keychain is not evidence either way).
  Test: `TombstoneRoutingTests` (transient + unreadable cases).
- **Registry staleness.** CloudKit lag makes heartbeats and the S7 blockers
  list stale. → Wrong blocking decisions, stale device lists. → Blocking
  threshold shorter than the 30-day staleness cutoff; override valve.
  Status: S7 proposed; thresholds undecided.
- **Clock skew.** `becamePrimaryAt` and heartbeats are device-clock-based;
  skew can flip reconciliation tiebreaks or heartbeat freshness. → Wrong
  reconciliation winner (rare; needs near-simultaneous claims + skew). →
  Accepted for now; server-side arbitration is the eventual fix.
  Status: accepted risk, follow-up exists.
- **Device backup restored onto a second phone.** The device-ID keychain item
  is non-synchronizable but travels in encrypted device backups — two
  physical devices can end up sharing one registry identity. → Heartbeat/
  primary/unlink confusion between the twins. → Undesigned; would need a
  liveness nonce or install-scoped identity component. Status: OPEN, known
  iOS pitfall, unhandled.

### C. Malicious

**The security boundary, stated honestly:** the app does not defend against a
compromised iCloud account or an unlocked device in hostile hands. Apple's
account security (password, 2FA) and the device lock are the walls; the app
adds *friction* (security checks) and *visibility* (notifications, device
list) inside them.

- **Stolen unlocked device.** Attacker sees balance/history (privacy loss)
  and — worst case — the recovery phrase (fund loss). → The proposed
  security-check matrix is precisely this mitigation: phrase display,
  deletions, and role changes re-check user presence. Balance privacy toggle
  already exists. Status: checks proposed, nothing gated today.
- **iCloud account compromise.** Attacker signs into their own device with
  the victim's account → joins as a silent secondary (S2 works for them,
  seed included) → can self-promote and spend. → Client cannot prevent this;
  it can expose it: PROPOSED "new device joined your wallet" notification on
  existing devices (also useful for honest S2/S5 flows), plus the promote
  security check on... the attacker's own device, which they pass — so
  visibility is the real mitigation. Status: notification proposed; risk
  otherwise accepted and documented.
- **Malicious household secondary.** Someone with occasional access to an
  unlocked secondary promotes it and spends. → Promote security check +
  demotion visibility on the old primary. Status: checks proposed.
- **Sold-but-not-erased device.** The buyer keeps opening the app: the ghost
  heartbeats forever (never goes stale → blocks S7 full wipe permanently),
  and a stranger holds a device whose keychain carries the seed. → The S7
  blockers list doubles as a detector — a device showing "active 2 hours
  ago" that the user knows they sold is a compromise indicator; unlink
  confirmation copy echoes the S4/S13 advice to move funds. Status: S7
  proposed; today this case both blocks deletion and goes unnoticed.
- **Registry vandalism.** Any same-account device can unlink others or write
  KVS primary flags. → Same-account only (inside the boundary); the
  reconciler resists accidents, not adversaries. → Server-side arbitration
  follow-up; until then accepted. Status: accepted risk, follow-up exists.

### D. Our-code faults

The recurring pattern — three incidents now — is **a device-scoped action
destroying account-scoped state**: the FFI deleting the synced seed on every
deletion (2026-08-19), and `deleteWallet()` clearing the shared network
config from iCloud KVS on a local-only delete, stranding the live secondary
on default-mainnet with a signet db that refused to open (2026-08-20, found
by the two-device verify). Defenses live elsewhere and are referenced, not
duplicated: launch contract rules 14–21 (invariants with incident history),
`WalletWipeCoverageTests` (SwiftData schema drift), `SharedStateWipeCoverage`
(keychain/KVS keys with declared deletion scopes), `WalletDeletionRejoinTests`
(routing + inventory consistency), the `SecItemDelete` owner sweep, and the
two-device on-device verification matrix as the gate for seed-touching
changes.

## Non-goals (explicit)

- Multiple wallets per iCloud account (hard invariant, enforced in code).
- Sharing one wallet across different iCloud accounts / family members.
- Non-Apple platforms as registered devices.
- Widgets/watch surfaces are projections of their host device, not devices.

## Derived work (gaps surfaced by this catalog)

Priority-ordered; tracked in `Open_Follow_Ups.md`. Status as of 2026-08-19:
S10 is DECIDED (read-only + explain); the S7 blocking design, the S5
assistant sketch, and the security-check matrix are PROPOSALS awaiting
Christoph's call — build items below assume acceptance and should not start
before it:

1. ~~Tombstone KVS-transient fix~~ — DONE 2026-08-20 (keychain-corroboration
   rule, see Failure modes §B).
2. Two-device on-device verify covering S2/S3/S4/S6 in one session (already
   the gate for the 2026-08-19 deletion work).
3. Security checks: fix `authenticateUser` policy
   (`.deviceOwnerAuthentication`), wire the gated-actions table. Small,
   touches every sensitive flow — do before the flows below so they're born
   gated.
4. S7 build: blocking full-wipe UX (blockers list, unlink-first paths,
   informed override), flip the `getDeletionStrategy()` error fallback to
   conservative, "wallet deleted elsewhere" cleanup-offer state. PROPOSED
   addition from Failure modes §A: phrase-confirmation (two words) on the
   final full-wipe confirmation as a backup-existence proof.
5. PROPOSED (Failure modes §C): "new device joined your wallet" notification
   on existing devices — the visibility mitigation for account compromise,
   also useful feedback in honest S2/S5 flows.
6. S4 entry point: the active "no primary device" banner (deferred
   2026-08-12) — reframe it as the "lost primary" journey's front door.
7. S5 build: migration assistant (orchestration + copy over existing
   primitives); delete `migrateToThisDevice()` (bypasses `becamePrimaryAt`,
   breaks the reconciliation tiebreak).
8. S10 build: read-only reasons for signed-out / account-changed, safe-exit
   copy.
9. Desktop parity for promote/demote UI (S3).
10. Devices-list scoping + automatic stale cleanup (S11).
11. Device-backup-twin identity problem (Failure modes §B): needs a design
    (liveness nonce or install-scoped identity); low frequency, real
    confusion when it hits.
