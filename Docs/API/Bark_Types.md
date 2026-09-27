# Bark API Types Reference

This document provides comprehensive documentation for the types exposed by the Bark Swift API. The Bark library provides Swift bindings for an Ark protocol implementation, enabling off-chain Bitcoin transactions.

## Table of Contents
- [Core Wallet Types](#core-wallet-types)
- [VTXO Types](#vtxo-types)
- [Transaction & Payment Types](#transaction--payment-types)
- [Configuration Types](#configuration-types)
- [Balance & Status Types](#balance--status-types)
- [Error Types](#error-types)
- [Enums](#enums)

---

## Core Wallet Types

### `Wallet`
The main Bark wallet interface for Ark operations.

**Key Methods:**
- `create(mnemonic:config:datadir:forceRescan:)` - Create a new wallet
- `open(mnemonic:config:datadir:)` - Open an existing wallet
- `sync()` - Lightweight sync with Ark server and blockchain
- `balance()` - Get detailed balance breakdown
- `vtxos()` - Get all spendable VTXOs
- `history()` - Get all wallet movements (transaction history)
- Exit management methods (see [Exit Operations](#exit-operations))
- Lightning payment methods (see [Lightning Types](#lightning-types))

### `OnchainWallet`
Onchain Bitcoin wallet for boarding (deposits) and exits (withdrawals).

**Implementations:**
- **Default**: BDK-based wallet (built-in)
- **Custom**: Your own wallet implementation via callbacks

**Methods:**
- `balance()` → `OnchainBalance` - Get wallet balance
- `newAddress()` → `String` - Generate a new Bitcoin address
- `send(address:amountSats:feeRateSatPerVb:)` → `String` - Send Bitcoin (returns txid)
- `sync()` → `UInt64` - Sync with blockchain (returns amount synced)

---

## VTXO Types

### `Vtxo`
Simplified view of a Virtual Transaction Output (off-chain Bitcoin representation).

**Properties:**
- `id: String` - VTXO identifier (format: "686...9aa:0")
- `amountSats: UInt64` - Amount in satoshis
- `expiryHeight: UInt32` - Block height when VTXO expires (0 if unknown)
- `kind: String` - Type of VTXO
  - `"board"` - From onchain boarding
  - `"round"` - From Ark round transactions
  - `"arkoor"` - From Ark-to-Ark payments
- `state: String` - Current state
  - `"spendable"` - Can be spent
  - `"spent"` - Already used
  - `"locked"` - Temporarily locked (e.g., in round or exit)

**Usage Context:**
VTXOs represent your off-chain balance in the Ark protocol. They expire after a certain number of blocks and need to be refreshed before expiry to maintain custody.

### `ExitVtxo`
A VTXO currently in the exit process (moving from off-chain to on-chain).

**Properties:**
- `vtxoId: String` - VTXO identifier
- `amountSats: UInt64` - Amount in satoshis
- `state: String` - Current exit state (state machine progress)
- `isClaimable: Bool` - Whether this exit can be claimed to onchain wallet

**Usage Context:**
When you exit VTXOs, they go through a state machine. Use `isClaimable` to determine if funds can be drained to your onchain wallet. Call `progressExits()` periodically to advance the state machine.

**Related Methods:**
- `Wallet.startExitForVtxos(vtxoIds:)` - Initiate exit
- `Wallet.progressExits(onchainWallet:feeRateSatPerVb:)` - Advance exits
- `Wallet.listClaimableExits()` - Get claimable exits
- `Wallet.drainExits(vtxoIds:address:feeRateSatPerVb:)` - Claim to address

---

## Transaction & Payment Types

### `Movement`
Wallet movement/transaction record (transaction history entry).

**Properties:**
- `id: UInt32` - Unique movement ID
- `status: String` - Status: `"pending"`, `"successful"`, `"failed"`, `"canceled"`
- `subsystemName: String` - Which subsystem created this movement
- `subsystemKind: String` - Kind of subsystem operation
- `metadataJson: String` - Additional metadata as JSON
- `intendedBalanceSats: Int64` - Intended balance change (can be negative)
- `effectiveBalanceSats: Int64` - Actual balance change after completion
- `offchainFeeSats: UInt64` - Off-chain fees paid
- `sentToAddresses: [String]` - Addresses/invoices sent to
- `receivedOnAddresses: [String]` - Addresses/invoices received on
- `inputVtxoIds: [String]` - VTXOs consumed
- `outputVtxoIds: [String]` - VTXOs created
- `exitedVtxoIds: [String]` - VTXOs sent to exit system
- `createdAt: String` - Timestamp when created
- `updatedAt: String` - Timestamp when last updated
- `completedAt: String?` - Timestamp when completed (nil if not completed)

**Usage Context:**
Movements provide a complete history of all wallet operations. Negative `intendedBalanceSats` means funds leaving, positive means funds arriving.

### `PendingBoard`
Information about a pending board (deposit) transaction.

**Properties:**
- `vtxoId: String` - VTXO ID that will be created once registered
- `amountSats: UInt64` - Amount being boarded
- `txid: String` - On-chain transaction ID

**Usage Context:**
Returned when boarding funds from onchain to Ark. The VTXO becomes spendable after required confirmations.

### `OffboardResult`
Result of an offboard (withdrawal) operation.

**Properties:**
- `roundId: String` - The round ID handling this offboard

**Usage Context:**
Offboarding happens during an Ark round. Track the round to know when funds arrive onchain.

---

## Lightning Types

### `LightningInvoice`
Result of creating a BOLT11 invoice.

**Properties:**
- `invoice: String` - The BOLT11 invoice string
- `amountSats: UInt64` - Amount in satoshis

**Usage Context:**
Generated when you want to receive Lightning payments through Ark.

### `LightningReceive`
Status of a pending Lightning receive.

**Properties:**
- `paymentHash: String` - Payment hash (hex)
- `invoice: String` - The BOLT11 invoice
- `amountSats: UInt64` - Amount in satoshis
- `hasHtlcVtxos: Bool` - Whether HTLC VTXOs have been received
- `preimageRevealed: Bool` - Whether preimage has been revealed

**Usage Context:**
Track incoming Lightning payments. Call `tryClaimLightningReceive()` to complete the payment.

### `LightningSend`
Lightning send payment information.

**Properties:**
- `invoice: String` - The invoice being paid
- `amountSats: UInt64` - Amount in satoshis
- `htlcVtxoCount: UInt32` - Number of HTLC VTXOs locked for this payment
- `preimage: String?` - Payment preimage (present when completed)

**Usage Context:**
Track outgoing Lightning payments. When `preimage` is present, payment succeeded.

---

## Exit Operations

### `ExitClaimTransaction`
Transaction for claiming exited funds.

**Properties:**
- `psbtBase64: String` - Base64-encoded Partially Signed Bitcoin Transaction
- `feeSats: UInt64` - Transaction fee in satoshis

**Usage Context:**
Returned by `drainExits()`. The PSBT is already signed and can be broadcast, or modified before broadcasting.

### `ExitTransactionStatus`
Detailed status of an exit transaction.

**Properties:**
- `vtxoId: String` - VTXO identifier
- `state: String` - Current state in the exit state machine
- `history: [String]?` - State history (if requested)
- `transactionCount: UInt32` - Number of transactions involved

**Usage Context:**
Use `getExitStatus()` for detailed debugging of exit progress.

### `ExitProgressStatus`
Status of an exit progression attempt.

**Properties:**
- `vtxoId: String` - VTXO being exited
- `state: String` - Current state after progression
- `error: String?` - Error message if progression failed

**Usage Context:**
Returned by `progressExits()` - tells you what happened to each VTXO during progression.

---

## Configuration Types

### `Config`
Configuration for creating/opening a Bark wallet.

**Properties:**
- `serverAddress: String` - Ark server address (required)
- `esploraAddress: String?` - Esplora HTTP REST server (mutually exclusive with bitcoind)
- `bitcoindAddress: String?` - Bitcoind RPC address
- `bitcoindCookiefile: String?` - Bitcoind cookie file path
- `bitcoindUser: String?` - Bitcoind RPC username
- `bitcoindPass: String?` - Bitcoind RPC password
- `network: Network` - Bitcoin network (see [Network](#network))
- `vtxoRefreshExpiryThreshold: UInt32?` - Blocks before expiry to refresh VTXOs
- `vtxoExitMargin: UInt16?` - Safety margin for exit timing
- `htlcRecvClaimDelta: UInt16?` - Blocks to claim HTLC receives
- `fallbackFeeRate: UInt64?` - Fallback fee rate (sat/kWu)
- `roundTxRequiredConfirmations: UInt32?` - Confirmations for round txs

**Usage Context:**
You must provide either `esploraAddress` OR bitcoind credentials, not both.

### `ArkInfo`
Ark server configuration information.

**Properties:**
- `network: Network` - Bitcoin network
- `serverPubkey: String` - Ark server public key (hex)
- `roundIntervalSecs: UInt64` - Seconds between rounds
- `nbRoundNonces: UInt32` - Number of nonces per round
- `vtxoExitDelta: UInt32` - Blocks between exit confirmation and spendability
- `vtxoExpiryDelta: UInt32` - VTXO expiration timeframe
- `htlcSendExpiryDelta: UInt32` - Blocks until HTLC-send expires
- `htlcExpiryDelta: UInt32` - Buffer between Lightning and Ark HTLC expiries
- `maxVtxoAmountSats: UInt64?` - Maximum VTXO amount (nil = no limit)
- `requiredBoardConfirmations: UInt32` - Confirmations for boarding
- `maxUserInvoiceCltvDelta: UInt16` - Max CLTV delta for invoice generation
- `minBoardAmountSats: UInt64` - Minimum board amount
- `offboardFeerateSatPerVb: UInt64` - Offboard fee rate
- `lnReceiveAntiDosRequired: Bool` - Whether anti-DoS is required for LN receives

**Usage Context:**
Retrieved from `Wallet.arkInfo()` - tells you about the connected Ark server's policies.

### `WalletProperties`
Read-only properties of the wallet.

**Properties:**
- `network: Network` - Bitcoin network
- `fingerprint: String` - Wallet fingerprint (derived from master key)

---

## Balance & Status Types

### `Balance`
Detailed balance breakdown of the wallet.

**Properties:**
- `spendableSats: UInt64` - Immediately spendable off-chain balance (Ark)
- `pendingInRoundSats: UInt64` - Coins locked in active rounds
- `pendingExitSats: UInt64` - Coins being unilaterally exited
- `pendingLightningSendSats: UInt64` - Coins locked in outgoing Lightning payments
- `claimableLightningReceiveSats: UInt64` - Claimable Lightning receives
- `pendingBoardSats: UInt64` - Coins pending board confirmations

**Usage Context:**
Get from `Wallet.balance()`. The sum of all fields represents your total balance in various states.

### `OnchainBalance`
Onchain Bitcoin wallet balance.

**Properties:**
- `confirmedSats: UInt64` - Confirmed balance
- `pendingSats: UInt64` - Pending balance (trusted + untrusted)
- `totalSats: UInt64` - Total balance (confirmed + pending)

### `RoundState`
A pending round state.

**Properties:**
- `id: UInt32` - Round ID
- `ongoing: Bool` - Whether the round is currently active

**Usage Context:**
Track pending rounds with `Wallet.pendingRoundStates()`.

---

## Address Types

### `AddressWithIndex`
An Ark address with its derivation index.

**Properties:**
- `address: String` - The Ark address string
- `index: UInt32` - The derivation index

**Usage Context:**
Returned by `Wallet.newAddressWithIndex()` when you need to track the index.

---

## Blockchain Types

### `BlockRef`
Reference to a block in the blockchain.

**Properties:**
- `height: UInt32` - Block height
- `hash: String` - Block hash (hex)

### `OutPoint`
A Bitcoin transaction outpoint (reference to a previous output).

**Properties:**
- `txid: String` - Transaction ID (hex)
- `vout: UInt32` - Output index

### `Destination`
A Bitcoin transaction output destination.

**Properties:**
- `address: String` - Bitcoin address
- `amountSats: UInt64` - Amount in satoshis

---

## CPFP (Fee Bumping) Types

### `CpfpParams`
Parameters for creating a CPFP (Child Pays For Parent) transaction.

**Properties:**
- `txHex: String` - Parent transaction to fee-bump (hex)
- `feesType: String` - Fee strategy: `"Effective"` or `"Rbf"`
- `effectiveFeeRateSatPerVb: UInt64` - Target effective fee rate (sat/vB)
- `currentPackageFeeSats: UInt64?` - Current package fee (required for RBF)

**Usage Context:**
Used in custom wallet implementations for fee-bumping exit transactions.

---

## Callback Interfaces

### `CustomOnchainWalletCallbacks`
Protocol for implementing custom onchain wallet functionality.

**Methods:**
- `getBalance()` → `UInt64` - Get wallet balance
- `prepareTx(destinations:feeRateSatPerVb:)` → `String` - Prepare transaction (returns PSBT)
- `prepareDrainTx(address:feeRateSatPerVb:)` → `String` - Prepare drain tx (returns PSBT)
- `finishTx(psbtBase64:)` → `String` - Sign and finalize PSBT (returns hex tx)
- `getWalletTx(txid:)` → `String?` - Get transaction by txid
- `getWalletTxConfirmedBlock(txid:)` → `BlockRef?` - Get confirmation block
- `getSpendingTx(outpoint:)` → `String?` - Find transaction spending an output
- `makeSignedP2aCpfp(params:)` → `String` - Create signed P2A CPFP tx
- `storeSignedP2aCpfp(txHex:)` - Store P2A CPFP transaction

**Usage Context:**
Implement this protocol to integrate your existing wallet with Bark. Pass to `OnchainWallet.custom(callbacks:)`.

---

## Error Types

### `BarkError`
Error types that can occur when using the Bark wallet.

**Cases:**
- `.Network(errorMessage: String)` - Network-related errors
- `.Database(errorMessage: String)` - Database errors
- `.InvalidMnemonic(errorMessage: String)` - Invalid mnemonic phrase
- `.InvalidAddress(errorMessage: String)` - Invalid address format
- `.InvalidInvoice(errorMessage: String)` - Invalid Lightning invoice
- `.InsufficientFunds(errorMessage: String)` - Not enough funds
- `.NotFound(errorMessage: String)` - Resource not found
- `.ServerConnection(errorMessage: String)` - Ark server connection issues
- `.Internal(errorMessage: String)` - Internal errors
- `.OnchainWalletRequired(errorMessage: String)` - Operation requires onchain wallet

**Usage Context:**
All throwing methods can throw `BarkError`. Use `do-catch` to handle specific error types.

---

## Enums

### `Network`
Bitcoin network types.

**Cases:**
- `.bitcoin` - Bitcoin mainnet
- `.testnet` - Bitcoin testnet
- `.signet` - Bitcoin signet
- `.regtest` - Bitcoin regtest (local development)

---

## Top-Level Functions

### `generateMnemonic() throws -> String`
Generate a new BIP39 mnemonic phrase.

### `validateMnemonic(mnemonic: String) throws -> Bool`
Validate a BIP39 mnemonic phrase format.

### `validateArkAddress(address: String) throws -> Bool`
Validate Ark address format (basic format check only, not server-specific).

**Note:** For full validation including server compatibility, use `Wallet.validateArkoorAddress()`.

---

## Key Concepts

### VTXO Lifecycle
1. **Creation**: VTXOs are created through boarding, rounds, or payments
2. **Spendable**: Can be used for payments or exits
3. **Expiry**: VTXOs expire after a certain number of blocks
4. **Refresh**: Must refresh before expiry to maintain custody
5. **Exit**: Can unilaterally exit to reclaim onchain funds

### Exit Process
1. **Start**: Call `startExitForVtxos()` to mark VTXOs for exit
2. **Progress**: Periodically call `progressExits()` to advance state machine
3. **Claimable**: When `isClaimable` is true, funds can be claimed
4. **Drain**: Call `drainExits()` to build claim transaction
5. **Broadcast**: Broadcast the signed PSBT to claim funds onchain

### Round System
Ark uses a round-based system where multiple users' transactions are batched together. Rounds happen at regular intervals (see `ArkInfo.roundIntervalSecs`).

### Maintenance
Call `Wallet.maintenance()` or `Wallet.maintenanceWithOnchain()` periodically to:
- Refresh expiring VTXOs
- Sync with server
- Update Lightning payment states
- Progress exits

---

## Common Patterns

### Creating a Wallet
```swift
let mnemonic = try generateMnemonic()
let config = Config(
    serverAddress: "https://ark.example.com",
    esploraAddress: "https://blockstream.info/api",
    network: .bitcoin
    // ... other config
)
let wallet = try Wallet.create(
    mnemonic: mnemonic,
    config: config,
    datadir: "/path/to/data",
    forceRescan: false
)
```

### Checking Balance
```swift
let balance = try wallet.balance()
print("Spendable: \(balance.spendableSats) sats")
print("Pending: \(balance.pendingInRoundSats) sats")
```

### Exiting VTXOs
```swift
// Start exit
let vtxos = try wallet.spendableVtxos()
let vtxoIds = vtxos.map { $0.id }
try wallet.startExitForVtxos(vtxoIds: vtxoIds)

// Progress exits periodically
let statuses = try wallet.progressExits(
    onchainWallet: onchainWallet,
    feeRateSatPerVb: 10
)

// Check if claimable
let claimable = try wallet.listClaimableExits()
if !claimable.isEmpty {
    // Drain to address
    let claim = try wallet.drainExits(
        vtxoIds: [],  // empty = all claimable
        address: "bc1q...",
        feeRateSatPerVb: 10
    )
    // Broadcast claim.psbtBase64
}
```

### Lightning Payments
```swift
// Receive
let invoice = try wallet.bolt11Invoice(amountSats: 10000)
// Give invoice.invoice to payer

// Send
let payment = try wallet.payLightningInvoice(
    invoice: "lnbc...",
    amountSats: nil  // nil if invoice has amount
)
// Check payment.preimage to confirm success
```

---

## Notes

- This API is generated from Rust via UniFFI, so some patterns may feel different from typical Swift APIs
- Many string-based enums are used (e.g., VTXO states) - future versions may use proper Swift enums
- All amounts are in **satoshis** (1 BTC = 100,000,000 sats)
- Timestamps are ISO 8601 strings
- Transaction IDs and hashes are hex strings
- PSBTs are Base64-encoded strings

---

**Last Updated:** 2026-01-07
**Bark API Version:** Based on UniFFI bindings in bark.swift
