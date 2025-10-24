# Arké Wallet Prototype

A native macOS wallet prototype for interacting with Ark protocol ([second.tech](https://second.tech) implementation) servers, built with SwiftUI. This application provides a user-friendly, and devastatingly fashion-forward, interface for managing Bitcoin transactions through the Ark protocol, offering enhanced privacy and scalability features.

> ⚠️ **Prototype Notice**: This is an experimental prototype wallet built for testing and demonstration purposes. Do not use with real funds or in production environments. Maybe it will be a real product some day, maybe not. Time will tell. As it tends to do.

## Features

All of this is in heavy development.

### Core Functionality
- **Wallet Management**: Create and manage Ark wallets with secure key storage
- **Multi-Layer Support**: Handle onchain Bitcoin UXTOs and Ark VTXOs
- **Balance Overview**: View total, available, and pending balances across all layers
- **Transaction Activity**: Monitor wallet movements and VTXO states
- **Send & Receive**: Support for Ark and onchain payments (with Lightning Network transactions to come)

### User Interface
- **Native macOS Design**: Built with SwiftUI for optimal macOS integration
- **Sidebar Navigation**: Quick access to balance information and key features
- **Activity Feed**: Real-time updates on wallet movements and transactions
- **Balance Details**: Comprehensive breakdown of onchain and Ark balances with transfer options
- **Settings Panel**: Wallet configuration and management options
- **X-Ray Page**: Explore all the data underlying your wallet

### Transaction Types
- **Ark Transactions**: Fast, private off-chain payments
- **Onchain Transactions**: Direct Bitcoin network operations
- **Board/Offboard**: Move funds between onchain and Ark layers

And, not to forget, some very stylish Midjourney images.

## Architecture

This wallet prototype integrates with the Bark command-line interface (version 0.0.0-alpha.20) to provide a native macOS frontend for Ark protocol operations.

### Key Components
- **VTXOs (Virtual Transaction Outputs)**: Manage off-chain Bitcoin representations
- **Onchain Integration**: Direct Bitcoin blockchain interaction capabilities
- **Lightning Support**: Bolt11 invoice creation and payment processing
- **Ark Protocol**: Privacy-preserving off-chain transaction processing

## Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later
- Access to an Ark protocol server
- Bark CLI tool (version 0.0.0-alpha.20)

### Installation
1. Clone the repository
2. Open the project in Xcode
3. Build and run on your Mac

### Initial Setup
1. Launch the app and create a new wallet
2. Configure connection to your preferred Ark server
3. Fund your wallet through onchain deposits or receiving via Ark

## Development Status

This is a total alpha prototype, running on signet. With your help, it can go from alpha to w-sigma. There's a lot of interesting aspects around Ark that need to be sorted out:
- User interactions around VTXOs (balance transfer, expiration & refreshing)
- Cross-ASP payments
- Fees & economic viability of ASP providers & competitiveness for end-users

## Contributing

This is a prototype project focused on exploring Ark protocol integration with native macOS applications. Contributions should focus on:

- macOS user experience improvements
- Ark protocol integration enhancements
- Security and privacy features
- Testing and validation tools

Please start any contributions with an issue to discuss.

## Bark commandline options

bark

  create        Create a new wallet
  config        Print the configuration of your bark wallet
  onchain       Use the built-in onchain wallet
  ark-info      Prints information related to the Ark Server
  address       Get an address to receive VTXOs
  balance       Get the wallet balance
  vtxos         List the wallet's VTXOs
  movements     List the wallet's payments
  refresh       Refresh expiring VTXOs
  board         Board from the onchain wallet into the Ark
  send          Send money using Ark
  send-onchain  Send money from your vtxo's to an onchain address This method requires to wait for a round
  offboard      Turn VTXOs into UTXOs This command sends
  exit          Perform a unilateral exit from the Ark
  lightning     Perform any lightning-related command [aliases: ln]
  dev           developer commands
  maintain      Run wallet maintenence
  help          Print this message or the help of the given subcommand(s)

bark dev

  vtxo      play with vtxos
  ark-info  inspect the `ArkInfo` of the given server (defaults to wallet server)
  help      Print this message or the help of the given subcommand(s)

bark onchain

  balance    Get the on-chain balance
  address    Get an on-chain address
  send       Send using the on-chain wallet
  send-many  Send using the on-chain wallet to multiple destinations.
             Example usage: send-many --destination bc1pfq...:10000sat --destination bc1pke...:20000sat
             This will send 10,000 sats to bc1pfq... and 20,000 sats to bc1pke...
  drain      Send all wallet funds to provided destination
  utxos      List our wallet's UTXOs
  help       Print this message or the help of the given subcommand(s)

bark lightning

  pay       pay a bolt11 invoice
  invoice   creates a bolt11 invoice with the provided amount
  status    get the status of an invoice
  invoices  list all generated invoices
  claim     claim the receipt of an invoice
  help      Print this message or the help of the given subcommand(s)

## License

This project is provided as-is for educational and experimental purposes. Please ensure compliance with local regulations regarding cryptocurrency software.

## Disclaimer

This wallet prototype is experimental software. It has not undergone security audits and should not be used with real Bitcoin or for production purposes. The developers assume no responsibility for any losses incurred through the use of this software.
