# Wallet State Divergence

**Status:** OPEN (Tier 0). Mainnet field incident, build 24, logs read
2026-10-07 and 2026-10-09, reframed 2026-10-10 after Second's answer. The four
app-side defects closed 2026-10-11/12 (write-ups in the Done log); what remains
is the remedy, which waits on the bindings bump, two owed answers and one
field-log check. Guiding doc for the refresh side:
`Refresh_Deduplication.md` §9–§10.

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. The incident and what is still open

- [ ] **Wallet state diverged from the server, and the app can neither see
  it nor say so** (field incident, mainnet, build 24, logs read 2026-10-07
  and 2026-10-09; wallet id and VTXO ids in the support thread; reframed
  2026-10-10 after Second's answer). Second found a *successful* refresh of
  the user's three VTXOs server-side — no funds lost — but the wallet missed
  the mailbox message that settles the forfeit, so it still holds the
  pre-refresh VTXOs (now spent in that round) and cannot auto-resolve. From
  the app's side: bark's selection logs them `is expired, must be
  refreshed`, every launch's auto-check and every "Refresh now" tap write a
  Pending refresh movement, the server rejects it as `unusable_inputs`, the
  movement flips to Failed, and the balance keeps showing 19,995 sats the
  user cannot spend. Root-cause candidates, both open: Second asks whether
  the user restored from a backup or reinstalled and restored from iCloud
  (see "Backup restore is newest-wins" above — our two log exports show
  "Local wallet file is up to date", earlier sessions unseen); and upstream
  server commit `dfd425d4a` (2026-09-18, after `server-0.7.1`) fixes mailbox
  checkpoint paging where a page boundary inside a batch "skipped the
  remaining rows for good", in both mailboxes — a lost message with no user
  action. Remedy per Second: recovery from seed, once bark's recovery-path
  fixes ship; for Arké that is the bindings bump (Tier 4 "Next bump"),
  since our 0.7.1 bindings predate every one of those fixes, so the user
  should hold the recovery until then. Four app defects, one cluster:

## 2. Owed and related

Owed to the user (Christoph, support thread): the two restore questions,
"funds confirmed safe on the server", "hold the recovery until the next
Arké build". Owed to Second: was `dfd425d4a` deployed before this user's
refresh round, and was the successful refresh a delegated one? None of the
four fixes waits on the expiry safety-net DECIDE, which this incident no
longer evidences. Related Tier 3 lines, different trigger: "Hide failed
and completed refreshes that were free?" and "Surface expiry sweeps"
(upstream-blocked).

## 3. The four app defects (closed)

Closed 2026-10-11/12; their write-ups, residuals and owed device checks are in `Open_Follow_Ups_Done.md` → "Moved from the open list 2026-11-10". Residuals recorded there and still open: bark's daemon joins every round's first attempt for maintenance refresh with the same dead VTXOs (bindings bump's to fix; confirm in the next field log); a `NotFound` rejection still retries as an ordinary error (Tier 4 typed-errors item); device check owed on the mainnet user's next export (FFI line with server text and ids, "holding them back for 24h", one Failed row per day, the refused card row and a tap landing on the refused screen).
