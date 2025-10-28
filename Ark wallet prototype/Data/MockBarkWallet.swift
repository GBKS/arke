//
//  MockBarkWallet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation

class MockBarkWallet: BarkWalletProtocol {
    let walletDir: URL
    let networkConfig: NetworkConfig
    
    var isMainnet: Bool {
        return networkConfig.isMainnet
    }
    
    var currentNetworkName: String {
        return networkConfig.name
    }
    
    init(networkConfig: NetworkConfig = .signet) {
        // Mock wallet directory
        self.walletDir = URL(fileURLWithPath: "/tmp/mock-bark-wallet")
        self.networkConfig = networkConfig
    }
    
    func executeCommand(_ args: [String]) async throws -> String {
        // Simulate delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let command = args.first ?? ""
        
        switch command {
        case "balance":
            return """
            {
              "spendable_sat": 50000,
              "pending_lightning_send_sat": 0,
              "pending_in_round_sat": 10000,
              "pending_exit_sat": 0,
              "pending_board_sat": 0
            }
            """
        case "address":
            return "ark1qxyz123mockaddress456"
        case "onchain":
            if args.contains("address") {
                return "tb1qmockaddress789xyz"
            }
        case "vtxos":
            return "2 VTXOs found"
        case "create":
            return "Wallet created successfully"
        default:
            break
        }
        
        return "Mock command executed: \(args.joined(separator: " "))"
    }
    
    func createWallet(network: String?, asp: String?) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        let networkName = network ?? currentNetworkName
        return "Wallet created successfully on \(networkName) network"
    }
    
    func importWallet(network: String?, asp: String?, mnemonic: String) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        let wordCount = mnemonic.split(separator: " ").count
        let networkName = network ?? currentNetworkName
        return "Wallet imported successfully on \(networkName) network using \(wordCount)-word mnemonic"
    }
    
    func deleteWallet() async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🗑️ Mock: Wallet deletion simulated")
        return "Mock: Successfully deleted wallet directory at \(walletDir.path)"
    }
    
    func getArkBalance() async throws -> ArkBalanceModel {
        return ArkBalanceModel(
            spendableSat: 50000,
            pendingLightningSendSat: 0,
            pendingInRoundSat: 10000,
            pendingExitSat: 0,
            pendingBoardSat: 0
        )
    }
    
    func getArkAddress() async throws -> String {
        return "ark1qxyz123mockaddress456"
    }
    
    func getArkInfo() async throws -> ArkInfoModel {
        return ArkInfoModel(
            network: "signet",
            serverPubkey: "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
            roundInterval: "30s",
            nbRoundNonces: 10,
            vtxoExitDelta: 12,
            vtxoExpiryDelta: 144,
            htlcExpiryDelta: 6,
            maxVtxoAmount: 100000000,
            maxArkoorDepth: 5,
            requiredBoardConfirmations: 1
        )
    }
    
    func getOnchainAddress() async throws -> String {
        return "tb1qmockaddress789xyz"
    }
    
    func getOnchainBalance() async throws -> OnchainBalanceModel {
        return OnchainBalanceModel(
            totalSat: 501197,
            trustedSpendableSat: 501197,
            immatureSat: 0,
            trustedPendingSat: 0,
            untrustedPendingSat: 0,
            confirmedSat: 501197
        )
    }
    
    func getVTXOs() async throws -> [VTXOModel] {
        let vtxos = [
            VTXOModel(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:0",
                amountSat: 25000,
                policyType: .pubkey,
                userPubkey: "03abc123def456789012345678901234567890abcdef123456789012345678901234",
                serverPubkey: "02def456abc123789012345678901234567890abcdef123456789012345678901234",
                expiryHeight: 274500,
                exitDelta: 10,
                chainAnchor: "abc123def456789012345678901234567890abcdef123456789012345678901234:0",
                exitDepth: 1,
                arkoorDepth: 0,
                state: .unregisteredBoard
            ),
            VTXOModel(
                id: "def456abc123789012345678901234567890abcdef123456789012345678901234:1",
                amountSat: 15000,
                policyType: .pubkey,
                userPubkey: "03def456abc123789012345678901234567890abcdef123456789012345678901234",
                serverPubkey: "02abc123def456789012345678901234567890abcdef123456789012345678901234",
                expiryHeight: 274600,
                exitDelta: 12,
                chainAnchor: "def456abc123789012345678901234567890abcdef123456789012345678901234:0",
                exitDepth: 2,
                arkoorDepth: 1,
                state: .registeredBoard
            )
        ]
        
        return vtxos
    }
    
    func getUTXOs() async throws -> [UTXOModel] {
        let utxos = [
            UTXOModel(
                outpoint: "869a6f6856d1c6db0b0d2b323f13a796538c9f11dfe30a9a5d6c20ecfdcdb002:26",
                amountSat: 501197,
                confirmationHeight: 274144
            ),
            UTXOModel(
                outpoint: "2ee54cbb552dd2c3f2eccf29ecad06f70dadc8aafa92ab066415356f84732dee:22",
                amountSat: 1100738,
                confirmationHeight: 274156
            )
        ]
        
        return utxos
    }
    
    func getMovements() async throws -> String {
        // Return mock VTXO data in a format that resembles what the real bark command might return
        return """
        VTXO 1: id=abc123def456789012345678901234567890abcdef123456789012345678901234:0, amount=25000, state=UnregisteredBoard
        VTXO 2: id=def456abc123789012345678901234567890abcdef123456789012345678901234:1, amount=15000, state=RegisteredBoard
        """
    }
    
    func send(to address: String, amount: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    func sendOnchain(to address: String, amount: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("💸 Mock: Sent \(amount) sats onchain to \(address)")
        return """
        {
          "txid": "cc84d21157d31a76267b5874b7a61f411b394d7c4089f5505122421e6bf98dcc"
        }
        """
    }
    
    func board(amount: Int) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("🏄‍♂️ Mock: Boarded \(amount) sats to Ark")
    }
    
    func boardAll() async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let result = "Mock: Boarded all available UTXOs (1,601,935 sats) to Ark"
        print("🏄‍♂️ \(result)")
        return result
    }
    
    func refreshVTXOs() async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        return """
        {
          "participate_round": true,
          "round": "25f42356e68c001d4239f05b4e2cdaf945de42375acdc7f9e216387f4e933bdd"
        }
        """
    }
    
    func getConfig() async throws -> ArkConfigModel {
        return ArkConfigModel(
            ark: "https://ark.signet.2nd.dev/",
            bitcoind: nil,
            bitcoindCookie: nil,
            bitcoindUser: nil,
            bitcoindPass: nil,
            esplora: "https://esplora.signet.2nd.dev/",
            vtxoRefreshExpiryThreshold: 12,
            fallbackFeeRateKvb: 1000
        )
    }
    
    func exitVTXO(vtxo_id: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let result = "Mock: Exit initiated for VTXO \(vtxo_id)"
        print("🚪 \(result)")
        return result
    }
    
    func startExit() async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let result = "Mock: Exit process started for all VTXOs"
        print("🚪 \(result)")
        return result
    }
    
    func getLatestBlockHeight() async throws -> Int {
        try await Task.sleep(nanoseconds: 500_000_000)
        // Return a mock block height that would be reasonable for signet
        return 274500
    }
    
    func getMnemonic() async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        // Return a mock mnemonic phrase (12 words)
        return "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    }
    
    func payLightningInvoice(invoice: String, amount: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    func getLightningInvoice(amount: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    func getLightningInvoiceStatus(invoice: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    func listLightningInvoices() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    func claimLightningInvoice(invoice: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ""
    }
    
    // MARK: - Network Safety Methods
    
    func requiresMainnetWarning() -> Bool {
        return isMainnet
    }
    
    func validateMainnetOperation() throws {
        // Mock implementation - doesn't actually validate anything
        if isMainnet {
            print("⚠️ Mock: Mainnet operation validation (would show warning in real implementation)")
        }
    }
    
    func sendWithSafetyCheck(to address: String, amount: Int) async throws -> String {
        try validateMainnetOperation()
        return try await send(to: address, amount: amount)
    }
    
    func sendOnchainWithSafetyCheck(to address: String, amount: Int) async throws -> String {
        try validateMainnetOperation()
        return try await sendOnchain(to: address, amount: amount)
    }
}


