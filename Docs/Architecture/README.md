# Architecture Documentation

High-level documentation of how the major components of the system work together.

## Documents

- **[System_Overview.md](System_Overview.md)** — high-level architecture, component responsibilities, and system boundaries
- **[Data_Flow.md](Data_Flow.md)** — how data flows through the application from external sources to UI
- **[Service_Layer.md](Service_Layer.md)** — core services, their responsibilities, and interaction patterns
- **[Multi_Device_Design.md](Multi_Device_Design.md)** — the guiding doc for primary/secondary devices, iCloud, and the seed: scenario catalog and capability matrix
- **[CloudKit_Realtime_Sync.md](CloudKit_Realtime_Sync.md)** — how `CloudKitObserver` turns remote-change notifications into `.cloudKitDataDidChange` and which services reload on it
- **[Data_Version_Observation.md](Data_Version_Observation.md)** — the `WalletManager.dataVersion` trigger that makes SwiftUI refresh when SwiftData relationships change
- **[Process_State_Service.md](Process_State_Service.md)** — `ProcessStateService`: exits, VTXO health, server connection, and backup reminders in one place
- **[Network_Configuration_Guide.md](Network_Configuration_Guide.md)**, **[Network_Configuration_Persistence.md](Network_Configuration_Persistence.md)** — network selection and how the config is persisted and reconciled with iCloud

See also `../Initialization/Launch_Sequence_Contract.md` for startup ordering invariants.
