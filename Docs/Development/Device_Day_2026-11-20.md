# Device Day 2026-11-20 — bark 0.9.0 bump (bindings v0.28.0)

**Results 2026-11-20 (Christoph, one phone plus the second for §1c):**
every section run and passed, reported in aggregate ("all worked great").
One log export, `~/Downloads/arke-debug-20261120-131320.log`, a mainnet
session 11:57–12:13 UTC on the wallet that failed on 2026-11-19. What it
shows: no "dust threshold" or "upgrade your wallet" line anywhere;
movements grew 439 → 443 during the session; cached tip 976725 and the
newest coin (91,549 sats) expiring at 980734, 4009 blocks out, i.e. the
server's 4032-block lifetime minus the blocks since the board, which
settles §2 on mainnet (the 0.9.0 default would have read about 432); the
37 dust coins are still there, now spendable. Two side findings, neither a
blocker: bark logs "VTXO … is uneconomical to exit, should be refreshed"
at error level once per dust coin per selection (1001 of the export's
1011 error entries), and `BarkWalletFFI` warned "Unknown VTXO kind:
'ServerHtlcRecv', defaulting to pubkey" once; both filed. §3's recovery
line and §4's CPFP link were not in this export (different session,
signet); the pass stands on the report, the log evidence is owed if either
ever misbehaves.

**Status:** CLOSED 2026-11-20. The bump is device-checked; the TestFlight
release is the remaining step (`Migrations/Bark-0.27.0-to-0.28.0/README.md`
Plan step 8).

**Ground rules.** One phone is enough; the signet pair (A primary, B
secondary) only for §2's Ark send if no other Ark address is at hand.
Never type the signet phrase into anything tracked. Log export: Settings ›
X-Ray › export, or Console with subsystem `GBKS.Arke`; device logs redact
private data. Fingerprint the build by `git log -S boardLifetime` on the
installed tree, not the version header. The bark database migrates to
schema 43 on the first open of this build; the previous build will not
reopen it, so do not plan to go back to build 27 on this phone.

## 1. The reason for the bump: small sends on Second's 0.9.0 mainnet server

Mainnet, the wallet that failed on 2026-11-19 (37 of 49 coins at 1–3 sats).

- (a) Pay a Lightning invoice of about 100 sats, the shape that failed
  with "An output is below the dust threshold, upgrade your wallet and
  retry". Expect "Payment Sent" and a Sent row in Activity.
- (b) Pay one of about 400 sats (the second failing shape, dust change on
  a larger send). Expect Sent.
- (c) An Ark (arkoor) send of a small amount to any other Arké mainnet
  wallet (the second phone's mainnet wallet from 2026-11-18 will do).
  Expect Sent.
- Pass: no "upgrade your wallet" text anywhere; nothing pending in
  Activity afterwards. Fail: the same server error means the server's
  checkpoint rule changed again, or the phone is not on this build.
- The 1–3 sat coins stay; 0.9.0 isolates them in the dust tx instead of
  refusing. If a send still fails for a different reason, export the log
  before anything else.

## 2. Board expiry: the `UInt16.max` ruling holds

- (a) Data › Ark info: read the server's VTXO lifetime in blocks and the
  current height.
- (b) Board a small amount. When the board VTXO appears in Data › coins,
  read its expiry height.
- Pass: expiry ≈ tip + the server's lifetime from (a). Fail: expiry ≈ tip
  + 432 on mainnet or tip + 4320 on signet, which would mean bark's new
  default won through.
- Discrimination: on signet the 0.9.0 default is 4320 blocks; if the
  signet server's lifetime is at or below 4320 the two answers coincide
  and the check proves nothing. Then do (b) on mainnet with a minimal
  amount (mainnet default would be 432, unmistakable).

## 3. Seed import with recovery (bark 0.9.0: starts on open, resumes on refresh)

Signet throwaway wallet, on the phone that holds it. Note its balance and
coin count first.

- (a) Settings › delete the wallet, **this device only**. The seed must
  stay on the other device / in iCloud; do not pick the full wipe.
- (b) Import the phrase. Watch the log for one of:
  - `Recovery from seed complete, isComplete=true: recovered N (S sats)…`
    → the old path; the balance should be there after the first refresh.
  - `Recovery from seed in progress, isComplete=false: … failed N …` and
    `Recovery from seed is still in progress after the creating open…`
    → the new path. Pull to refresh twice; expect bark's
    `Error resuming recovery from seed` **absent** and the balance to
    reach the noted figure. Locked coins are no part of the balance until
    the server decides them, so a lower figure after the first refresh is
    expected, after the second it is a finding.
  - `Recovery from seed failed to start (attempt n/3): …` → the wipe-and-
    retry path; it should be followed by a second attempt within seconds.
- (c) Data › coins: count matches the note. Activity: history present.
- Pass: balance and coin count match within two refreshes. Record which
  of the three log lines you saw; "in progress" on a healthy network is
  worth reporting to Second.
- Optional, forces the new path: switch to airplane mode about two
  seconds into (b), then back on, then refresh. Skip if the import screen
  refuses to start offline.

## 4. Exit to confirmation, and the CPFP child link (review F2)

Signet. One small VTXO.

- (a) Data › coins › start a unilateral exit. Watch it move through
  broadcast, confirmation, the delta wait, claimable, claimed.
- Pass for the bump: it never sits in "awaiting CPFP" or "awaiting
  confirmation" after the block that confirms the exit tx (bark 0.9.0
  now counts the exit tx's own confirmation).
- (b) F2 question: open the exit's row in Activity › technical details
  (or Settings › Fees summary) and check whether the CPFP child
  transaction is linked to the exit movement. Linked: the history
  snapshot caught `AwaitingConfirmation`. Not linked: note it on the Tier
  2 Exits entry "CPFP child linking after a fast exit confirmation"; it is
  not a release blocker.

## 5. Regression on the new binary (signet, quick)

Receive Lightning and claim, receive Ark, onchain send from Payments,
offboard, a manual refresh from the coin list, pull-to-refresh on the
balance. Each: completes, correct row in Activity, no new error lines in
the log. Fifteen minutes.

## 6. Lightning send failure and retry (MR 2664, optional)

- (a) Pay an invoice that cannot succeed (expired, or to a node that is
  offline). Expect "Payment Failed", nothing pending.
- (b) Pay a fresh invoice to the same destination. bark 0.9.0 gives the
  retry its own movement: expect two rows in Activity, not one row that
  changes state.

## 7. Relaunch

Kill and relaunch twice. Wallet opens, balance present, no `migration` or
`database` error lines. The second launch is the one that proves the
schema-43 database reopens.

## Release notes to carry

- Update required to send small amounts against Second's upgraded server.
- Once this build has opened the wallet, the previous build cannot reopen
  it (database migration); do not downgrade.
- Users still on the old build who need to send a small amount today:
  Data › coins › "Refresh all" first, then send.
