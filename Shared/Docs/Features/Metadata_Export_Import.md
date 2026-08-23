# Metadata Export & Import

**Status:** Decided (2026-08-23) — scope and policies approved by Christoph (see Decisions). Implementation not started.
**Problem:** Everything the user *adds on top of* the wallet — contacts, transaction
notes, tags, the personal profile — lives only in SwiftData synced through the
CloudKit private database. There is no user-controlled copy: the manual backup
file (`db.sqlite`) is bark's wallet state and contains none of it, and CloudKit
is invisible, unexportable, and tied to one iCloud account. A user who switches
iCloud accounts, hits a CloudKit sync bug, or simply wants a file they own has
no way to take their metadata with them. This feature adds file-based export
and import to the settings backup section.

## Scope

**In — the four user-added metadata families:**

| Family | Persistent models | What travels |
| --- | --- | --- |
| Personal profile | `UserProfile` | name, avatar, timestamps |
| Contacts | `PersistentContact` + `PersistentContactAddress` | name, notes, avatar, contact type, addresses (address, format, label, isPrimary, network), timestamps |
| Tags | `PersistentTag` | name, colorHex, emoji, createdDate, isSystemTag |
| Transaction annotations | `PersistentTransaction.notes`, `TransactionTagAssignment`, `TransactionContactAssignment` | keyed by `txid`: the note text plus tag/contact assignment references with assignedDate |

Transaction annotations are included because they are exactly as user-authored
as contact notes — losing them loses the "what was this payment" layer. They
export as references (`txid` → note / tag IDs / contact IDs), not as
transactions; the transactions themselves belong to the wallet db.

**Out (system/derived/secret):** seed and wallet database, balances,
`PersistentAddress` history, `DeviceRegistration`, `BackupStatus`,
`PersistentExitCache`, `WalletConfiguration`, and `PendingPaymentMetadata`
(ephemeral by design — unmatched entries are deleted after 24h; anything
matched has already landed on a transaction).

## File format

One JSON file, versioned envelope, `arke-metadata-YYYY-MM-DD-HHmm.json`:

```json
{
  "format": "arke-metadata",
  "version": 1,
  "exportedAt": "2026-08-23T14:30:00Z",
  "appVersion": "…",
  "network": "signet",
  "profile": { "name": "…", "avatarData": "<base64>", "updatedAt": "…" },
  "tags": [ { "id": "UUID", "name": "…", "colorHex": "…", "emoji": "…", "createdDate": "…", "isSystemTag": false } ],
  "contacts": [ { "id": "UUID", "name": "…", "notes": "…", "avatarData": "…", "contactType": "standard", "createdAt": "…", "updatedAt": "…",
                  "addresses": [ { "id": "UUID", "address": "…", "format": "ark", "label": "…", "isPrimary": true, "network": "signet" } ] } ],
  "transactionAnnotations": [ { "txid": "…", "notes": "…",
                                "tagAssignments": [ { "tagId": "UUID", "assignedDate": "…" } ],
                                "contactAssignments": [ { "contactId": "UUID", "assignedDate": "…" } ] } ]
}
```

Design points:

- **Dedicated export DTOs** (`ExportedContact`, `ExportedTag`, …), not the
  ArkéUI presentation models. `ContactModel`/`TagModel` are Codable but carry
  computed UI stats (transactionCount, sentAmount) and follow UI needs; the
  file format must stay stable independently. Same decoupling
  `WalletManager+Export.swift` already uses (`WalletExportData`).
- Same encoder settings as the X-Ray export: ISO8601 dates, pretty-printed,
  sorted keys (`WalletManager+Export.swift:79-83`).
- Avatars inline as base64 `Data` (Codable's default). Keeps it a single file;
  a handful of avatar JPEGs keeps the file well under a few MB.
- `version` gates the decoder; unknown-version files are rejected with a clear
  message. Same versioned-snapshot pattern as `ExitStatusSnapshot` v1→v2.
- Fields like `nativeContactID` / `lastSyncedFromNative` deliberately do NOT
  travel — they are device-local links into the OS contact store.

## Export flow

New `MetadataExportService` in `Shared/Services/` (needs the usual Xcode
membership pass — Shared files are opt-in per target):

1. Gather on the MainActor from the ModelContext: the `UserProfile`, all
   non-system-generated contacts, all tags, and every transaction that has a
   note or at least one tag/contact assignment.
2. Map to DTOs, encode, write to a temp file.
3. Hand off per platform, both already proven in the backup section:
   - iOS: `ShareHelper.share()` (as `BackupStatusSectionView_iOS.swift:57-72`)
   - macOS: `NSSavePanel` (as `ManualBackupView.swift:158-172`)

## Import flow

1. `.fileImporter` accepting `.json` (pattern exists in both
   `ImportWalletView`s).
2. Decode + validate envelope (`format`, `version`). Show a **preview sheet**
   before touching the store: "3 contacts (1 new, 2 updates), 5 tags, 34
   transaction notes — 2 notes reference transactions not in this wallet",
   plus the file's export date and network. Confirm applies; cancel is a no-op.
3. Apply with **upsert-by-identity merge** (proposed policy — see open
   questions):
   - **Match by UUID first.** Same `id` → update; **newer `updatedAt` wins**
     per entity (tags have no `updatedAt`; treat imported as authoritative on
     UUID match).
   - **Fallback identity match** to avoid duplicates when UUIDs differ
     (fresh install, cross-account move): tags by normalized name; contacts by
     any shared normalized address, else exact name match.
   - **Annotations** apply only to transactions present locally (matched by
     `txid`); note fills/overwrites per the same newest-wins rule, assignments
     are additive (the join-table `id` is `{tagId}_{txid}` — natural dedup).
     Unmatched txids are counted and reported, not stored — the txs arrive via
     wallet restore/sync, after which a re-import attaches them.
     (`PendingPaymentMetadata` is NOT a parking spot; its 24h cleanup would
     eat them. A durable deferred-annotations store is possible later if
     re-import feels clunky.)
   - **Profile**: applied only if the local profile is unconfigured, else
     newest-wins like contacts.
   - Import never deletes anything.
4. Everything lands in SwiftData → CloudKit propagates to other devices
   automatically; import once on any device.

Merge decisions live in a pure, context-free helper (à la
`ImportRecoveryLogic`) so policy is unit-testable without SwiftData.

## UI placement (proposed)

Inside the existing Manual Backup hub, which becomes the one place for
"copies of your data":

- **iOS**: third `NavigationLink` in `ManualBackupView_iOS.swift` after
  Recovery Phrase and Backup File — "Contacts & Metadata" → a page with
  Export and Import actions plus a short explanation of what's included.
- **macOS**: third section in `ManualBackupView.swift` (no new
  `SettingsDetailItem` case needed).
- Shared content view with `#if` islands for share-sheet vs save-panel,
  per the prefer-shared-views convention.
- Import stays enabled in read-only mode? No — gate like other mutating
  settings (read-only devices shouldn't write metadata).

## Privacy note

The file is plaintext JSON containing names, avatars, payment addresses, and
note text — but **no keys and no funds**. Decided: v1 ships unencrypted with
no special warning copy. Passphrase encryption stays available as future work
if ever wanted.

## Localization & tests

- All new strings via `defaultValue:`/L10n; run `apply_translations.py` +
  `translation_lint.py` for de/ja/zh-Hant first passes.
- Tests: DTO round-trip (export → import into empty in-memory container →
  field equality), merge-policy table tests on the pure helper (UUID match,
  name/address fallback, newest-wins, additive assignments, unmatched-txid
  reporting), envelope version rejection, and confirming `WalletWipeCoverage`
  is unaffected (no new models in v1 scope).

## Decisions (Christoph, 2026-08-23)

1. **Annotation scope** — transaction notes/assignments keyed by txid ARE
   included in v1.
2. **Conflict policy** — newest-`updatedAt`-wins, as proposed.
3. **Encryption** — plaintext v1, no warning copy.
4. **Placement** — inside Manual Backup.
5. **Auto-export** — no; manual export/import only.

## Phasing

1. **Phase 1 — Export**: DTOs + `MetadataExportService` + both platform UIs.
   Shippable alone; already delivers the "file I own" value.
   **DONE + device-tested 2026-08-23.** Files:
   `Shared/Services/MetadataExportService.swift`,
   `Shared/Views/Settings/MetadataBackupSectionView.swift`, hooks in both
   Manual Backup views. Note: the ArkeMobile target holds Shared files by
   opt-in — new Shared files need the Xcode membership tick (done for these
   two). Finding from testing: one raw native-contact avatar made the file
   1.2MB → avatar-size follow-up proposed in Open_Follow_Ups.md.
2. **Phase 2 — Import**: file picker, envelope validation, preview sheet,
   merge helper + apply.
   **DONE 2026-08-23, on-device verify pending.** Files:
   `Shared/Services/MetadataImportService.swift` (decode with version probe,
   `MetadataImportPolicy` pure merge policy, dry-run preview, apply), import
   UI + preview sheet in `MetadataBackupSectionView.swift`, tests in
   `Tests/Shared/MetadataImportLogicTests.swift` (policy + round-trip +
   merge semantics; mobile suite 234/234 green). One policy refinement made
   during implementation: transaction notes carry no timestamp to arbitrate
   newest-wins with, so an imported note only fills an empty local note —
   local notes are never overwritten.
3. **Phase 3 — QA**: localization pass, mobile test batch, on-device
   round-trip (export on iPhone → import on clean simulator), Open_Follow_Ups
   update.
