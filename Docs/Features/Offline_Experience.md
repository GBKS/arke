# Offline and Server-Down Experience

**Status:** OPEN (Tier 1 Connectivity). Section 1 is built (2026-10-12, Train
1) with a device check owed; section 2 is the CONFIRMED signal defect that has
to land before the rest; section 3 is the feature itself. Short related entry
that stays in the backlog: "Open-time server connection fails on a cold start".

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Launch icon: "no Ark connection" during the whole launch refresh (built 2026-10-12)

- [ ] **The activity screen shows "no Ark connection" for the whole launch
  refresh although the server answered in 1 s** (Christoph's unattached
  log 2026-10-12, icon visible ~19–23 s): `connectionStatus.isConnected`
  is written only in Step 4 of `performRefresh`
  (`refreshProcessStates(isConnected: anyServerCallSucceeded)`), after the
  two onchain syncs above; the Activity view's 4 s grace period expires
  long before that, so the crossed-out antenna is the normal launch state
  on every device. Fix: mark connected right after Step 1 succeeds, leave
  Step 4 unchanged. Small, no device step beyond watching the icon on one
  launch. DECIDED 2026-10-12: pulled into Train 1 (visible on every launch
  for every user). Built 2026-10-12: `refreshServer()` now returns its
  outcome (the old `error != nil` check also misread a stale error from an
  earlier refresh as a Step 1 failure), Step 1 success calls
  `updateConnectionStatus(connected: true)`. Adversarial pass 2026-10-12:
  the early write is sound (single dedup'd `performRefresh`, in-memory
  observable store, all readers live); it refuted the rationale first
  written here for keeping the disconnected side at Step 4 — see the next
  item — and noted that a Step 1 slower than the 4 s grace still shows the
  icon until the server answers, which is the correct reading. No unit
  test: pinning "flag is true before Step 3 ends" needs a mid-refresh
  WalletManager harness that does not exist. Device check owed: one
  launch, icon must not appear.

## 2. The app can never show "disconnected" once the wallet is open (CONFIRMED)

- [ ] **The app can never show "disconnected" once the wallet is open**
  (CONFIRMED by the 2026-10-12 adversarial pass, pre-existing): Step 2's
  `sync()` returns `()` in bark 0.7.1 (`bark/src/lib.rs:1980`, every
  sub-sync is `if let Err … warn!`) and the FFI wrapper returns `Ok(())`
  unconditionally, so the Swift `sync()` can only throw
  `walletNotInitialized`, which `performRefresh` already guards. Hence
  `anyServerCallSucceeded` is true for every refresh that reaches Step 2,
  Step 4 always writes connected / excellent / `lastError = nil`, and with
  the server down the Activity icon hides, the Connection Info sheet says
  "Connected", its red error row is unreachable, `isArkServerReachable`
  stays true so Lightning routing stays enabled, and
  `hasEverSyncedSuccessfully` flips on the same flag. Fix shape: Step 2
  must not count as a server success (only Step 1's handshake does), and
  Step 4 then writes the disconnected verdict with Step 1's error — which
  makes a transient Step 1 failure visible until the next refresh, so
  decide the retry cadence with it. Belongs to the offline / server-down
  feature below; build it first, the rest of that feature assumes the
  signal works.

## 3. The feature: offline, server down, connecting

- [ ] **Offline / server-down experience** (one feature, merged from eight
  Reminders items: "stunningly designed no-connection state", server-down
  and no-internet messages with disabled functionality, server-offline tip to
  withdraw funds, disable send when offline, animate the connection icon
  while connecting, track and surface the disconnect reason, and a Settings
  disconnect button?). Corrected 2026-10-09: the last service error *is*
  shown, as a red row in the Connection Info sheet while disconnected
  (`ConnectionInfoSheet.swift:178-182`, fed via
  `refreshProcessStates(isConnected:)` → `markDisconnected(error:)`), but
  nowhere inline, not in read-only mode, and it is the generic last
  refresh-service error, not a classified reason (offline vs server down).
  Design the states (offline vs server down vs connecting), decide what each
  disables (boarding while the server is unreachable belongs on the list —
  Tier 0 "Failed boards"), classify the reason, build. **In scope since the
  2026-10-10 ruling on operator dependence:** the server-down state must
  leave unilateral exit reachable while Second's chain source is down too —
  pick a fallback Esplora per network (a third-party trust call), decide
  automatic fallback vs. a recipe, and whether an Esplora setting appears in
  Settings; exercise the exit path once against an unreachable server
  before shipping. Related dead code: connection quality is binary in
  practice (Tier 4).
