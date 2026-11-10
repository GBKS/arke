# Activity Row Dating

**Status:** blocked upstream (Tier 3 Activity). DECIDED 2026-10-19: filed as
`Bark_Bindings_Feedback.md` §1.10 / ask 20; the entry stays open as the
adoption item.

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Trace and ruling

- [ ] **Activity rows are dated by when the wallet processed the movement,
  not when it happened** (Christoph, 2026-10-19; Train 1 cosmetic pass).
  Related, not a fix: bark 0.8.0 (#2610, feedback ask 11) stops finished
  exits from re-stamping `completed_at` on every sync, which removes one
  cause of old cancelled exits floating to the top; the date-freeze
  workaround in the upsert can go once a build-26 export shows no churn.
  Traced: the row date is `parseDate(movement.completedAt ?? movement.createdAt)`
  (`TransactionService+Parsing.swift:320`), and bark's `MovementTimestamp`
  (`bark/src/movement/mod.rs:326-334`) has only `created_at`, `updated_at`,
  `completed_at`, all stamped with the wallet's local clock when *it* acted.
  For a sent payment that is the real time. For anything discovered at a
  sync — a received Ark payment claimed from the mailbox, a board or an
  onchain receive found by the chain scan, a round refresh — it is the
  sync time, which on a phone that was closed for a day is a day late.
  Bark offers no counterparty time, so the fix is per source: (a) onchain
  rows already have the block time (`OnchainTransactionModel.confirmationTime.timestamp`)
  and the movement ↔ onchain link (`Movement_Onchain_Linking.md`) — show
  the block time when linked; (b) received Ark payments that arrive by
  push are processed within seconds (`processSingleMovement`), so they are
  already right; only the catch-up sync case is late, and for it the
  honest display is bark's time — or an "around" prefix / "received by"
  wording, ruling needed; (c) the upsert must not re-date an existing row
  when a later refresh reports a later `completed_at` for the same
  movement (`TransactionUpsertDateFreezeTests` pins the cancelled case
  only; check whether a re-sync bumps dates of settled rows, which would be
  the "when the app loaded it" effect on *every* refresh). Start with (c):
  if settled rows are re-dated on refresh, that is the bug; (a) is the
  improvement; (b) needs a ruling.
  **(c) executed 2026-10-19 — no re-dating.** Read at bark tag 0.7.1 (the
  deployed library): `movement/manager.rs` sets `completed_at` only in
  `new_finished_movement` / `finish_movement*`; `movement/update.rs:217`
  (`MovementUpdate::apply_to`) moves `updated_at` only; `exit/mod.rs:788-797`
  re-finishes an exit movement only on a fresh state change (the §2a bump
  on every tip advance is gone at this tag, the app-side freeze stays as
  belt and braces). The upsert rewrites `date` only when bark's value
  differs, and `updated_at` never feeds it — pinned by
  `settledDateIgnoresUpdatedAt` in `TransactionUpsertDateFreezeTests` (4/4
  green). **(a) is largely moot:** onchain rows already take the block time
  (`UnifiedTransactionService.swift:398-404`), and the movements linked to
  them — boards, offboards, exits — are this wallet's own actions, stamped
  when they happened. **(b) — the real time exists, bark drops it**
  (traced 2026-10-19, Christoph: "is there really no date on when the
  payment actually happened?"). Incoming payments reach the phone through
  the server mailbox (`mailbox_server.proto`: Ark payments, incoming
  Lightning payments, round completions). Every mailbox message carries a
  `checkpoint`, and the server builds it from its clock at deposit time
  (`V21__blinded_mailbox.sql`: upper 44 bits = milliseconds since epoch,
  lower 20 a same-millisecond counter). So the server-side arrival time of
  each received payment is on the wire. The bark client keeps only the
  highest checkpoint as its read cursor (`store_mailbox_checkpoint(u64)`)
  and stamps the movement with the phone's clock when it processes the
  message — that is the "when the app loaded it" date. Nothing in the
  bindings exposes the per-message time, so there is no app-side fix.
  DECIDED 2026-10-19 (Christoph): filed as an upstream ask —
  `Bark_Bindings_Feedback.md` §1.10 / ask 20: stamp mailbox-delivered
  movements with the checkpoint's time (or expose it as a `received_at`
  on the movement). On adoption, the parser uses it as the row date for
  received rows and keeps `completed_at` for everything the wallet did
  itself. Until then the row date is honest about one thing only: when
  this phone learned of the payment. Stays open as the adoption item,
  blocked on upstream.
