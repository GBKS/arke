# Open Follow-Ups

Cross-feature index of open work, ordered by priority so the top of the file
is always "what next". Detail lives in the linked guiding docs; this file is
the index. Closed items and their write-ups live in `Open_Follow_Ups_Done.md`
(moved there 2026-10-07 when this file was restructured from workstream
sections into tiers). Last consolidated: 2026-10-07.

How to use it:

- **Tiers, not sections.** Tier 0 is funds or security at risk, Tier 1 is
  what users hit every day, Tier 2 is shipped-but-unverified work, Tier 3 is
  polish grouped by screen, Tier 4 is tech debt, Parked is deliberate.
  Within a tier, items are grouped by area; order inside a group is loose.
- **Closing an item**: check it off with the date, keep it in place for a
  session or two as a reminder, then move it to the Done log.
- **New items**: add them to the tier they belong in, with a pointer and
  one line of context. Christoph's Reminders app is capture-only; sweep it
  into this file at the end of a session.
- **DECIDE / PROPOSAL** markers mean Christoph has not ruled; nothing below
  them is a decision until he says so.

Counts at consolidation: 211 open + 1 partial items from the old layout,
consolidated into 191 entries here (duplicates and same-screen items merged,
nothing dropped); 73 closed items moved to the Done log.

## Current train

Process: `Development/Release_Train.md` (two-week cycle: decide → build →
device day → TestFlight → soak). This block names the picks; it is rewritten
at the start of every train and the previous one is summarised in one line
under "Past trains".

**Train 1 — 2026-10-08 to 2026-10-21** (PROPOSED picks, Christoph to confirm
on day 1):

- Day 1 — rule on the "Decisions needed" list, at minimum: onchain default
  source, nearby payloads, dead images, rates cache (the cheap ones), and a
  first position on explicit device linking and full S7.
- Build — Tier 0, everything unblocked: BIP39 checksum; mainnet fee ceiling;
  BIP-353 DNS query skip + softer error; paste fallback; clipboard expiry
  2–3 min + macOS pasteboard; `RelayAPIToken` out of the repo; screen-capture
  protection; delete-flow partial failure; ghost mirror clear (1); audit the
  unprotected background store writes. Then the three send proposals
  (address header, fee three-state, onchain from Payments) as one cluster.
- Review (2026-10-14) — fresh-context adversarial pass over each cluster
  against the five fault classes (`Development/Change_Review_Playbook.md`);
  findings fixed or filed, ledger lines written, then the device-day
  checklist (`Development/Device_Day_2026-10-15.md`).
- Device day (2026-10-15) — the two-device set: deletion + rejoin, deletion
  strategy, second-iPhone read-only data, seeding scenarios, SwiftData
  import crash repro, self-unlink → relaunch; plus exit blocked state and
  exit completion with the stuck-signet wallet.
- Release (2026-10-16) — bump build number, code-review pass, TestFlight.
- Soak — 0xdead10cc signatures in Organizer, bark 0.25 day-15 renewal
  (~2026-10-11 falls inside this train), auth-wake journal rows.
- Deferred to Train 2 on purpose: claimed-exit-funds fix (needs a design
  pass on the claim address), security gating (depends on the device-linking
  decision), the offline feature, CI.

**Past trains:** none yet.

## Decisions needed (Christoph)

Scattered DECIDE and PROPOSAL items pulled together because they block
Tier 0/1 work. Guiding docs hold the full arguments.

- [ ] **DECIDE — explicit device linking** (proposal in
  `Architecture/Multi_Device_Design.md`, cross-cutting section after S13):
  should an install ever adopt the account's wallet silently, or disclose
  what it found and ask for one acknowledgement? Four open questions in the
  proposal. Absorbs "reinstall after a local delete silently rejoins" and
  "fresh secondary shows an empty wallet" (both below) and would retire the
  pre-open network reconcile patch rather than inherit it.
- [ ] **DECIDE — full S7 build vs. the reduced version shipped 2026-09-24**
  (blocker disclosure + informed override). Full S7 adds unlink-first paths,
  per-device confirmed "forget this device" for mirror-only ghosts, and the
  "wallet deleted elsewhere" cleanup state. See Multi-Device in Tier 1.
- [ ] **DECIDE — S5 migration assistant**: orchestration + copy over S2 join →
  promote → S6 retire, entry points on both devices. Deletes
  `migrateToThisDevice()` (writes `isPrimaryDevice` without `becamePrimaryAt`).
- [ ] **DECIDE — default source for onchain sends** when both Savings and
  Payments are viable (proposal: Savings, faster and keeps Payments liquid).
  See the Payments-balance onchain proposal in Tier 1.
- [ ] **DECIDE — nearby-exchange payloads accepted from any peer** (PR #8
  description): accepted whatever the distance check says, parsed on arrival.
- [ ] **DECIDE — duplicate default tags/contacts already in the account**
  (second iPhone's extra 9 tags + 2 contacts are in CloudKit): hand-delete on
  a device, or a one-shot dedup by name that re-points assignments before
  deleting the loser (`PersistentTag` has no unique constraint). Automatic
  post-import merge deferred 2026-09-25: it deletes CloudKit-mirrored rows
  outside `WalletDataCleanupService` (contract rule 23 fault class); if ever
  built it keeps the copy with assignments, runs under cleanup-service
  ownership, behind explicit user action.
- [ ] **DECIDE — wallet deletion and the rates cache** — PROPOSAL: clear the
  currency preference with other preferences, leave the cache.
- [ ] **DECIDE — dead Shared images in the Mobile bundle**:
  `Images/avatar-{female,male}-{1..4}.jpg` (8) and `Images/cover-animation.mp4`
  ship in iOS since Mobile attached to Shared; referenced by no code. Delete,
  or exclude in the File Inspector.
- [ ] **DECIDE — reinstall after a local wallet deletion silently rejoins**:
  tombstone is `UserDefaults` (wiped with the app) while seed + KVS hash
  survive, so detection routes into the wallet instead of `RejoinWalletView`
  (observed 2026-09-23). Defensible as designed; the keychain device-ID slot
  (`WhenUnlockedThisDeviceOnly`) has the right lifetime if it should change.
  Likely superseded by explicit device linking.
- [ ] **DECIDE — Live Activity across device migration**: `closeWallet()` /
  demotion keeps an in-flight exit's Live Activity alive (only deletion ends
  it). Should demotion end it too, since the demoted device stops progressing?
- [ ] **PROPOSED — "new device joined your wallet" notification** (failure
  modes §C): visibility mitigation for iCloud-account compromise; honest-flow
  feedback for S2/S5.
- [ ] **PROPOSED — phrase-confirmation on full wipe** (failure modes §A):
  final "Delete everything" asks for two recovery-phrase words.
- [ ] **PROPOSED — delete only when the user has no VTXOs?** (from Reminders;
  today the strategy only distinguishes last-device vs other-devices.)
- [ ] **Mark the four network-name log interpolations `privacy: .public`?**
  Undecided; simulator logs don't redact, device logs do.

## Tier 0 — Funds or security at risk

- [ ] **BIP39 checksum is not validated on import**: `validateMnemonic` in
  `BarkWalletFFI+Mnemonic.swift` still carries `// TODO: Add checksum
  validation`, so a 12-word phrase with one wrong wordlist word is accepted
  and opens a different, empty wallet. Validate before creating the wallet;
  show a "phrase has a typo" error.
- [ ] **Mainnet fee rate can still crash the app**: mainnet rates are
  uncapped and `FeeRateService.parse` only drops values past `UInt64`. A rate
  above ~6.6e16 sat/vB passes and crashes at
  `PaymentDestinationSelector.swift:482` (`Int(feeRate * estimatedVBytes)`)
  whenever an onchain destination is ranked. Sanity ceiling on mainnet (e.g.
  10,000 sat/vB) or checked arithmetic, plus a test.
- [ ] **Claimed exit funds invisible after seed import** (network-verified
  2026-08-13: 8,839 sats confirmed-unspent at the claim address, absent from
  balance — 143,041 shown vs 151,880 actual). `ExitClaimSequence.run` reveals
  a fresh address (`getOnchainAddress()` = `reveal_next_address`) as its FIRST
  step on every claim attempt, before `drainExits` can fail, and
  `ExitProgressionService` auto-retries failed claims each interval, so every
  failed attempt burns a derivation index. Claim addresses bypass
  `AddressService` history (untracked, not gap-limited); seed import loses the
  revealed-index state and both BDK gap-10 scans stop short. The receive
  screen's 20-unused cap also independently exceeds gap-10. Mitigations:
  (a) reveal the claim address only after a successful `drainExits` build, or
  persist one claim address per exit; (b) route claim addresses through
  `AddressService`; (c) import scan stop gap ≥ unused cap + margin (~50);
  (d) upstream — no rescan API (feedback §2.6). Also blocks the exit movement
  from linking its claim tx (`onchain_… not found` on every relink pass).
- [ ] **Warn on wallet deletion about forfeitable offchain balance** (field
  incident 2026-08-13: 10,000-sat VTXO swept at expiry 6h after deletion, app
  showed 0 with no explanation). Minimum expiry height across spendable VTXOs
  is known at deletion time — say "your offchain balance of X is forfeited
  around <time> unless this wallet is re-imported and refreshed before then."
  Deleting the last device deletes the only agent that can refresh.
- [ ] **Expiry-critical reminders vs. the notifications toggle**: the
  scheduled free-refresh reminder is silently dropped when notifications are
  disabled in app settings (as in the field logs). Exempt expiry-deadline
  reminders from the toggle, or warn that disabling risks missed deadlines.
- [ ] **`checkReadOnlyMode()` infers primary** (`WalletManager.swift:503-514`):
  a missing or unreadable device registration sets `isReadOnlyMode = false`,
  i.e. full spend rights — contradicts Principle 2 / contract rule 15.
  Reachable via self-unlink (`LinkedDevicesView_iOS.swift:46`). UNVERIFIED —
  needs a self-unlink → relaunch run before deciding the fix. Fix this before
  collapsing `shouldBlockWalletAccess`'s layers (Tier 4).
- [ ] **Security checks first**: switch `authenticateUser` to
  `.deviceOwnerAuthentication` (passcode fallback; biometrics-only hard-fails
  on Macs without Touch ID) and wire the gated-actions table (recovery phrase,
  deletions, promote/demote/unlink; send as opt-in). Its only call site is
  commented out — nothing is gated today. PR #8 review flagged the same.
- [ ] **Delete flow has no partial-failure handling**
  (`DeleteWalletSettingView.swift:205-236`): `deleteWalletData()` runs first,
  then `walletManager.deleteWallet()`; if the second throws, shared state is
  already destroyed and the user stays in-app with no navigation.
  `isDeleting` is never reset on success either.
- [ ] **Ghost-device hardening (1): make the mirror clear unconditional and
  first** (or in a `defer`) in `unregisterCurrentDevice`, and surface a
  failed unregister in the deletion summary — typed error + test. From the
  2026-09-26 incident (full write-up in the Done log): an uncleared mirror
  entry blocks every remaining device's full wipe for 48h with no override.
  Items (2)–(4) of that incident are in Tier 4.
- [ ] **Paste button accepts unverified Lightning Addresses**: in
  `SendViewModel+Clipboard`, `tryParallelResolution` and
  `tryLightningAddressFallback` fall back to
  `AddressValidator.parsePaymentRequest` when both lookups fail, accepting any
  `user@domain`. Typing the same address rejects it. Seen with `chri@sto.ph`.
  Remove the fallback or show a "couldn't verify" state so both paths match.
- [ ] **BIP-353: stop sending the DNS query while DNSSEC is unimplemented**
  — `BIP353Resolver.validateDNSSEC` always returns `false`, so every lookup
  is refused, but the query is still sent and its answer thrown away, telling
  the network's DNS who the user is about to pay. Skip the query now; soften
  the error text ("address may be compromised" + both raw errors) in
  `ManualSendView`/`ContactPaymentView`. Full DNSSEC implementation is Tier 1.
- [ ] **`RelayAPIToken` is checked into the repo**: read via
  `Bundle.main.object(forInfoDictionaryKey:)` in `WalletManager.swift`, so it
  ships in the Info.plist in git. Untracked xcconfig, build-phase injection,
  or drop it for per-device relay auth.
- [ ] **No screen-capture protection on the recovery phrase**: nothing
  observes `UIScreen.isCaptured` or uses `privacySensitive()` on the
  manual-backup / scratch-card views. Hide while recorded or mirrored; exclude
  from the app-switcher snapshot.
- [ ] **Background runs killed for holding a store lock (0xdead10cc)** —
  mitigations shipped 2026-09-24 (probe write removed, task assertions around
  `registerCurrentDevice` and the headless open; see Done log). Still open:
  **audit the other unprotected store writes on background-reachable paths**
  (`unregisterCurrentDevice`, the upsert in `refreshTransactionsAfterWrite`,
  the balance persist). Only the two crash-proven sites were wrapped.
- [ ] **Get Patrick's private write-up**: includes "a few multi-device and
  backup paths fail open". Check each claim against the source before acting.

## Tier 1 — What users hit every day

### Send and fees

- [ ] **Lightning fee estimation falls back silently**: when
  `PaymentDestinationSelector.estimateFee()` fails for a Lightning destination
  it logs and uses a static 20 sats, so the fee shown can differ from the fee
  paid and a too-low estimate can fail the payment. Surface "estimate
  unavailable" or block the send until the estimate succeeds. (Carried from
  `Archive/Fixes/LIGHTNING_FEE_ESTIMATION_ISSUES.md` item 3.)
- [ ] **PROPOSAL (2026-10-07) — Fee row three-state + stale-cache guard**:
  the fee row shows "—" for Lightning addresses and keeps the old value when
  onchain priority changes. (1) `feeAmount` for Lightning returns only
  `cachedLightningFee`; when `estimateLightningSendFee` throws,
  `calculateLightningFee` nils the cache → dash, while the ranking path hides
  the same failure behind the static 20 (the "20 ₿" on the 750-sat invoice
  screenshot is that constant). In quick mode with no viable ranked
  destination (`selectedDestination == nil`, balance label falls back to
  "Total balance") no fee path runs although Send is enabled.
  (2) `estimateOnchainFee` keeps the previous cache on any BDK/sync error and
  `feeAmount` returns `cachedOnchainFee` without checking
  `cachedOnchainFeePriority`/`cachedOnchainFeeAmount` match. Proposal:
  value / estimating / unavailable states (never a bare dash); `feeAmount`
  requires a cache match; log the bark error once and confirm on device
  whether the Lightning estimate really fails; when quick mode has no viable
  destination, say why.
- [ ] **PROPOSAL (2026-10-07) — Human-readable address header**: a plain
  Lightning address shows the address twice in a greyed, disabled destination
  row. `QuickPaymentView.swift:481` passes `formatNameOverride` whenever
  `BIP353Resolver.isBIP353Format` is true, and that test accepts plain
  `user@domain`; `ManualSendView`'s Lightning fallback stores the typed address
  as `originalBIP353Address` and reuses `.bip353Resolved`. The row is a button
  disabled when there are no alternatives. Proposal: (a) make the address the
  title line (replacing "Address found") with a caption like "Lightning
  address, paid from Payments balance" and drop the row; (b) keep the row only
  when there is a choice; (c) manual flow shows a one-line caption since
  "Send to" already shows the address; (d) restrict the override to
  ₿-prefixed or actually-resolved BIP-353 input.
- [ ] **PROPOSAL (2026-10-07) — Send onchain from the Payments balance**
  (asked by Neil, Second): bitcoin addresses can only be paid from Savings.
  The round-based path exists — `sendToOnchain` / `estimateSendToOnchainFee`
  on `BarkWalletProtocol` (bark `Wallet.sendOnchain(address:amountSats:)`) —
  used only by the offboarding modal. `balanceSource(for:)` maps `.bitcoin`
  to `.bitcoin` only; `SendViewModel+PaymentExecution` always calls the
  onchain-wallet `sendOnchain`. Also explains "scanned Noah QR, onchain failed
  with error building tx" (empty Savings). Design: ranking emits two entries
  for bitcoin addresses, selection keyed on (destination, source); the round
  path has a server fee, no priority picker, settles at the next round — say
  so in the option row; tell third-party round sends apart from offboards
  via `AddressService` history so Activity doesn't label them "Moved".
  Default source is a DECIDE above.
- [ ] **Contact assignment mixes up send and receive addresses** (four
  Reminders reports: batch assignment uses the receive-to address; assigning
  a payment adds the Lightning invoice as a contact address; assigning an Ark
  transaction proposes the user's own Ark address; assigning a contact to a
  Noah Lightning-address send did not add the address). Likely one root cause
  in the assignment proposal logic — see the address-history findings in
  Tier 4.
- [ ] **Failed payment errors are ugly** (Reminders). Pair with the
  three-state fee row since both touch the send summary.
- [ ] **Balance shows 0 while refreshing / "Payments balance: 0" while the
  card shows a balance** — label "Available payments balance" or hide during
  refresh (Reminders, two reports).
- [ ] **Send all from savings to spending did not work, needs a better
  message** (Reminders).

### Multi-device (guiding doc: `Architecture/Multi_Device_Design.md`)

Status: S10 DECIDED (read-only + explain). S7 reduced version shipped
2026-09-24; full S7, S5 and the security-check matrix await decisions above.

- [ ] **A payment on the primary does not promptly update the secondary's
  balance**, while tags and activity do. Narrowed 2026-09-23: the re-read
  path is proven (`ReadOnlySyncedDataTests/balancePicksUpInPlaceUpdate`), so
  suspicion is on the write/export side. Candidate cause: the rapid-fire
  notification drop fixed 2026-09-24 (Done log) — not confirmed. Evidence
  needed: primary's `💾 Updated persisted Ark balance` paired with the
  secondary's `📱 Loaded Ark balance from CloudKit (spendable: N)`.
- [ ] **Active "no primary device" banner** on secondaries' main view
  (deferred 2026-08-12): run `checkForNoPrimaryDevice()` on launch/foreground,
  callout deep-linking to `PromoteDeviceSheet`. Also the recovery path for
  **an account with no primary can never get default tags/contacts**
  (2026-09-25; deliberately not patched by showing the button when no primary
  is visible — a not-yet-imported registry reads as "no primary").
- [ ] **S10 build**: read-only reasons for signed-out / account-changed +
  safe-exit copy (sign back in, or local-only delete). Never auto-wipe, never
  pair local files with a foreign account.
- [ ] **Fresh secondary: balance card still reads 0 during the initial
  CloudKit import** (activity list got the `.syncingFromCloud` state
  2026-09-24; the card renders a substituted zero model). Decide whether it
  gets the same treatment. Also: the gate is balance-based (a balance batch
  landing first drops the syncing state early; a primary that never persisted
  balance rows leaves it up with no timeout) — honest upgrade is
  `NSPersistentCloudKitContainer` import events. Desktop `TransactionList`
  not wired (no read-only mode there).
- [ ] **Unlink-first for mirror-only ghosts** (deliberately not built
  2026-09-24; now the only remedy for a healthy-but-unwanted blocker since
  the override is no longer offered there): `unlinkDevice` throws
  `deviceNotFound` with no registry row, so needs `forgetUnsyncedDevice(_:)`.
  Build with the full S7 blockers UX, per-device and confirmed; fail closed
  when the registry can't be read. The "KVS-only ghost is invisible" item
  folds in here (delete screen already names mirror-only blockers; aged ones
  unlock the override).
- [ ] **Blocked-strategy copy**: `.localOnly` fallback shows "Other devices
  have this wallet", a guess in the error case. Needs a third state
  ("couldn't check — try again") = new strings. S7 blockers list supersedes.
- [ ] **Deletion-flow copywriting** (2026-09-26 session, cosmetic): strategy
  intro, blockers copy, override acknowledgement, scope-changed banner
  (`error_delete_scope_changed`) — then de/ja/zh-Hant.
- [ ] **Delete wallet amount-warning copy is not right** (Reminders) — same
  pass as the above.
- [ ] **Desktop parity for promote/demote UI** (S3; unlink exists on both).
- [ ] **Devices: plan forced promotion; allow deletion / renaming of
  devices?** (Reminders) → extend the scenario catalog first.

### Connectivity and offline

- [ ] **Offline / server-down experience** (one feature, merged from eight
  Reminders items: "stunningly designed no-connection state", server-down
  and no-internet messages with disabled functionality, server-offline tip to
  withdraw funds, disable send when offline, animate the connection icon
  while connecting, track and surface the disconnect reason —
  `connectionError` is captured in `WalletManager` but never shown — and a
  Settings disconnect button?). Design the states (offline vs server down vs
  connecting), decide what each disables, surface the stored reason, build.
  Related dead code: connection quality is binary in practice (Tier 4).
- [ ] **Invoice request timeout**: unknown how long `getLightningInvoice`
  takes to fail with no connectivity (bark's timeout, unmeasured). If minutes,
  users give up before Try Again / Share Addresses Instead appear. Measure
  under 100% Loss, decide an app timeout, device-verify the failure path.
- [ ] **Invoice creation polish**: "Slow connection, still trying…" after
  ~5 s; say "offline" right away when the wallet knows; VoiceOver
  announcement for "Creating invoice".

### Release readiness

- [ ] **Distribution compliance** (Reminders): Terms of Service; Privacy
  Policy with data collection and storage; remove all "prototype" references;
  age-rating compliance. Website: revise privacy statements (via Max).
- [ ] **Translation debt — 80 user-facing keys have no de/ja value** (zh-Hant
  89): deletion strings (`settings_delete_warning_local_only_named %@` and
  13 more, listed in the Done log under Wallet Deletion), `metadata_*`
  export/import set, ~28 X-Ray `data_bg_*` keys, 5 `ManualRefreshOutcome`
  keys (`status_refresh_not_needed`, `balance_refresh_not_needed`,
  `status_refresh_already_underway`, `balance_refresh_already_underway`,
  `balance_refresh_already_scheduled` — absent from the catalog until an IDE
  build extracts them; don't hand-add, re-extraction empties them), `rejoin_*`
  (`rejoin_title`, `rejoin_message %@`, `rejoin_button`,
  `error_wallet_already_on_account`), `data_bg_next_renewal_label`,
  `transaction_list_syncing_*`, `data_fiat_rates*`, `settings_currency*`.
  All render English `defaultValue` (no raw keys) — cosmetic for TestFlight,
  the whole Phase 3 debt in one number. `apply_translations.py` +
  `translation_lint.py` once extracted.
- [ ] **Native-speaker review of the de/ja first pass** (1,090 × 2 values
  `needs_review`, 2026-08-18): glossary ⚠️ terms first (Übertrag, Rechnung,
  Hauptgerät/Zweitgerät). Required before shipping the languages.
  `Localization/Translation_Rollout_Plan.md`.
- [ ] **Native-speaker review of the zh-Hant first pass** (1,088 values,
  2026-08-23): 聰 vs "sats", 復原片語 vs 助記詞, 付款請求, 轉入/轉出, the
  拷貝/剪貼板 vs 複製/剪貼簿 pair.
- [ ] **Phase D per-language QA**: App Language de (+30% expansion layout
  pass — badges, fixed-width buttons, alerts), ja (typography), zh-Hant
  (CJK/Latin spacing, line breaking), plus guard test + full suite.
- [ ] **Set up CI via GitHub**: no `.github/` exists. Pair with the nightly
  AI security review via scheduled Claude tasks, which needs CI first.
- [ ] **macOS test suite fails ~68 of 272, flaky, for an unknown length of
  time** (measured 2026-09-22 on a clean tree): failures span nearly every
  suite while iOS runs the same Shared tests green, pointing at shared
  mutable state across parallel macOS test hosts (keychain, UserDefaults,
  KVS — `TombstonePersistenceTests`, `KeychainAccessibilityMigrationTests`
  mutate process-wide state). Consequence: desktop regressions are
  undetectable. `.serialized` suites or scratch-scoped keychain/defaults.
  Fix before desktop parity work.
- [ ] **Recovery phrase clipboard**: expiry of 60 s (`copySecretToClipboard`
  default, `Shared/Helpers/Clipboard.swift`) is too short to reach a password
  manager — raise to 2–3 min. macOS still uses the plain general pasteboard
  with no expiry — `org.nspasteboard.ConcealedType` + delayed clear.
- [ ] **BIP-353 DNSSEC validation** (full implementation): DNSSEC-validating
  library, RRSIG check, or a validating DoH resolver. Unblocks the four
  BIP-353 items in Tier 3 (BIP-353 vs Lightning address logic, resolved
  address display, contact address differentiation).
- [ ] **OS `bitcoin:` URI scheme registration**: no `CFBundleURLSchemes` in
  either Info.plist. Also test the macOS Shortcuts integration (only the
  widget has App Intents).

## Tier 2 — Verification debt (shipped, never confirmed)

Cheap to clear in a dedicated device session; expensive to carry. Each item
names the fix it verifies; the write-ups are in the Done log.

### Two-device

- [ ] **Deletion + rejoin** (fix 2026-08-19, `Features/Wallet_Deletion_And_Rejoin.md`
  definition of done): local-only delete keeps the seed everywhere (phrase
  still displays on the other device); deleted device shows the rejoin
  screen and relaunch does NOT resurrect the wallet; Rejoin restores from the
  preserved iCloud backup; create-wallet refused while the account has a
  wallet. Gate for calling the seed-deletion fix done. Add: delete on a
  freshly joined secondary while CloudKit is still importing → must say
  "Delete from This Device" (2026-09-21 KVS-mirror fix).
- [ ] **Deletion-strategy fix** (2026-08-12): delete on the primary →
  secondary's Linked Devices shows "no active wallet" + "Make This Device
  Primary" once CloudKit syncs → promotion restores from the iCloud backup.
- [ ] **Second iPhone read-only data** (fix 2026-09-23): with the app running,
  move funds on the primary → secondary's balance updates without relaunch;
  receive screen shows an address; pull-to-refresh leaves no error banner.
  Confirm in the log that `Loaded Ark balance from CloudKit (spendable: …)`
  follows a `[CloudKit] Remote change detected` round.
- [ ] **Seeding scenarios** (import-gated seeding, contract rule 26):
  (1) reinstalled primary → exactly 9 tags + 1 faucet + customs, gate-wait
  log line; (2) fresh account → seeds immediately, no 90 s wait;
  (3) reinstalled secondary → never seeds; (4) iCloud signed out + import →
  seeds after ~90 s timeout (`log show --info --debug`).
- [ ] **SwiftData invalidation on the second iPhone** (fix 2026-09-23/25):
  launch during the initial CloudKit import (the crash repro), assign/unassign
  a tag from the detail and confirm the list label updates (`dataVersion`
  moved from row to list), check a tag-filtered and a contact-filtered list.
- [ ] **Self-unlink → relaunch** run to settle the `checkReadOnlyMode()`
  finding in Tier 0 before choosing its fix.

### Exits and refresh

- [ ] **Exit blocked state**: on-device verify + WalletManager tests
  (`Features/Exit_Blocked_State.md`, phases 1–3 done). Also closes the
  Reminders report "error when not enough onchain to progress exit".
- [ ] **Exit completion issues**: on-device verify with a wallet that has
  both claimed and cancelled exits (`Features/Exit_Completion_Issues.md`).
  Also closes "exit fee calculation includes pending onchain / fees are off"
  and "completed force move still reads 'Force moving'" (display helpers now
  have `transaction_force_moved_amount`).
- [ ] **Refresh dedup on-device signet verification** (doc §6): parsing gate
  first — log `subsystemName`/`subsystemKind`/`category` right after
  scheduling (the **category mapping** is the unverified half of Phase 1,
  marked `[~]`: `.refresh` requires `subsystemName == "bark.round"` and
  `subsystemKind == "refresh"`, and a miss silently empties the signal);
  then card flips to "Refreshing", no duplicate schedule from hourly or
  foreground check, "Already refreshing" on a raced tap. Also closes the
  Reminders report "active refresh in Activity while card and balance still
  say 'Refresh now'".
- [ ] **Refresh reminder inside the free period** (bcdb0fa): confirm no
  reminder fires inside the fee-free window.
- [ ] **Pre-open refresh skip path** (2026-10-01): soak through normal use —
  grep exported logs for `⏭️ [Refresh] Skipped` (first real exercise; lines
  before it name the trigger, mailbox push suspected) and any
  `walletNotInitialized`. Owed too: desktop `ActivityView.swift` still shows
  the never-cleared banner (parked with desktop); `TransactionService.error`
  is never cleared on success — drop or clear it.
- [ ] **Bark 0.16 v1-snapshot wallet** upgrade path, never verified on device.

### Background and relay

- [ ] **0xdead10cc kills**: watch Organizer for build 25+ signatures at
  `getWalletDirectory`/`registerCurrentDevice` and the new `⏳ Background
  assertion '…' expired` / `ℹ️ … not granted` lines. Absence over a week of
  wakes is the only confirmation.
- [ ] **Auth wake push from field data** (2026-09-17/21, acceptance criteria
  in `Features/Background_Execution.md`): X-Ray journal rows "Auth wake push ·
  refreshed" and "Stale mailbox unregistered · success · wake_push"; relay
  side `trigger: "wake_push"` under `auth_refresh.refreshes_after_wake` and
  DELETE `/v1/register` `removed: 1` shortly after a wake. DELETE carries no
  trigger; orphans past their 7-wake budget never wake again — "no signal" ≠
  broken.
- [ ] **Bark 0.25 day-15 renewal**: journal when it happens (~2026-10-11), or
  sooner on the simulator by backdating `com.arke.relay.lastRegisteredAt` /
  `com.arke.relay.authExpiresAt` via `simctl … defaults write`. **Relay-side
  confirmation** after a week: registrations per trigger drop to ~1 per
  device per 15 days; pre-expiry 2h/1h wakes stop for updated devices.
- [ ] **Background activity journal leftovers**: simulated-wake journal
  verify (plan Phase 1 item 4), on-device look at the relay cross-check row,
  events-list bottom row can sit under the floating tab pill.
- [ ] **Verify the rest without the ATS exception** (PR #8): force a relay
  register call (not a still-valid registration) and the signet faucet over
  HTTPS.

### Other on-device looks

- [ ] **Fiat**: X-Ray "Exchange Rates" section on a wallet install (currency
  count, file time, last checked, last result — the simulator has no wallet);
  German separator on the keypad key and in the partial display.
- [ ] **Metadata import round-trip**: export on one device → import on a
  fresh wallet (`Features/Metadata_Export_Import.md`); then the faucet
  avatar re-encode drops the export to ~KB.
- [ ] **Startup routing retests** (Reminders): delete-and-create landing on
  the delete-wallet screen instead of the wallet; importing right after
  delete seeming to freeze the app. Both predate the startup hardening.
- [ ] **Notification permission on first received payment** when never
  asked: `requestAuthorization` runs from the invoice sheet, refresh and exit
  services; confirm the receive-without-invoice path asks too.
- [ ] **Exit local notifications still working?** → needs the X-Ray local
  notification listing (Tier 3, Refresh).
- [ ] **Transaction address parsing (Strings → Objects) when assigning to
  contacts** (Reminders): predates the address-history rework; verify with
  one assignment, probably obsolete.

## Tier 3 — Polish by area

One pass per area when that screen is touched. Mostly from the 2026-10-07
Reminders merge; wording kept so the two can be matched.

### Send

- [ ] **Number pad sometimes has no Done button** (also "amount input
  keyboard done button"). Related: tap-outside keyboard dismissal added to
  the Boarding/Offboarding forms 2026-08-21 as fallback for the flaky toolbar
  Done; `ManualSendView`, `QuickPaymentView`, `ContactPaymentView` still rely
  on the toolbar alone — denser layouts, apply with a closer look.
- [ ] **Fees not correctly calculated in the Zinqq multi-address selector
  sheet**; add a large-address review in the multi-address picker.
- [ ] **Review logic for telling BIP-353 and Lightning addresses apart**;
  a contact with a resolved BIP-353 shows only the resolved address in the
  send view — both DNSSEC-blocked (Tier 1).
- [ ] **LNURL comment input and metadata** (short/long text, image) —
  `Features/LNURL_Pay.md` "not implemented"; `commentAllowed` is parsed and
  ignored (`comment: nil` passed to `payLnurl`).
- [ ] **Switch send button to a slider for larger amounts**.
- [ ] **Toggle icons blink again; no-contacts icon should be white and more
  distinct; animated highlight when parsing the clipboard; some character
  videos are awkwardly cropped in the send modal** (video sizing finding in
  Parked → Themes).
- [ ] **How to detect if an address is from a different Ark server?**
- [ ] **Parse Cashu NUT-18 `creq` parameter** (idea).
- [ ] **Input field type detection – test thoroughly**.
- [ ] **Send-metadata tidy-ups**: `SendNoteEditorSheet.maxCharacters = 500`
  declared but never enforced while `PersistentTransaction.notes` says 1000 —
  pick one and enforce it; dead `SendMetadataSection.iconView(systemName:isFilled:)`,
  `SendModalContentView.stateMessage` only referenced from a commented block
  and its `.error` video branch still says "Phase 3b will add…";
  `PendingPaymentMetadata.matchedTxid` comment says "for debugging" but it is
  load-bearing (priority-0 matching) — fix the comment.

### Receive

- [ ] **Temporarily brighten the screen when showing a QR**
  (`UIScreen.main.brightness`, restore on dismiss).
- [ ] **Test scanning from a laptop camera; ensure amount and memo input
  interactions work properly**.
- [ ] **QR network indicators not showing?**

### Activity, transaction details, tags

- [ ] **Does a Lightning-address send movement include the address?**
- [ ] **Hide failed and completed refreshes that were free?**
- [ ] **Balance tag shows "-0 B fees paid"; needs a no-fee state**.
- [ ] **Tag amounts — do they include fees, should they? Balance tag must
  include onchain child-tx fees**.
- [ ] **Transaction details**: show the invoice description when present
  (Opago order numbers); description for refreshes; onchain send-to /
  received-from addresses; onchain txid with explorer link; general
  clean-up; remove blue from the status colours?
- [ ] **Exit status — long-press copy copies the truncated txid**.
- [ ] **`TransactionCardStackView_iOS` holds `[PersistentTransaction]`** in
  `@State` for the overlay's lifetime; if an import deletes the movement row
  while the overlay is open, reading its own properties still traps. Pass
  txids from the list and re-fetch the window; re-verify the entrance/drag
  choreography on device.
- [ ] **Fiat on transaction detail and rows** — skipped 2026-09-29 (decide the
  "today's rate" wording first). `Features/Fiat_Rates.md` Phase 3.

### Balance, board / offboard

- [ ] **Onboard modal**: minimum value only shows after X-Ray was visited;
  add fee info; success message with duration; test the error state.
  **Offboard modal**: add fee info; add data to success (claim required?);
  test the error state. **Boarding**: calculate and display the network fee;
  adjust the amount input to the unit setting; offboard takes a long time.
- [ ] **Fee summary — move to savings showed up as a send**.
- [ ] **Full bitcoin format — add satcomma spacing** (nothing in
  `BitcoinFormatter` does it).
- [ ] **Settings — combine unit format and show-balance?** (question).

### Refresh

- [ ] **X-Ray: list local notifications** (requested 2026-09-27): show
  `pendingNotificationRequests()` (id, title, category, `nextTriggerDate`)
  and `deliveredNotifications()` next to the Background Activity rows, plus
  the scheduler's inputs (current height, target height, blocks remaining,
  seconds/block). A full history needs a `localNotificationScheduled`
  journal kind plus journaling in the `willPresent`/`didReceive` hooks.
- [ ] **Show a message the first time the user has expired VTXOs?**
- [ ] **Make the overlay better reflect the current state**.
- [ ] **Warn when total VTXOs are under 330 sats, and don't show "Refresh
  now" below that minimum** (`VTXORefreshService` already uses 330 as the
  floor; the UI does not).
- [ ] **`RefreshModalFormView` — description text is cut off even when the
  modal is fully expanded**.
- [ ] **Surface expiry sweeps instead of silently showing less money** — on
  import VTXOs come back as bare `Spent` with no reason. Blocked on upstream
  spent-reason (`sweptAtExpiry`, feedback §1.9 / ask 17); once available,
  write an explicit "expired" history entry.

### Exits

- [ ] **Adopt `cancelExit` from bindings v0.18.0**: the escape hatch for
  fee-blocked exits. Prerequisites: Live Activity `ExitState` lacks terminal
  `canceled`/`vtxoAlreadySpent`; verify the date-freeze workaround covers
  explicit cancels (feedback §1.4); check whether bark purges cancelled exits
  from `getExitVtxos()` like claimed ones (snapshot into
  `PersistentExitCache` if so). Notes in `Bark_Bindings_Unadopted_API.md`
  §1.1. Folds in the Reminders question "review exit cancellation — only
  until the first transaction is committed?".
- [ ] **`estimateEmergencyExitFee(...)` exit pre-flight** — broadcast vs
  claim fees separately; block/warn hard on `fundable == false`. Slow call
  (syncs the onchain wallet first).
- [ ] **Exit UX pass** (Reminders): completed exit did not show the status
  bar with details (should it?); switch up the notification when done; fix
  progress state in label; remove UI of the manual claim step; review the
  experience from first interaction; more testing.
- [ ] **Disable the Settings exit entry while an exit is active?**
- [ ] **Alternative Esplora server / Esplora setting in Settings** (Esplora is
  only configurable via `NetworkConfig` today).
- [ ] **When the daemon auto-exits VTXOs, how to detect and tell the user?**
- [ ] **Is there exit grouping, or is each VTXO its own movement entry?**
- [ ] **Options to handle failed Lightning payments (exit?)**.
- [ ] **Drain wallet option** (Settings).
- [ ] **Report upstream to bark devs** (network-verified on the stuck signet
  wallet): exit package txs don't exist on the network despite bark reporting
  broadcast; round-replacement VTXO fails signature validation.

### Settings, devices, deletion

- [ ] **Backup — how to explain that not all wallets are compatible?**
- [ ] **Importing a signet wallet in the mainnet flow shows an ugly overlay**.
- [ ] **Two "Faucetto Signetto" contacts** — default-contact creation lacks a
  dedupe check on reinstall / rejoin (insert-time store dedup exists as the
  gate's timeout backstop; check it covers this path).
- [ ] **Rejoin wallet screen is unstyled**.
- [ ] **Savings deposits don't show up automatically** — note in the
  notifications explainer until Background Execution Phase 2 lands.
- [ ] **Optional self-heal on network mismatch**: bark's db knows its own
  network — on a mismatch open failure, derive the config from the db instead
  of the stored setting (needs a bindings check for reading the db network
  without a chain source).

### Contacts

- [ ] **Native-contact linking, remaining pieces**: link an existing contact;
  display the link and offer to remove it; test unlinking and deleting a
  linked native contact; explore saving BIP-21s to native contacts. (Import,
  refresh and unlink-on-delete exist in `ContactService+NativeIntegration`.)
- [ ] **Contact permission setting — test**.
- [ ] **Clipboard — offer to add or assign to a contact; copy functionality
  fixes in various places; don't always pop the clipboard modal on first
  view**.
- [ ] **Distinguish testnet and signet addresses; more subtle network display
  when adding an address; differentiate BIP-353 and Lightning address,
  actually resolve and test** (DNSSEC-blocked).
- [ ] **After adding a contact it doesn't instantly show in the transaction
  list; refresh-from-native updates the header in the sidebar**.
- [ ] **Assign-contact modal design improvements; "x" should close, not
  unset**.
- [ ] **Move the deletion-logic note into the address-deletion confirmation
  modal**.
- [ ] **Adding an address doesn't update the persistent model right away;
  tapping send on it says it cannot be found on the contact** (likely the
  cached-relationship rule — read with a fetch in the same main-actor pass).
- [ ] **Restyle the contact view; invite-friends feature (no fees between
  Arké users)**.

### First use

- [ ] **Allow swiping up through the videos; intro video play-button
  flicker?; TL;DR screen when skipping the video?**
- [ ] **Internal flag for "user has backed up the mnemonic" + backup reminder
  once there are funds** (no such flag exists; `BackupStatus.reminderMessage`
  and `shouldShowBackupReminder` exist unwired, see Tier 4 process state).
- [ ] **Import — autocomplete for seed words** (`EnglishWordListProvider`).
- [ ] **Image in move-to-payments has a slight white line on the left**.

### X-Ray and Tilt

- [ ] **Options view / `VTXODeveloperActionsView` don't refresh when another
  VTXO is selected** — key the view on the VTXO id.
- [ ] **Tilt share — pay is not working; explore Mesh user detection instead
  of NearbyDevices** (and the any-peer payload DECIDE above).

## Tier 4 — Tech debt and deferred by design

### Concurrency and the FFI boundary

- [ ] **`TaskDeduplicationManager.cancel`/`cancelAll` have never worked**:
  both cast to `Task<Any, Error>` / `Task<Any, Never>` and `Task` is
  invariant, so `cancel(key:)` is a no-op and `cancelAll()` clears the
  registry with operations in flight (next `execute` → concurrent duplicate).
  Low impact today (only `ServiceContainer.cleanup()` at teardown). Fix:
  type-erased cancel closures per task. Deferred again 2026-09-24: making
  `cancelAll` real starts cancelling fund-adjacent operations never written
  to be cancellation-safe — needs a per-key review. `generations` also never
  cleared (bounded, harmless).
- [ ] **Surface typed errors across the bark FFI boundary**: every
  `Bark.Error` collapses into `BarkWalletFFIError.configurationError(_:)`, so
  callers string-match (`isAlreadyIssuedRejection`). One case per recoverable
  variant, starting with `unusable_inputs`.
- [ ] **Thread the live refresh-expiry threshold into `RefreshExclusion`**:
  the valve hardcodes 144 to mirror bark's `vtxo_refresh_expiry_threshold`
  (FFI config passes `nil`); needs a cached `arkConfig` on `WalletManager`.
- [ ] **`refreshTransactionsAfterWrite()` costs an extra `getMovements()`
  under contention** (drains the in-flight fetch and runs its own). Accepted;
  cheaper design: write sequence + join when the in-flight fetch observed it.
- [ ] **Refresh dedup deferred notes** (doc §3/§5): near-expiry valve is
  auto-path-only; `findVTXOsForAutoRefresh` embedded and untested;
  `vtxoIdsBeingRefreshed()` has no test seam; modal list/amount can diverge
  from what the service refreshes (valve + mid-flight changes) — revisit after
  the device run.
- [ ] **18s gap between `initialize()` called and executed** (device log
  2026-09-08) — relative anomaly within one run; suspect the
  dedup/queueing layer. Check it reproduces before digging.
- [ ] **Daemon auto-start on `Wallet.open()` (bark 0.7.0)**: our explicit
  `runDaemon()` logs `Called Wallet::start_daemon while daemon was already
  running` — may restart a just-started daemon every launch. Drop the call or
  confirm the double-start is a no-op.

### Device registry cleanup

- [ ] **Ghost-device hardening (2)–(4)**: re-run the device assessment and
  refresh Linked Devices on `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
  (today the primary needs a relaunch to see a cleared ghost); log each
  blocker's device-ID prefix and `registeredAt` in the "Other-device check"
  line; debug-only override of `mirrorSettleWindow` (a test ghost blocks for
  two days by design).
- [ ] **Collapse `shouldBlockWalletAccess`'s three layers**: layer 2 has no
  unique job (its KVS flag is only ever written by the reading device). Left
  because layer 3 returns nil on a fresh install and would hand a new
  secondary spend rights — fix the Tier 0 `checkReadOnlyMode` item first.
- [ ] **Dead device-registry code**: `cleanupStaleDevices()` and
  `migrateToThisDevice()` have zero call sites; `DeleteLocallyConfirmationView`
  is never instantiated. Delete `migrateToThisDevice()` with S5.
- [ ] **Remove the dead `showNoPrimaryDeviceBanner` NotificationCenter post**
  (`DeviceRegistrationService.demoteThisDevice`) — nothing observes it.
- [ ] **Devices-list display scoping** to the current wallet's registrations.
- [ ] **Server-side arbitration for primary claims** — reconciliation is
  client-side only.
- [ ] **Multi_Device_Design S7 note**: a deleted wallet's 30-day mailbox
  authorization stays valid on the Ark server (cannot be revoked); read-only
  and the mailbox holds nothing new, but worth a sentence.

### Code findings from the 2026-09-27 doc rewrites (unverified beyond a grep)

- [ ] **Onchain "used" marking may rarely fire**: `linkTransactionToAddress`'s
  `type == "received"` branch is the only setter of `PersistentAddress.isUsed`,
  but `PersistentTransaction.address` is documented nil for receives. If so,
  onchain rows stay "unused" forever and the gap counter climbs. Verify what
  bark puts in movement destinations for receives. (Feeds the contact
  assignment mixups in Tier 1.)
- [ ] **Address history dead surface**: `AddressGenerationStrategy.discovered`,
  `AddressError.invalidAddressType`/`.addressNotFound`,
  `PersistentAddress.hasBeenUsed`/`totalReceivedFormatted`,
  `AddressService.getUnusedAddressCount`, `validateGapLimit`.
- [ ] **Address history unlocalized strings**: `AddressHistoryView` section
  titles, gap-limit alert, `effectiveTypeDisplayName`,
  `AddressError.errorDescription`.
- [ ] `generateNewAddress` checks duplicates *after* calling bark (a duplicate
  still consumes a revealed index); `AddressService.loadAddresses()` dumps a
  call-stack trace in DEBUG on every call; no unit tests cover
  `AddressService` or `linkTransactionToAddress`.
- [ ] **Process state**: connection quality is binary in practice
  (`updateConnectionStatus`'s `quality:` never passed; `.good`/`.poor`,
  `from(lastSuccessfulSync:)`, `from(latencyMs:)`,
  `incrementReconnectionAttempt()`, `updateQuality(from:)` unused — the
  offline feature in Tier 1 decides their fate); `vtxoHealth`,
  `shouldShowBackupReminder`, `needsAttention`/`attentionSummary`/
  `attentionItemCount` have no view consumers; `VTXOHealth.actionMessage`,
  `BackupStatus.reminderMessage` hard-coded English. Wire up or delete.
- [ ] **CloudKit-merge duplicates never cleaned**: `loadPersistedData` takes
  `.first` without dedupe while `BackupStatus.getSingleton` and
  `cleanupDuplicateBackupStatus()` exist with zero callers.
- [ ] **Balance persistence**: `loadPersistedArkBalance()` /
  `loadPersistedOnchainBalance()` are private wrappers with zero callers;
  `isValid` only changes a log line; no direct unit coverage of the upsert
  path or `init(from:)`/`update(from:)`.

### Bindings adoption

`Bark_Bindings_Unadopted_API.md` records the unadopted surface (baseline
v0.25.0 / bark 0.7.1). Migration guides in `Migrations/`.

- [ ] **Keep the unadopted-API record current on every bindings bump**.
- [ ] **`initialScanOnchain(birthdayHeight:)` on import** — recovers onchain
  history from a previous incarnation of the seed; `sync()` never finds it.
  Needs a "scanning" import UI state + on-device verify. (Relates to the
  Tier 0 claimed-exit-funds item.)
- [ ] **`recoveryStatus()` adoption** — distinguishes recovery-failed from
  never-ran; at minimum log `.failed(message:)` where the import path reads
  `recoveryReport()` (`BarkWalletFFI+WalletCreation.swift:572`).
- [ ] **0.23 Phase 3 (optional, ask first)**: `RoundFlowKind`-rich round UI,
  externally funded board (`boardFundingAddress`/`boardPsbt`),
  `OnchainWallet.evictTx`.
- [ ] **0.24: `importVtxos` batch adoption** (no import loop exists;
  `WalletManager.importVtxo` has zero callers) and **protocol mirroring of
  `importVtxo(args:)` / `recoverVtxos(gapLimit:)`** when a caller needs a
  non-default.
- [ ] **0.25: `ExitClaimTransaction` included-ids gap** — skips unclaimable
  ids silently, so `recordClaim` links every *requested* id. Asked upstream
  (feedback §1.3 addendum); no app workaround planned.
- [ ] **BDK fee estimator removal, Phase 3** — blocked until bark exposes
  onchain estimate/drain fee APIs; then drop `bdk-swift`.

### Startup and background structure

- [ ] **Startup wallet detection review follow-ups**: 8 items in
  `Initialization/Startup_Wallet_Detection_Plan.md`; optional Phase 5
  refactor. **Next pure-logic extraction**: wallet-detection decisions
  (contract rules 3/4/14).
- [ ] **Keep `Initialization/Launch_Sequence_Contract.md` current**: every
  startup-shaped fix adds a rule.
- [ ] **~600 lines of `CoreData: error` on first launch after reinstall**: the
  App Group `Library/Application Support` directory doesn't exist yet; create
  it before building the container (that launch took 13.8s).
- [ ] **A background launch still builds the whole app**: `App.init()`
  constructs `WalletManager` → `BarkWalletFFI` and the CloudKit container
  before anything knows whether the launch is UI or a wake. Direction: lazy
  wallet/FFI construction; revisit with Background Execution Phase 2.
- [ ] **Background Execution Phase 2**: mailbox push wake → full background
  pass. Relay stays dumb except the auth-expiry wake. Also carries
  "payment notification → navigate to that payment" and "notifications on
  onchain deposits" from Reminders.

### UI components, refactors, tooling

- [ ] **ArkeGlassButton adoption sweep** (~45 `.glassProminent` + ~29
  `.glass` hand-styled sites across ~39 files; adopted in
  DeviceAssignmentSheets_iOS only; expect slight normalization to
  title2/`.large`). `ArkeButtonStyle` (5 sites) is a separate later cleanup.
- [ ] **ArkeCircularIcon adoption sweep**: FaucetModalView_iOS,
  PaymentInfoReceivedSheet, QRScannerView_iOS, desktop WalletCreatedView /
  WalletImportedView.
- [ ] **Previewable models extraction, Phase 3b** (paused; opportunistic).
  `Previewable_Models_Extraction_Plan.md`.
- [ ] **Delete the emptied `TransactionModel+OnchainAdapter` file** (needs an
  Xcode pass); `arke-qr-background` in `Media.xcassets` is referenced nowhere.
- [ ] **Revise use of Int / UInt32 etc. through the app, starting with the
  Bark bindings** (0.23 widened a few to UInt16).
- [ ] **Memory profiler pass** to see if memory piles up over time.
- [ ] **Move relay to DigitalOcean**; **Arke.me domain?** (external).
- [ ] **`Data samples/` → `Data_Samples/`** (folder names were out of scope
  for the 2026-09-27 filename standardization).

## Parked (deliberate)

### Desktop parity (`Features/Desktop_Parity.md`)

Onboarding, settings, launch/registration done. Desktop is ignored in the
day-to-day workflow until the macOS test suite is trustworthy (Tier 1).

- [ ] Exit UI; notifications; promote/demote UI (S3); read-only mode for
  `TransactionList`; embed `CurrencySettingView` next to `ThemeSettingView`
  (one line, the view is Shared); the never-cleared banner in
  `ActivityView.swift`.

### Themes (`Features/Theme_System.md`)

- [ ] **Send-modal and balance-modal video sizing** — parked 2026-08-21, code
  reverted. Keep: the reaction videos display LANDSCAPE ~3:2 (encoded portrait
  with a 90° rotation; `mdls`/`naturalSize` lie, only `presentationSize` or a
  thumbnail shows the truth). A full-width 3:2 window showed the whole video
  in the medium detent but wasn't accepted visually.
- [ ] **Per-theme color palettes** (deferred by design).

### Website and marketing

- [ ] "Discuss with AI" buttons; video explainers per test page;
  content-marketing article series on Ark and Lightning topics.

### Future ideas (not scheduled)

- [ ] Fave-friends quick send from Activity; propaganda videos; throw/swipe
  sats at people; replace address parsing with Matt's Rust crate; Ark server
  picker V2 with auto-pick default (plus the cover-screen server selection
  mockup); console; Passkey (may be moot given the server requirement); export
  transactions (metadata export covers part of this); macOS Shortcuts.
