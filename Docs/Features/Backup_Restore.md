# Backup Restore

**Status:** OPEN (Tier 0, not scheduled). Created 2026-11-10 to hold the evidence
for the iCloud Drive `db.sqlite` backup items; the open entries in
`Open_Follow_Ups.md` point here. Related open entries that stay short in the
backlog: "Savings funds invisible after a launch-time iCloud restore" (Tier 1
Data safety) and the Tier 2 "Backup import rolled back for a server mismatch".

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Newest-wins restore with no wallet binding

- [ ] **Backup restore is newest-wins with no wallet binding**: one
  `Backups/db.sqlite` slot per iCloud account, written by plain file copy;
  on launch `restoreWalletIfNeeded` (`WalletManager.swift:1339-1360`, primary
  only) replaces the local database when the backup's modification date is
  later. Nothing ties a backup to a wallet hash or a sequence number, so a
  device can start from an older or foreign VTXO database (local-only state
  is what unilateral exit depends on). Fix: bind each backup to the wallet
  hash and a monotonic counter and refuse mismatches; binding also
  neutralises the leftover-backup restore above. Possible field case
  (2026-10-10): Second's hypothesis for the mainnet divergence incident
  below is a restore from backup or a reinstall + iCloud restore, which a
  newest-wins restore of an older `db.sqlite` would produce (the wallet
  forgets a round it already took part in). Unconfirmed — our two log
  exports show "Local wallet file is up to date" and earlier sessions are
  unseen; the user has been asked. If confirmed, this becomes the
  field-evidenced root cause and moves into Train 1. Journal question closed
  2026-10-09: bark 0.7.1 sets no `PRAGMA journal_mode` in
  `SqliteClient::open`, so SQLite's default rollback journal applies and
  there are no `-wal`/`-shm` side files; the remaining copy risk is a backup
  taken mid-transaction, which stopping the daemon first mitigates.
  Addendum 2026-11-12: the delete flow's export step
  (`Features/Wallet_Deletion_Export_Step.md`) copies the live file the same
  way while the daemon may be running, as the background hook does; only
  the shutdown backup stops the daemon first. A `PRAGMA quick_check` on the
  copy before the row shows "Saved" would make the tick honest; noted, not
  built (review F6).
