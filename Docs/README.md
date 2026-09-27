# Project Documentation

Welcome to the project documentation. It is organized to help you understand the system architecture, features, and development workflows.

**The docs are created and maintained by AI, mostly for its own use. As the project grows, it can reference basic architectural decisions, etc. In reverse, make sure to tell AI to revise docs as needed.**

`Docs/` lives at the repository root, outside every Xcode target. Nothing here is bundled or compiled, so files can be moved and renamed freely. Filenames follow `Title_Case_With_Underscores.md`; see the naming policy in [Documentation Inventory](Documentation_Inventory.md).

## Start here

- [Open Follow-Ups](Open_Follow_Ups.md) — the canonical list of open items, deferred work, and decisions still owed
- [Documentation Inventory](Documentation_Inventory.md) — what every doc is, its status, and the cleanup backlog
- [Launch Sequence Contract](Initialization/Launch_Sequence_Contract.md) — startup ordering invariants; check before touching launch code
- [Multi-Device Design](Architecture/Multi_Device_Design.md) — the guiding doc for anything touching devices, iCloud, or the seed

## Architecture

- [System Overview](Architecture/system-overview.md), [Data Flow](Architecture/data-flow.md), [Service Layer](Architecture/service-layer.md)
- [Multi-Device Design](Architecture/Multi_Device_Design.md) — scenario catalog and capability matrix for primary/secondary devices
- [Network Configuration Guide](Architecture/network-configuration-guide.md), [Network Configuration Persistence](Architecture/network-configuration-persistence.md)
- [CloudKit Real-Time Sync](CloudKit/CloudKit_Realtime_Sync.md) — how remote-change notifications drive service refreshes
- [Data Version Observation](DataVersionObservation.md), [Process State Service](process-state-service-implementation.md) — root-level for now, pending rename

## Bark (the Ark wallet library)

- [Bark Types](API/Bark_Types.md), [Bark Daemon](API/Bark_Daemon.md) — FFI type and daemon reference
- [Relay Registration API](API/Relay_Registration_API.md) — the push relay contract (`/v1/register`)
- [Bark Bindings Unadopted API](Bark_Bindings_Unadopted_API.md) — binding surface the app has not adopted yet; roadmap inspiration
- [Bark Bindings Feedback](Bark_Bindings_Feedback.md) — issues and asks for the upstream bark developers
- [Migrations/](Migrations/) — one folder per bindings bump (`README`, `01-api-changes`, `02-migration-plan`, `04-completion-report`), from 0.6.3 through 0.25.0
- [Bark Movements](Movements/Bark_Movements.md), [Movement Onchain Linking](Movements/Movement_Onchain_Linking.md)

## Features

- Exits: [Exit Architecture](Features/Exit_Architecture.md), [Exit Blocked State](Features/Exit_Blocked_State.md), [Exit Completion Issues](Features/Exit_Completion_Issues.md), [Exit Refresh Coordination](Features/Exit_Refresh_Coordination.md)
- Refresh: [Refresh Deduplication](Features/Refresh_Deduplication.md)
- Background: [Background Execution](Features/Background_Execution.md), [Background Activity Journal](Features/Background_Activity_Journal.md), [Relay Registration API](API/Relay_Registration_API.md)
- Devices and wallet lifecycle: [Read-Only Mode](Features/Read_Only_Mode.md), [Wallet Deletion and Rejoin](Features/Wallet_Deletion_And_Rejoin.md), [Device Registry Reference](Device_Registry_Reference.md), [Wallet First Initialization](Initialization/Wallet_First_Initialization.md), [Startup Wallet Detection Plan](Initialization/STARTUP_WALLET_DETECTION_PLAN.md)
- Payments: [SendView Architecture](Send/SendView_Architecture.md), [Payment Destination Selector](Payment%20destination%20selection/PAYMENT_DESTINATION_SELECTOR.md), [Send Metadata](Features/send-metadata-enhancement.md), [LNURL Pay](Features/LNURL_Pay.md)
- Data: [Balance Persistence](Features/balance-persistence.md), [Tag System](Features/tag-system.md), [Metadata Export/Import](Features/Metadata_Export_Import.md), [Address History Plan](Address%20history/ADDRESS_HISTORY_PLAN.md), [BDK Transaction Reader Removal](Features/BDK_Transaction_Reader_Removal.md)
- Contacts: [Default Contact](Contacts/Default_Contact.md), [Contact Address Deletion](Contacts/Contact_Address_Deletion.md)
- UI and platform: [Theme System](Features/Theme_System.md), [Desktop Parity](Features/Desktop_Parity.md), [Accessibility](Features/Accessibility.md), [Intro Video Player](Features/Intro_Video_Player.md), [Scratch Card](Features/Scratch_Card.md), [Signet Faucet](Features/Signet_Faucet.md), [BIP39](Features/BIP39.md)
- Refactors in flight: [Previewable Models Extraction Plan](PREVIEWABLE_MODELS_EXTRACTION_PLAN.md) (paused at Phase 3b)

## Localization

- [Localization Guidelines](Localization/Localization_Guidelines.md) — semantic keys, `defaultValue:`, catalog rules
- [Default Value Migration Plan](Localization/Default_Value_Migration_Plan.md), [Translation Rollout Plan](Localization/Translation_Rollout_Plan.md), [Translation Glossary](Localization/Translation_Glossary.md)
- [BitcoinFormatter Locale Guide](BitcoinFormatter-Locale-Guide.md)

## API Reference

- [Service Interfaces](API/service-interfaces.md), [Model Definitions](API/model-definitions.md), [API intro](API/intro.md)

## Development

- [Setup Guide](Development/setup.md), [Testing Patterns](Development/testing-patterns.md), [Common Tasks](Development/common-tasks.md)
- [Change Review Playbook](Development/Change_Review_Playbook.md) — how review passes are run and recorded

## Data samples

- [Movements](Data%20samples/Movements.md), [Exit Transaction Status History](Data%20samples/ExitTransactionStatus_History.md), [Exit Transaction Status State](Data%20samples/ExitTransactionStatus_State.md) — raw dumps used as parser fixtures

## Archive

Historical implementation, migration, and fix documentation, kept under original names: [Archive index](Archive/readme.md). Nothing in `Archive/` is a current reference; when an archived doc contradicts a living one, the living one wins.

## Contributing to documentation

- Plans carry a `**Status:**` line and move to `Archive/` (or become a feature doc) when the work ships.
- Record open items in [Open Follow-Ups](Open_Follow_Ups.md), not only in chat or memory.
- New files use `Title_Case_With_Underscores.md`. Migrations folders keep their numbered names; `README.md` and `Archive/` are exempt.

---
*Last updated: September 27, 2026*
