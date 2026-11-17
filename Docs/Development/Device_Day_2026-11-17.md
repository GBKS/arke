# Device Day 2026-11-17 — device linking, deletion, import

**Results 2026-11-17 (Christoph, two phones):** §1, §2, §3 (all four
runs, including the hand-back Activity list), §4 with the folded-in Remove
check, §7 and §9 all passed, reported in aggregate ("everything worked out
well"). §8 run later the same day on the fix 2 working tree (restore
mode screen, wrong phrase refused, right phrase reopened the existing
database with its history): passed, "everything worked great". §5
deferred by ruling. §10 not runnable. The idle-primary handover passing settles H3 on device: the
mtime-only slot stamp did propagate. The Activity list after hand-back
being populated means H1's visible symptom did not reproduce; the code
asymmetry stands (see `Features/Device_Linking.md` §17.2).

**Status:** DRAFT 2026-11-17. Review has not closed: fixes 2–4 of the
range review (`Features/Device_Linking.md` §17: I1 restore exit, H1 service
rebuild, I2 import backup order) are not built. Sections marked **wait**
exercise code those fixes change; run them after. Everything else can run
on the current working tree (fix 1 included). Tick a section when run and
paste the exported log path under it.

**Ground rules for the day.** Two phones on signet, A primary, B secondary,
both on the same build. Never create a wallet on the shared Apple ID: a
create replaces the account's wallet hash and the synchronizable seed for
every device (2026-11-16). Never type the signet phrase into anything
tracked. Log export: Settings › X-Ray › export, or Console with the
`GBKS.Arke` subsystem; device logs redact private data. Sections are
ordered so the non-destructive ones come first; the destructive group at
the end needs the reset recipe in §R.

## 1. Mirror-only window (step 3, §13.2 re-run)

- (a) A primary, B linked. Both on the current build.
- (b) Delete the app on B, reinstall, launch, link. On A open Settings ›
  Devices within the first minute, leave and re-enter if empty (the list
  re-reads on appear only, filed). Then open A's Delete wallet screen.
  Then unlink B from A's Devices list.
- (c) Pass: A's list shows B's name, platform and role before B's CloudKit
  row has imported (no sync-state text on the row). A's delete screen
  names B as a blocker. After the unlink B lands on its link screen
  (B log: `Own registration row is gone`), and A's list after re-entering
  shows no B. Relink B afterwards.
- (d) Fail: export both logs; note the time between B's link tap and B
  appearing on A.

## 2. Delete flow, blocked (step 5, §15.5 item 1)

- (a) A primary, B linked.
- (b) On A: Settings › Delete wallet. B appears as a row with "I no longer
  have this device". Tap, confirm. Watch B. Back on A, watch the screen
  re-assess. **Do not slide.** Back out, relink B.
- (c) Pass: B goes to its link screen. A's screen changes to the
  last-device steps (backup file, two words, slider). B's log:
  `Own registration row is gone`; A's log: no backup line.
- (d) Fail: both logs, screenshot of A's delete screen.

## 3. Handover paths not yet recorded (step 4, §14.3)

Four runs, all two-phone, A primary, B secondary at the start of each.

### 3.1 Idle-primary handover (settles H3 too)

- (b) Leave A idle for at least an hour, no payment. On B: Devices › Make
  Device Primary › "Do you still have A?" › Yes. On A: Make Device
  Secondary › confirm.
- (c) Pass: A shows "Closing the wallet…", "Uploading the final backup…",
  "Now continue on your other device" with log `Backup slot wait` lines
  and no timeout; B moves through "Waiting for A to hand over…",
  "Handover started…", "Waiting for the latest backup…", "Latest backup
  received." and the button enables inside the 240 s window. B opens as
  primary. **H3 fails** if B times out and offers "I Don't Have It
  Anymore" while A reported done: the slot's mtime-only stamp did not
  propagate. Export both logs either way; this settles an assumed fact.
- Hand back B → A afterwards and check on A that the **Activity list**
  is populated, not only X-Ray. Expected to fail until fix 3 (H1); record
  the result, it confirms the finding on device.

### 3.2 Timeout path

- (b) On B start the handover; do nothing on A for four minutes.
- (c) Pass: "I Don't Have It Anymore" appears on B at about 240 s. Cancel.

### 3.3 Takeover

- (b) Send a small signet payment on A first. Start on B, choose "No, I
  Lost It". Read the warning. Take Over. Then relaunch A.
- (c) Pass: the warning names A and the backup date. B opens as primary;
  B log `Takeover reconcile over N VTXO(s): … no longer spendable, …
  undecided`. A on relaunch lands on the link screen (A log:
  `Wallet access blocked` or `Own registration row is gone`), never
  spends. Relink A as secondary, then hand primary back to A with the
  guided flow if you want A primary again.
- Avoid having a round in flight on A at the moment of takeover (H4): if
  you want to settle H4 instead, do the opposite deliberately and check
  whether the in-flight VTXO is still spendable on B after the round.

### 3.4 Direct promotion

- (b) Demote A (Make Device Secondary) with B not yet promoting. Then on B
  open Make Device Primary.
- (c) Pass: B skips the "Do you still have A?" question and shows the
  direct confirmation. Promote. B primary.

## 4. Fix 1 on device: record for another wallet never heals or opens

- (a) A primary, B linked. **Destructive, see §R first**; run it last in
  the day together with §8.
- (b) Put B in airplane mode. On A: full wipe (B's row shows as a blocker;
  use "I no longer have this device" on B's row, then slide). Create a
  new wallet on A (this is the one permitted create, inside the
  destructive group). Bring B online and launch.
- (c) Pass: B never opens bark. B shows the launch-check screen (today's
  copy says "different iCloud account", filed). B log:
  `Account wallet awaiting link on this install (walletMismatch(differentAccount))`
  and no `Wallet opened successfully`. Then the **Remove from this
  device** check (was §6): tap Remove on B → the slider sheet → onboarding
  (the account's wallet is the new one A created, so B is offered the link
  screen or onboarding; either is right). B's log must show no backup
  written during the removal: no `Backup` line after
  `Closing wallet for migration`. Then §R.
- The retained-row variant (G1 b) needs a forced unregister failure and
  has no device recipe; it stays owed to a debug hook.

## 5. Signed out and different account — **DEFERRED (DECIDED 2026-11-17)**

Not part of this device day. Run once, on B only, before the first
TestFlight build that ships the launch-check screen; one session covers
both cases because signing out is step one of switching accounts. What it
buys is boundary facts no code read can give: how fast CloudKit reports
`noAccount`, whether the synchronizable seed and the CloudKit local store
leave the device on sign-out or switch (ASSUMED today, 2026-11-17), and
the order of `CKAccountChanged`, the KVS account-change notification and
`Own registration row is gone` (G4). Every launch-check case opens
nothing and registers nothing, so skipping it risks a wrong screen on a
rare path, not a wrong wallet open. Once observed, record the facts in
`Features/Device_Linking.md` §15.1 as verified; no re-run unless the
launch-check code changes.

- (b) On B sign out of iCloud (keep data when asked). Launch Arké. Sign
  back in. Return to Arké without tapping anything. Then the same with a
  second Apple ID if one is available.
- (c) Pass: "You are signed out of iCloud"; after signing back in the
  screen re-checks on return to the foreground and the wallet comes back
  without a tap. Another Apple ID: the different-account title; Check
  Again after signing back in returns to the wallet. Export B's log even
  on a pass.

## 6. Remove from this device — folded into §4

The Remove exit is the same `LaunchCheckView` whichever case shows it;
§4 reaches it without a sign-out and checks it there.

## 7. iCloud Keychain off, seed-only entry (step 2, Tier 2)

- (a) B: Settings › iCloud › Passwords & Keychain off. Delete and reinstall
  Arké on B.
- (b) Launch: link screen with the key-missing line. Tap Enter Recovery
  Phrase, type the signet phrase, save.
- (c) Pass: the save succeeds after the account-hash check, B stays
  secondary (read-only wallet), B log has **no** bark import line. Turn
  Keychain back on afterwards.

## 8. Deleted elsewhere, then restore (step 5, §15.5 item 4) — fix 2 built 2026-11-17, **PASSED 2026-11-17**

- (a) A must have launched linked once on this build (identity token).
  Destructive: §R after. Both phones on a build that includes fix 2.
- (b) Unlink A from B. Full wipe on B. Launch A. On the launch-check
  screen tap Restore with Recovery Phrase. The phrase screen must show
  "This device still holds the wallet's data…" and a **Restore Wallet**
  button; there is no backup-file step on this path. First type a wrong
  phrase (any valid 12 words that are not the wallet's), then the right
  one.
- (c) Pass: the wrong phrase is refused with "This is not the recovery
  phrase of the wallet on this device" and A's log shows
  `Import refused: the phrase is not the one of the wallet still on this device`
  with no `Wallet opened` line. The right phrase opens the existing
  database: the Activity history is still there, A's log has
  `Existing wallet restored from the recovery phrase`. Then §R. Export A's
  log either way; it also shows whether the stale-parked-file line or any
  backup line appears during the restore.
- (d) Fail: A's log, screenshots of the restore screen and the result.

## 9. Deletion export step, two-device half (`Wallet_Deletion_Export_Step.md` §8)

- 9.1 Override route from a secondary: on B, Settings › Delete wallet, take
  the override path. Pass: the export step appears before the phrase
  check. Back out.
- 9.2 Demoted device exports the slot copy: demote A, make B primary
  (guided flow), send a payment on B so B writes a newer backup, then on A
  start Delete wallet and Download the wallet backup file. Pass: the
  exported file's modification date is after the demotion (Files app
  info), i.e. the slot's copy, not A's frozen local one. Back out, hand
  primary back.

## 10. Not runnable with two phones

- H2, two secondaries promoting at once, needs three devices.
- D2, per-blocker unlink of a live backgrounded primary refilling the
  slot: wait for the restore-path fix (ruling 2026-11-16), then it is a
  two-phone run: background B (primary, open); on A unlink B from the
  delete screen, full wipe, create; foreground B; cold-relaunch A; grep A
  for `Backup is newer than local file`.

## 11. Service rewiring after promotion (fix 3, §17.2 H1) — built 2026-11-17, **PASSED 2026-11-17** (reported in aggregate, "seems all to be working well")

- (a) A primary, B secondary, both on a build with fix 3. Signet wallet
  with at least one spendable VTXO.
- (b) Hand over A → B, then hand back B → A, in one session on A (no
  relaunch). On A open the balance card's refresh modal and start a VTXO
  refresh.
- (c) Pass: A's log has `Model context re-applied to rebuilt wallet
  services` right after the hand-back, and while the refresh is pending
  the balance card's refresh status shows it as in progress (that status
  reads `hasActiveRefresh`, which is empty without the fix). No second
  refresh is scheduled for the same VTXOs (X-Ray › Background Activity or
  the log's `VTXORefreshService` lines).
- (d) Fail: A's log, screenshot of the balance card during the refresh.

## R. Reset to the shared signet wallet

After §4 or §8: full wipe of whatever wallet is on the account from the
last linked device, import the signet phrase on A (phrase step, then Skip
on the backup-file step unless you saved a file you trust), link B from
its link screen. Check A's Activity shows the signet history and B shows
the same read-only. If the new wallet's history appears on the restored
one, the leftover-rows item (Tier 1 Data safety) is confirmed from the
other direction; export A's log.
