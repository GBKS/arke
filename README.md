# Ark Wallet Prototype

Using bark-0.0.0-alpha.20.

## To-dos

General
- Go straight to main view if there's a wallet
- Is there an import wallet option even?

Cover
- Note about being a prototoype
- Set the visual tone

Sidebar
- Show balance
  - Total when nothing is pending, otherwise available & pending
  - Click to navigate to balance details screen

Activity
- Show movements
- Show UTXOs (for the lack of access to actual transactions)

Balance
- List out onchain and ark balances
- Options to onboard & offboard

Send
- Input field to detect onchain, ark, lightning

Receive
- Toggle ark or onchain address
- Create a lightning invoice

Settings
- Drain option

Data
- Show VTXOs
- Nicely render wallet config

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
