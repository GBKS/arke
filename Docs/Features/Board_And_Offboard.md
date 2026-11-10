# Board and Offboard

**Status:** OPEN. Created 2026-11-10 to hold the evidence behind the boarding and
offboarding entries: the Tier 0 "failed boards" verification owed on bark 0.8.0
and the missing client-side maximum, plus the Tier 3 modal polish list (whose
closed half is in the Done log, "Moved from the open list 2026-11-10").

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Failed boards on bark 0.7.1 and the missing maximum

- [ ] **Failed boards leave onchain coins stranded on bark 0.7.1** — upstream
  fix `f85ca92ac` ships in bark 0.8.0 (bindings v0.26.0, built 2026-10-25),
  so this becomes a Tier 2 verification once build 26 is on a phone: a
  board refused after signing leaves the onchain wallet untouched (surfaced
  by the 2026-10-05 Second server incident: an attacker registered boards
  with only his own signatures via `BoardBuilder::new_from_vtxo`, a lib
  function only the server's register-board handler calls, so our client
  never ran the vulnerable code and user VTXOs stayed on pre-signed exit
  paths; Second lost ~0.75 BTC of its own funds). The client-side fallout is
  upstream `f85ca92ac` (2026-10-07, after our bark 0.7.1): the board flow
  stored the signed funding tx in the onchain wallet *before* the server
  cosigned, so a board refused after signing (cosign refused, below the
  minimum, network error) leaves no movement or checkpoint, the coins read
  as spent, and every sync rebroadcasts a funding tx no VTXO tracks — a
  2-of-2 output with no cosigned exit. **Derived** from the commit message,
  not reproduced. The server now also rejects register-board above
  `max_vtxo_amount` (`8fab49706`), and `BoardingModalView.swift:32` caps the
  form only by `minBoardAmount` although `ArkInfo.maxVtxoAmount` is parsed
  (`BarkWalletFFI+Configuration.swift:192`; `BoardingModalFormView` has no
  maximum parameter while `OffboardingModalFormView` does), so a user can
  trigger exactly that refusal. Now: pass the maximum into the boarding form
  and refuse client-side; disable boarding while the server is unreachable
  (also on the Tier 1 offline feature's disable list). Real fix: the
  bindings bump that carries `f85ca92ac` (Tier 4 "Bindings adoption"). Both
  upstream commits are only on `origin/master`; the local `~/workspace/bark`
  checkout is at `8adc8e7` (2026-09-30), so `git fetch` before quoting more.
