# Arké Wallet

A native Bitcoin wallet for iPhone that integrates the Ark protocol ([second.tech](https://second.tech)) for enhanced privacy and scalability. Built with SwiftUI and designed for Apple's Liquid Glass design system, Arké provides a user-friendly, devastatingly fashion-forward interface for managing Bitcoin across multiple layers.

**Try it now**: Sign up for TestFlight at [arke.cash](https://arke.cash/)

> ⚠️ **Beta Software**: Arké now runs on Bitcoin mainnet by default. Signet is available from the cover screen for testing. This software has not undergone a formal security audit — use with caution and only amounts you are comfortable risking.

## Platform Requirements

- **iOS 26.0 or later** - Required for Liquid Glass design system support
- iPhone only (iPad and macOS are not currently supported)

### A Note on Platform Evolution

Arké began as a macOS application using the Bark CLI tool directly, as Swift bindings weren't initially available for iOS. The codebase still contains macOS code from this earlier phase. The vision evolved toward synchronized iOS and macOS apps, but reliable multi-device wallet synchronization requires protocol-level support that isn't yet available (VTXOs need recovery mechanisms that work across separately-synced devices, and iCloud alone isn't sufficient for this use case).

The current focus is on delivering an excellent iOS experience first. A future macOS version may take one of several approaches: separate wallets per platform, a lightweight companion app that pairs with your iPhone, or full multi-device sync once the underlying protocol supports it. The path forward will become clearer as the Ark ecosystem matures.

## Features

### Multi-Layer Bitcoin Wallet
- **Onchain Layer**: Full Bitcoin wallet powered by Bitcoin Dev Kit (BDK)
  - Send and receive standard Bitcoin transactions
  - Complete UTXO management and coin control
  - Custom fee rate support
- **Ark Layer**: Privacy-enhanced off-chain transactions via VTXOs
  - Fast, private payments within the Ark network
  - Automatic VTXO management and refresh
  - Board and offboard between onchain and Ark layers
- **Lightning Network**: Bolt11 invoice support
  - Create and pay Lightning invoices
  - Bolt12, Lightning address, and BIP353 support
  - Claim and track invoice payments

### Transaction Management
- **Unified Activity Feed**: All transactions across layers in one view
- **Contact System**: Save and manage payment recipients
  - Native iOS Contacts integration
  - Custom contact addresses for Bitcoin, Ark, and Lightning
  - Automatic contact matching for transactions
- **Tag System**: Organize transactions with custom tags
  - Visual tag colors and icons
  - Net change tracking per tag
  - Tag-based transaction filtering
- **Transaction Notes**: Add personal notes to any transaction

### iOS-Specific Features
- **Tilt-to-Pay**: Elegant gesture-based receiving
  - Tilt your device to reveal a full-screen QR code overlay
  - Personalized with your profile photo and name
- **Profile Personalization**: Customize your wallet identity
  - Add profile photo from your photo library
  - Set a display name for your wallet
- **Native Integration**: Deep iOS system integration
  - Contacts framework integration
  - Haptic feedback

### Cloud Sync
- **iCloud Sync**: Sync your data across devices
  - Transactions, contacts, and tags
  - User profiles and settings
  - Backup reminders and device registry

### Network Support
- **Mainnet**: Live Bitcoin network (default)
- **Signet**: Bitcoin signet for testing (available from the cover screen)

Note: Only one Ark server is currently available. Additional server options will become available as the Ark ecosystem grows.

### Privacy & Security
- **Secure Key Storage**: BIP39 mnemonics stored in device Keychain
- **Privacy-First Design**: Ark protocol provides enhanced transaction privacy
- **Local Control**: Your keys, your Bitcoin

### Developer Features
- **X-Ray View**: Inspect all underlying wallet data
  - UTXO details and management
  - VTXO states and expiration tracking
  - Unilateral exit management
  - Raw transaction data
- **Network Diagnostics**: Connection status and server information

## Architecture

Arké is built with modern Swift technologies and native Bitcoin tooling for optimal performance and security.

### Technology Stack
- **SwiftUI**: Native iOS and macOS user interface
- **SwiftData**: Local persistence with iCloud CloudKit sync
- **Swift 6**: Strict concurrency for thread-safe operations
- **BarkProtocol FFI**: Direct Rust library bindings for Ark protocol operations
- **Bitcoin Dev Kit (BDK)**: Production-grade Bitcoin wallet functionality
- **Keychain Services**: Secure storage for sensitive data

### Core Components
- **WalletManager**: Coordinates all wallet operations and state
- **BarkWalletFFI**: Foreign Function Interface to the Ark protocol implementation
- **BDKOnchainWallet**: Bitcoin layer using Bitcoin Dev Kit
- **ServiceContainer**: Manages tag, contact, and sync services
- **SwiftData Models**: Transaction history, contacts, tags, and user profiles with CloudKit sync

### Data Flow
1. User interface built with SwiftUI
2. WalletManager coordinates operations
3. BarkWalletFFI handles Ark-specific operations via native Rust bindings
4. BDK handles onchain Bitcoin operations
5. SwiftData persists data locally and syncs via CloudKit
6. Keychain stores sensitive cryptographic material

## Getting Started

### For Users
The easiest way to try Arké is through TestFlight:

1. Visit [arke.cash](https://arke.cash/) and sign up for TestFlight access
2. Install the app on your iPhone (iOS 26.0 or later required)
3. Create a new wallet or import an existing one
4. Start receiving and sending Bitcoin on mainnet (or switch to signet from the cover screen for testing)

### For Developers

#### Prerequisites
- macOS 15.0 or later
- Xcode 16.2 or later (for Liquid Glass support)
- iOS 26+ device or simulator

#### Building from Source
1. Clone the repository
   ```bash
   git clone https://github.com/gbks/arke.git
   cd arke
   ```
2. Open `Arke.xcodeproj` in Xcode
3. Select the iOS target
4. Build and run (⌘R)

#### Project Structure
- `Arké mobile/` - iOS-specific code (primary focus)
- `Shared/` - Shared business logic and data models
- `ArkeUI/` - Reusable UI components package
- `Arké/` - macOS code (currently not maintained)

### Initial Wallet Setup
1. **Create New Wallet**: Generate a new BIP39 mnemonic
2. **Import Wallet**: Restore from existing 12 or 24-word seed phrase
3. **Backup**: Securely store your recovery phrase

All devices signed into the same iCloud account automatically share the same wallet. One device acts as the primary — maintaining the active connection to the Ark server — while other devices are read-only.

## What is Ark?

Ark is a second-layer protocol for Bitcoin that enables:
- **Enhanced Privacy**: Transactions within Ark are more private than standard Bitcoin transactions
- **Instant Payments**: Near-instant settlement between Ark users
- **Scalability**: Reduced blockchain footprint for frequent transactions
- **Self-Custody**: Maintain control of your Bitcoin with unilateral exit capability

Virtual Transaction Outputs (VTXOs) represent your Bitcoin within the Ark network. They can be:
- Transferred instantly to other Ark users
- Exited to onchain Bitcoin at any time
- Automatically refreshed before expiration

Ark was invented in 2023 by Burak, a Bitcoin developer. The protocol is open source and being developed by two independent teams: [Ark Labs](https://arklabs.xyz) and [Second](https://second.tech). Arké is built on Second's implementation, which focuses on Bitcoin payments.

Learn more at [ark-protocol.org](https://ark-protocol.org)

## Development Status & Roadmap

Arké is developed in phases. See the full roadmap at [arke.cash/roadmap](https://arke.cash/roadmap).

Current status:
- ✅ iOS application with Liquid Glass design
- ✅ Production-ready architecture with FFI and BDK
- ✅ iCloud sync
- ✅ Contact and tag management
- ✅ Lightning Network integration
- ✅ Localization and accessibility
- ✅ Performance optimizations
- ✅ Mainnet support
- ⏳ Broader beta testing with non-technical users

## Contributing

While contributions are welcome, there is no proper structure in place to chip in. It's a single-person project at the moment, iterating every day. The biggest help at this time are to provide feedback on any aspect of Arké.

## Privacy & Data

### iCloud Sync
Arké uses CloudKit to sync the following data across your devices:
- Transaction metadata (contacts, tags, notes)
- User profile information
- Wallet configuration and preferences
- Device registry

**What is NOT synced:**
- Raw transaction data from the blockchain

**Security:**
- Your seed phrase syncs across devices via iCloud Keychain with end-to-end encryption
- Transaction metadata and wallet configuration sync via CloudKit; enabling [Advanced Data Protection](https://support.apple.com/en-us/108756) in iPhone Settings extends end-to-end encryption to this data as well

You can disable iCloud sync in System Settings if preferred, though this will limit multi-device functionality.

### Data Collection
Arké does not collect analytics, telemetry, or usage data. All wallet operations occur locally or directly with your chosen Ark service provider and Bitcoin nodes.

## Support & Community

- **Website**: [arke.cash](https://arke.cash/)
- **Ark Protocol**: [ark-protocol.org](https://ark-protocol.org)
- **Second**: [second.tech](https://second.tech)
- **Issues**: Report bugs and request features via GitHub Issues

## License

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg)](http://creativecommons.org/licenses/by-nc/4.0/)

This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0).

**What this means:**
- ✅ Free to use, modify, and share for personal, educational, and non-profit purposes
- ✅ Must provide attribution when sharing or building upon this work
- ❌ Commercial use prohibited without permission (including offering as a paid service)
- ❌ Derivatives inherit the same restrictions

See the [LICENSE](LICENSE) file for full details.

**Commercial Licensing:** If you're interested in using Arké for commercial purposes, please contact the project maintainers to discuss licensing options.

Please ensure compliance with local regulations regarding cryptocurrency software.

## Disclaimer

**Beta Software — Use With Caution:** Arké now defaults to Bitcoin mainnet:

- This software is in beta and has not undergone a formal security audit
- Only use amounts you are comfortable risking
- Always maintain secure backups of your recovery phrase
- The Ark protocol is an emerging technology — understand the trade-offs before use
- Signet is available from the cover screen for risk-free testing
- The developers assume no responsibility for any losses incurred through use of this software

**Remember**: Not your keys, not your Bitcoin. Always maintain control of your seed phrase and understand how to recover your funds.
