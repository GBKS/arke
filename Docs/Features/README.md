# Features Documentation

Reference docs for shipped features, plus the plans still in flight. Each doc carries a `**Status:**` line; plans move to `../Archive/` or become a reference doc when the work ships.

## Exits and refresh

- **[Exit_Architecture.md](Exit_Architecture.md)** — unilateral exits end to end: progression, claim, persistence, UI
- **[Exit_Blocked_State.md](Exit_Blocked_State.md)** — fee-blocked exits surfaced instead of "ready to approve"
- **[Exit_Completion_Issues.md](Exit_Completion_Issues.md)** — fee double-count, cancelled-exit date bump, live activity respawn
- **[Exit_Refresh_Coordination.md](Exit_Refresh_Coordination.md)** — keeping exits and refreshes from fighting over the same VTXOs
- **[Refresh_Deduplication.md](Refresh_Deduplication.md)** — the guiding doc for VTXO refresh scheduling and deduplication

## Background execution

- **[Background_Execution.md](Background_Execution.md)** — BGTasks, silent pushes, relay auth refresh, the auth wake push
- **[Background_Activity_Journal.md](Background_Activity_Journal.md)** — the on-device event journal behind the X-Ray screen

## Devices and wallet lifecycle

- **[Read_Only_Mode.md](Read_Only_Mode.md)** — secondary-device read-only mode and primary switching
- **[Wallet_Deletion_And_Rejoin.md](Wallet_Deletion_And_Rejoin.md)** — deletion strategies, the tombstone, rejoin
- **[BIP39.md](BIP39.md)** — mnemonic generation, validation, and Keychain storage

## Payments

- **[Send_Metadata.md](Send_Metadata.md)** — assigning contact, tags, and notes during send (`PendingPaymentMetadata`)
- **[LNURL_Pay.md](LNURL_Pay.md)** — LNURL-pay send support
- **[Signet_Faucet.md](Signet_Faucet.md)** — the signet faucet contact
- **[Fiat_Rates.md](Fiat_Rates.md)** — fiat values next to sats from one public rates file: contract, cache, staleness, money-safety rules, phases
- **[Agent_Payments.md](Agent_Payments.md)** — PARKED on branch `hackathon/agent-payments` (BTC++ hackathon, 2nd prize): an agent asks the desktop to pay, the phone approves over a seed-keyed local link, the preimage goes back as proof

## Data

- **[Balance_Persistence.md](Balance_Persistence.md)** — SwiftData caching of Ark and onchain balances
- **[Tag_System.md](Tag_System.md)** — transaction tagging: models, service, views, CloudKit sync
- **[Address_History.md](Address_History.md)** — persistent address history, gap limit, internal-transfer detection
- **[Metadata_Export_Import.md](Metadata_Export_Import.md)** — exporting and importing contacts, tags, and notes
- **[BDK_Transaction_Reader_Removal.md](BDK_Transaction_Reader_Removal.md)** — why onchain history now comes from bark, and what remains of BDK

## UI and platform

- **[Theme_System.md](Theme_System.md)** — the four image-based themes and the surfaces they cover
- **[Desktop_Parity.md](Desktop_Parity.md)** — macOS parity roadmap and status
- **[Accessibility.md](Accessibility.md)**, **[Intro_Video_Player.md](Intro_Video_Player.md)**, **[Scratch_Card.md](Scratch_Card.md)**

See also `../Send/SendView_Architecture.md` and `../Send/Payment_Destination_Selector.md` for the send flow, and `../Previewable_Models_Extraction_Plan.md` for the paused ArkéUI refactor.
