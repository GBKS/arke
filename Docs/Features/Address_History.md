# Address History

**Status:** Shipped 2026-01-14 (`4ba4228`, per `git log` on `Shared/Services/PersistentAddress.swift`); transaction linking landed 2026-04-20. Rewritten 2026-09-27 from the implementation plan; phase docs in `../Archive/Implementations/Address history/`.

Address history is an internal subsystem. It records every Ark and onchain address the app reveals from bark, reuses them according to a per-type policy, caps the number of unused onchain addresses, links transactions to the addresses they touch, and lets the activity list recognise sends to the wallet's own addresses as internal transfers. The only user-facing surface is the Address History screen in Settings.

## Files

| Concern | File |
|---|---|
| Model | `Shared/Services/PersistentAddress.swift` |
| Enums | `Shared/Services/AddressType.swift`, `Shared/Services/AddressGenerationStrategy.swift`, `Shared/Services/AddressErrors.swift` |
| Primary-device service | `Shared/Services/AddressService.swift` |
| Secondary-device service | `Shared/Services/ReadOnlyAddressService.swift` |
| Wiring | `Shared/Data/WalletManager/WalletManager.swift` (`setModelContext`, `arkAddress`/`onchainAddress`), `Shared/Data/WalletManager/WalletManager+Refresh.swift` |
| Transaction linking | `Shared/Services/TransactionService/TransactionService+AddressLinking.swift`, `Shared/Services/TransactionService/TransactionService+Upsert.swift` |
| Internal-transfer display | `Shared/Models/PersistentTransaction.swift` (`isInternalTransfer`, `effectiveType`) |
| UI | `Shared/Views/Settings/AddressHistoryView.swift` |
| Schema / wipe | `Shared/Data/SwiftDataHelper.swift`, `Shared/Views/Settings/WalletDataCleanupService.swift` |
| Tests | `Tests/Shared/ReadOnlySyncedDataTests.swift` (read-only path only) |

## Data model

### `PersistentAddress` (`@Model`)

All stored properties have defaults and the relationship is optional, as CloudKit requires.

| Field | Type | Meaning |
|---|---|---|
| `id` | `UUID` | Row identity. |
| `address` | `String` | The Ark or Bitcoin address string. |
| `addressType` | `String` | `"ark"` or `"onchain"`; typed accessor `type: AddressType`. |
| `generatedAt` | `Date` | When the row was created. |
| `derivationIndex` | `Int?` | App-side counter for onchain addresses (see "Derivation index" below); `nil` for Ark. |
| `generatedBy` | `String` | `AddressGenerationStrategy` raw value; typed accessor `strategy`. |
| `isUsed` | `Bool` | Set by `markAddressAsUsed`. |
| `firstUsedAt`, `lastUsedAt` | `Date?` | Stamped by `markAddressAsUsed`. |
| `receivedTransactionCount` | `Int` | Incremented per `markAddressAsUsed` call. |
| `totalReceivedSats` | `Int` | Sum of `transaction.amount` passed to `markAddressAsUsed`; `totalReceivedFormatted` renders it. |
| `isActive` | `Bool` | Every query filters on it. Nothing in the app ever sets it to `false`; rows are hard-deleted instead (see "Wallet deletion"). |
| `receivedTransactions` | `[PersistentTransaction]?` | `@Relationship(deleteRule: .nullify, inverse: \PersistentTransaction.receivingAddress)`. |

`hasBeenUsed` is an alias of `isUsed`.

### `AddressType`

`enum AddressType: String, Codable, CaseIterable` with `.ark` and `.onchain`. `displayName` is localized ("Ark Address" / "Bitcoin Address"); `canReuse` is `true` for Ark and `false` for onchain. `canReuse` is descriptive only; the reuse policy itself is hard-coded in `AddressService.getCurrentReceiveAddress`.

### `AddressGenerationStrategy`

`enum AddressGenerationStrategy: String, Codable` with `.auto` (`"auto"`), `.userRequested` (`"user_request"`) and `.discovered` (`"discovered"`). Only `.auto` and `.userRequested` are ever written; `.discovered` exists in the enum but no code path assigns it (address discovery on sync is not implemented, see "Not implemented").

### `AddressError`

`enum AddressError: LocalizedError`: `.gapLimitExceeded(unusedCount:)`, `.invalidAddressType`, `.addressNotFound(String)`, `.duplicateAddress(String)`. Only `gapLimitExceeded` and `duplicateAddress` are thrown by `AddressService`; the other two exist for the UI's exhaustive switch.

## AddressService

`@MainActor @Observable class AddressService`, created by `WalletManager.setModelContext` once a wallet and a `ModelContext` exist (primary mode only), and handed to `TransactionService.setAddressService`. It holds `wallet: BarkWalletProtocol`, a `TaskDeduplicationManager`, the `ModelContext`, and the constant `maxUnusedOnchainAddresses = 20`.

Observable state consumed by the receive screens through `WalletManager.arkAddress` / `WalletManager.onchainAddress`:

- `arkAddress: String`, `onchainAddress: String` — cached copies of the current receive addresses.
- `error: String?`

Public methods:

```swift
func loadAddresses() async                      // deduplicated under key "addresses"
func refreshAddresses() async                   // = loadAddresses()
func clearAddresses()                           // clears the two cached strings + error

func getCurrentReceiveAddress(type: AddressType) async throws -> PersistentAddress
func generateNewAddress(type: AddressType, strategy: AddressGenerationStrategy = .userRequested) async throws -> PersistentAddress

func markAddressAsUsed(address: String, transaction: PersistentTransaction?) async
func isOwnAddress(_ address: String) async -> Bool
func getAllAddresses(type: AddressType? = nil) async -> [PersistentAddress]
func getUnusedAddressCount(type: AddressType) async -> Int
func validateGapLimit() async throws
func getAddressByString(_ address: String) async -> PersistentAddress?
```

`WalletManager+Refresh.swift` forwards `loadAddresses()` and `generateNewAddress(type:strategy:)`; the latter throws `BarkErrorArke.commandFailed` when no `AddressService` exists (read-only mode).

Plan said there would be a separate `AddressPolicyEngine` struct; shipped as inline logic in `getCurrentReceiveAddress` and `generateNewAddress`.

### `loadAddresses()` and refresh ordering

`performLoadAddresses()` calls `getCurrentReceiveAddress` for `.ark` then `.onchain`, copies the results into the cached strings, and records the first failure in `error` (cleared when both succeed). `WalletManager.refresh` awaits `loadAddresses()` *before* the parallel balance/transaction group: on a fresh import this reveals onchain index 0, and bark's revealed-SPK sync scans nothing until at least one address is revealed (`Docs/Open_Follow_Ups.md`, "Phase 1 defect — first render after fresh import").

## Address generation flow

### Ark

`getCurrentReceiveAddress(type: .ark)` returns the most recent active Ark row regardless of `isUsed`. Only when no Ark row exists does it call `generateNewAddress(type: .ark, strategy: .auto)`. A new Ark address is otherwise created only by an explicit `.userRequested` call from the Address History screen. There is no gap-limit check for Ark.

### Onchain

`getCurrentReceiveAddress(type: .onchain)` returns the most recent active *unused* onchain row. If none exists it counts unused onchain rows and throws `AddressError.gapLimitExceeded` if the count is `>= 20`, otherwise calls `generateNewAddress(type: .onchain, strategy: .auto)`. In practice the count is always 0 on that branch (no unused row was found), so the auto path never trips the limit; the check bites on user-requested generation.

### `generateNewAddress`

1. For `.onchain` with `.userRequested`, throw `gapLimitExceeded` if unused onchain rows `>= 20`.
2. Call `wallet.getArkAddress()` or `wallet.getOnchainAddress()` (bark `reveal_next_address`).
3. For onchain, compute `derivationIndex` = highest existing active onchain `derivationIndex` + 1, or 0.
4. Throw `duplicateAddress` if an active row with the same string exists (after the wallet call, so the bark-side index is still consumed).
5. Insert, `save()`, refresh the cached strings.

### Derivation index

`derivationIndex` is an app-side counter, not read from bark. It stays aligned with bark's revealed index only while every `getOnchainAddress()` call goes through `AddressService`. `ExitClaimSequence` reveals claim addresses directly and bypasses history, so the two can drift — tracked in `Docs/Open_Follow_Ups.md`, "Claimed exit funds invisible after seed import".

## Transaction integration

### `PersistentTransaction.receivingAddress`

`@Relationship(deleteRule: .nullify) var receivingAddress: PersistentAddress?` — the inverse of `PersistentAddress.receivedTransactions`. Despite the name it is set on both received and sent transactions (see below). `WalletDataCleanupService` reads it once as a diagnostic touch.

### `linkTransactionToAddress` (`TransactionService+AddressLinking.swift`)

Called from `TransactionService+Upsert.swift` for every *newly inserted* transaction only; existing rows are not re-linked. It is a no-op until `addressService` is wired. Given `transaction.address`:

- `type == "received"`: `markAddressAsUsed(address:transaction:)`, then set `receivingAddress`. `PersistentTransaction.address` is populated from `destination?.address` of the movement's first destination, and the model documents it as "recipient address for sends, nil for receives" — so this branch depends on bark supplying a destination for receives.
- `type == "sent"` and `isOwnAddress(address)`: set `receivingAddress`; if the category is not `.onchainSend`, also set `subsystemCategory = "internal_transfer"`; then `autoTagInternalTransfer` (assigns the "Balance" system tag, `TransactionService+AutoTagging.swift`). Onchain sends keep their category and are recognised via the link alone.
- Any category in `.refresh`, `.boarding`, `.exit`, `.offboarding` (with or without an address): set `subsystemCategory = "internal_transfer"`, link the address if it is in history, auto-tag.

### Internal-transfer detection (`PersistentTransaction`)

```swift
var isInternalTransfer: Bool   // category in {boarding, offboarding, refresh, exit} → true
                               // category == .onchainSend → receivingAddress != nil
                               // else type == "sent" && receivingAddress != nil
var effectiveType: String      // "internal_transfer" when isInternalTransfer, else type
```

`effectiveTypeDisplayName` / `effectiveTypeIcon` derive from `effectiveType` (English literals, not localized). `isInternalTransfer` drives `TransactionIconView`, `TransactionListItem`, `TransactionSwipeCard`, `TransactionDetailView_iOS`, `TransactionTagView`, `TransactionContactView`, `FeeSummaryViewModel`, and amount formatting in `TransactionModel+Persistence.swift`.

## Settings: Address History screen

`AddressHistoryView` (Shared, reached from `SettingsView_iOS` via `NavigationLink` and from the desktop `SettingsView` via `SettingsDetailItem.addressHistory`) uses `@Query(filter: isActive, sort: generatedAt desc)` and splits rows client-side into "Payments Addresses (Ark)" and "Savings Addresses (Bitcoin)" sections; a section is hidden when empty and a tray placeholder shows when there are no rows at all.

Each section header carries a `+` button that calls `walletManager.generateNewAddress(type:strategy: .userRequested)`, with a per-section spinner and haptic on success. Each `AddressHistoryRowView` shows the address via `ExpandableAddressView`, a relative "ago" timestamp, `Address #<derivationIndex>` for onchain rows, and a copy button with a 1.5s checkmark state. Rows do not show used/unused status or received counts.

Gap-limit warning: `AddressError.gapLimitExceeded` is caught in the view and shown as an alert: "Cannot generate new Bitcoin address. You have N unused addresses. For privacy and wallet recovery, please use your existing unused addresses before generating more." The alert strings and the section titles are hard-coded English, not in the string catalog.

The receive screens (`ReceiveView_iOS`, `ReceiveViewModel`, `AddressDisplayView`) only read `walletManager.arkAddress` / `onchainAddress`; there is no "generate new address" control outside Settings. Plan said the receive view would get one; shipped only in Address History.

## Multi-device and read-only mode

`PersistentAddress` is in `SwiftDataHelper.appSchemaModels`, so rows sync through the CloudKit-backed container like the rest of the schema. There is no merge-conflict handling beyond CloudKit's defaults.

Secondary devices never construct `AddressService`. `WalletManager.setModelContext` and `initializeReadOnlyMode` create `ReadOnlyAddressService(modelContext:)` instead, which:

- reads the newest active Ark row and the newest active *unused* onchain row (falling back to the newest onchain row when all are used) into `arkAddress` / `onchainAddress`;
- re-reads on every `.cloudKitDataDidChange` notification, so a fresh install picks up rows that land after init (`ReadOnlySyncedDataTests.addressPicksUpLateImport`);
- cannot generate addresses; `WalletManager.generateNewAddress` throws in this mode.

Because secondaries reuse the primary's unused onchain address, a receive on the secondary is only marked used once the primary's transaction sync runs `linkTransactionToAddress`.

## Wallet deletion

`WalletDataCleanupService.deleteAddressHistory` fetches all `PersistentAddress` rows (regardless of `isActive`) and deletes them; `PersistentAddress` is listed in `directlyWiped`, which the wipe-coverage test enforces. `WalletManager+Wallet.swift` clears the in-memory cached strings on shutdown. Plan said restore would deactivate old rows via `isActive = false`; shipped as hard deletion during wipe, and `isActive` is never toggled.

## Not implemented (plan items with no code)

- Address discovery on sync (`.discovered` rows for receives to addresses not in history).
- Address-history rebuild after seed restore; a re-imported wallet starts with zero rows and `loadAddresses` reveals fresh index 0.
- `unusedCount >= 15` "approaching limit" warning; only the hard `>= 20` error exists.
- Address labels, analytics, export, watch-only addresses, per-address QR codes — none tracked in `Docs/Open_Follow_Ups.md`.

## Open follow-ups

- Claim addresses bypass `AddressService` (untracked, not gap-limited, drift `derivationIndex`; seed import cannot find them) — `Docs/Open_Follow_Ups.md`, "Claimed exit funds invisible after seed import".
- Two-device on-device verify of the read-only receive address after a late CloudKit import — `Docs/Open_Follow_Ups.md`, "On-device verify on the second iPhone".
