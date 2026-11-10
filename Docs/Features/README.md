# Features Documentation

Reference docs for shipped features, plus the plans still in flight. Each doc carries a `**Status:**` line; plans move to `../Archive/` or become a reference doc when the work ships.

## Exits and refresh

- **[Exit_Architecture.md](Exit_Architecture.md)** — unilateral exits end to end: progression, claim, persistence, UI
- **[Exit_Blocked_State.md](Exit_Blocked_State.md)** — fee-blocked exits surfaced instead of "ready to approve"
- **[Exit_Completion_Issues.md](Exit_Completion_Issues.md)** — fee double-count, cancelled-exit date bump, live activity respawn
- **[Exit_Refresh_Coordination.md](Exit_Refresh_Coordination.md)** — keeping exits and refreshes from fighting over the same VTXOs
- **[Refresh_Deduplication.md](Refresh_Deduplication.md)** — the guiding doc for VTXO refresh scheduling and deduplication
- **[Launch_Ark_First_Refresh.md](Launch_Ark_First_Refresh.md)** — plan (DECIDED 2026-10-14): Ark sync and Ark reads before the onchain sync in every full refresh, balance published on arrival
- **[Exit_Cost_Estimate.md](Exit_Cost_Estimate.md)** — plan (DECIDED 2026-10-19, not built): bark's `estimateEmergencyExitFee` replaces the hand-rolled exit cost; premises at bark 0.8.0, error rule, the 0.7.1 record
- **[Wallet_State_Divergence.md](Wallet_State_Divergence.md)** — Tier 0 field incident (2026-10): wallet missed the mailbox message settling a refresh; the four closed app defects, the remedy that waits on the bindings bump, owed answers

## Background execution

- **[Background_Execution.md](Background_Execution.md)** — BGTasks, silent pushes, relay auth refresh, the auth wake push
- **[Background_Activity_Journal.md](Background_Activity_Journal.md)** — the on-device event journal behind the X-Ray screen

## Connectivity and diagnostics

- **[Offline_Experience.md](Offline_Experience.md)** — Tier 1: the launch "no Ark connection" icon (built 2026-10-12), the CONFIRMED can-never-show-disconnected signal defect, the offline / server-down feature with exit reachability in scope
- **[Lightning_Receive_State.md](Lightning_Receive_State.md)** — Tier 1: the app has no claim loop; surfacing, cancelling or exiting a stuck Lightning receive
- **[Debug_Log_Export.md](Debug_Log_Export.md)** — Tier 2: info-level eviction on device, the notice-level launch skeleton built 2026-10-14, device check owed

## Devices and wallet lifecycle

- **[Read_Only_Mode.md](Read_Only_Mode.md)** — secondary-device read-only mode and primary switching
- **[Wallet_Deletion_And_Rejoin.md](Wallet_Deletion_And_Rejoin.md)** — deletion strategies, the tombstone, rejoin
- **[Wallet_Deletion_Backup_Skip.md](Wallet_Deletion_Backup_Skip.md)** — plan (DECIDED 2026-10-14): the full wipe no longer re-creates the iCloud backup it just deleted
- **[BIP39.md](BIP39.md)** — mnemonic generation, validation, and Keychain storage; open: pre-check the phrase before bark sees it
- **[Backup_Restore.md](Backup_Restore.md)** — Tier 0: the iCloud Drive `db.sqlite` backup is newest-wins with no wallet binding
- **[Ark_Server_Selection.md](Ark_Server_Selection.md)** — PROPOSED 2026-10-29: cover-screen sheet replacing the mainnet/signet toggle, custom Ark server entry, chain/server model split, full-config persistence, probe, what a server change means for an existing wallet

## Payments

- **[Send_Metadata.md](Send_Metadata.md)** — assigning contact, tags, and notes during send (`PendingPaymentMetadata`)
- **[LNURL_Pay.md](LNURL_Pay.md)** — LNURL-pay send support
- **[Signet_Faucet.md](Signet_Faucet.md)** — the signet faucet contact
- **[Board_And_Offboard.md](Board_And_Offboard.md)** — failed boards on bark 0.7.1 (verification owed on 0.8.0), the missing client-side maximum, the modal polish list
- **[Fiat_Rates.md](Fiat_Rates.md)** — fiat values next to sats from one public rates file: contract, cache, staleness, money-safety rules, phases
- **[Mainnet_Fee_Rate_Ceiling.md](Mainnet_Fee_Rate_Ceiling.md)** — Tier 0 fix (2026-10-19): the 10,000 sat/vB sanity ceiling on mainnet Esplora rates, the two overflow sites it bounds, the reader sweep
- **[BIP353_DNSSEC.md](BIP353_DNSSEC.md)** — Tier 0 fix (DONE 2026-10-29): BIP-353 names resolve again through two validating DoH resolvers that must agree; why Apple's DNSSEC validator could not be used (probe evidence); the documented deviation from the BIP and the bark-ffi route to close it

## Data

- **[Balance_Persistence.md](Balance_Persistence.md)** — SwiftData caching of Ark and onchain balances
- **[Tag_System.md](Tag_System.md)** — transaction tagging: models, service, views, CloudKit sync
- **[Address_History.md](Address_History.md)** — persistent address history, gap limit, internal-transfer detection
- **[Metadata_Export_Import.md](Metadata_Export_Import.md)** — exporting and importing contacts, tags, and notes
- **[BDK_Transaction_Reader_Removal.md](BDK_Transaction_Reader_Removal.md)** — why onchain history now comes from bark, and what remains of BDK
- **[Transaction_Upsert_Duplicates.md](Transaction_Upsert_Duplicates.md)** — Tier 1: the upsert deletes duplicate mirrored rows itself and cascades assignments away
- **[Activity_Row_Dating.md](Activity_Row_Dating.md)** — Tier 3, blocked upstream: rows carry the wallet's processing time; the server's arrival time is on the wire as the mailbox checkpoint

## UI and platform

- **[Theme_System.md](Theme_System.md)** — the four image-based themes and the surfaces they cover
- **[Desktop_Parity.md](Desktop_Parity.md)** — macOS parity: done phases, the 2026-11-01 inventory, and the seven batches (Track 1 of the MCP plan); rules in `../Development/Platform_Porting_Rules.md`
- **[Accessibility.md](Accessibility.md)**, **[Intro_Video_Player.md](Intro_Video_Player.md)**, **[Scratch_Card.md](Scratch_Card.md)**

## Agents

- **[MCP_Server.md](MCP_Server.md)** — PROPOSED 2026-11-01: an MCP server inside the Mac app in three tracks (desktop parity → single approved payments → policy engine); the secondary-to-primary transport proposal and what to reuse from the `hackathon/agent-payments` branch

See also `../Send/SendView_Architecture.md` and `../Send/Payment_Destination_Selector.md` for the send flow, `../Initialization/Launch_Performance.md` for the cold-launch timing items, and `../Previewable_Models_Extraction_Plan.md` for the paused ArkéUI refactor.
