//
//  MockBarkWallet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation
import ArkeUI
import Bark

#if DEBUG
/// Minimal stub conformance of `BarkWalletProtocol` for unit tests and the
/// `-skipWalletOpen` / `SKIP_WALLET_OPEN=1` fast-launch debugging path.
/// Canned responses are not kept in sync with the real wallet's output —
/// don't rely on them for realistic data. Debug builds only.
class MockBarkWallet: BarkWalletProtocol {
    let walletDir: URL
    var networkConfig: NetworkConfig
    
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
    
    func createWallet(network: String?, arkServer: String?) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        let networkName = network ?? currentNetworkName
        return "Wallet created successfully on \(networkName) network"
    }
    
    func importWallet(network: String?, arkServer: String?, mnemonic: String) async throws -> String {
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
    
    func getArkBalance() async throws -> ArkBalanceResponse {
        return ArkBalanceResponse(
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
            htlcSendExpiryDelta: 144,
            htlcExpiryDelta: 6,
            maxVtxoAmount: 100000000,
            requiredBoardConfirmations: 1,
            maxUserInvoiceCltvDelta: 288,
            minBoardAmount: 1000,
            maxVtxoExitDepth: 10,
            lnReceiveAntiDosRequired: false,
            feeSchedule: ArkeUI.FeeSchedule(
                board: BoardFeeStructure(minFeeSat: 0, baseFeeSat: 0, ppm: 0),
                offboard: OffboardFeeStructure(
                    baseFeeSat: 0,
                    fixedAdditionalVb: 212,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                ),
                refresh: RefreshFeeStructure(
                    baseFeeSat: 0,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 0),
                        PpmExpiryEntry(expiryBlocksThreshold: 288, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                ),
                lightningReceive: LightningReceiveFeeStructure(baseFeeSat: 0, ppm: 0),
                lightningSend: LightningSendFeeStructure(
                    minFeeSat: 20,
                    baseFeeSat: 0,
                    ppmExpiryTable: [
                        PpmExpiryEntry(expiryBlocksThreshold: 0, ppm: 2000),
                        PpmExpiryEntry(expiryBlocksThreshold: 1008, ppm: 4000),
                        PpmExpiryEntry(expiryBlocksThreshold: 2016, ppm: 5000)
                    ]
                )
            )
        )
    }
    
    func getOnchainAddress() async throws -> String {
        return "tb1qmockaddress789xyz"
    }
    
    func getOnchainBalance() async throws -> OnchainBalanceResponse {
        return OnchainBalanceResponse(
            totalSat: 501197,
            confirmedSat: 501197,
            pendingSat: 0
        )
    }
    
    func getOnchainTransactions() async throws -> [OnchainTransactionModel] {
        // Return mock transactions for preview/testing
        return OnchainTransactionModel.mockTransactions()
    }
    
    func getVTXOs() async throws -> [VTXOModel] {
        let vtxos = [
            VTXOModel(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:0",
                amountSat: 25000,
                expiryHeight: 274500,
                kind: .pubkey,
                state: .spendable
            ),
            VTXOModel(
                id: "def456abc123789012345678901234567890abcdef123456789012345678901234:1",
                amountSat: 15000,
                expiryHeight: 274600,
                kind: .pubkey,
                state: .spendable
            ),
            VTXOModel(
                id: "789012abc456def789012345678901234567890abcdef123456789012345678:2",
                amountSat: 5000,
                expiryHeight: 0,
                kind: .pubkey,
                state: .locked
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
    
    func sendOnchain(to address: String, amount: Int, feeRateSatPerVb: UInt64?) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let feeInfo = feeRateSatPerVb.map { " with fee rate \($0) sat/vB" } ?? ""
        print("💸 Mock: Sent \(amount) sats onchain to \(address)\(feeInfo)")
        return """
        {
          "txid": "cc84d21157d31a76267b5874b7a61f411b394d7c4089f5505122421e6bf98dcc"
        }
        """
    }
    
    func sendToOnchain(to address: String, amount: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("💸 Mock: Sent \(amount) sats to onchain to \(address)")
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
    
    // Disabling since we always want delegated refreshes in the app
    /*
    func refreshVTXOs() async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        return """
        {
          "participate_round": true,
          "round": "25f42356e68c001d4239f05b4e2cdaf945de42375acdc7f9e216387f4e933bdd"
        }
        """
    }
     */
    
    // Disabling since we always want delegated refreshes in the app
    /*
    func refreshVTXOs(vtxo_ids: [String]) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Refreshing \(vtxo_ids.count) VTXOs")
        return """
        {
          "participate_round": true,
          "round": "d85cd074d2a95552d7ab661d065991a53a73ad5863dd17384008714c89f7ecc1"
        }
        """
    }
     */
    
    // Disabling since we always want delegated refreshes in the app
    /*
    func refreshVTXO(vtxo_id: String) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        return """
        {
          "participate_round": true,
          "round": "d85cd074d2a95552d7ab661d065991a53a73ad5863dd17384008714c89f7ecc1"
        }
        """
    }
    */
    
    func getConfig() async throws -> ArkConfigModel {
        return ArkConfigModel(
            serverAddress: "https://ark.signet.2nd.dev/",
            esploraAddress: "https://esplora.signet.2nd.dev/",
            bitcoindAddress: nil,
            bitcoindCookiefile: nil,
            bitcoindUser: nil,
            bitcoindPass: nil,
            network: "signet",
            vtxoRefreshExpiryThreshold: 12,
            vtxoExitMargin: 10,
            htlcRecvClaimDelta: 6,
            fallbackFeeRate: 10,
            roundTxRequiredConfirmations: 1,
            daemonSyncIntervalSecs: 60,
            offboardRequiredConfirmations: 1,
            daemonManualSync: false,
            lightningReceiveClaimRetries: 3
        )
    }
    
    func startExit() async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let result = "Mock: Exit process started for all VTXOs"
        print("🚪 \(result)")
        return result
    }
    
    func sync() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Wallet synced with ASP server")
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

    func payLightningInvoice(invoice: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let amount = amountSats ?? 0
        print("⚡️ Mock: Paid Lightning invoice: \(String(invoice.prefix(30)))... for \(amount) sats, wait: \(wait)")
        let send = LightningSend(
            invoice: invoice,
            amountSats: amount,
            feeSats: 50,
            htlcVtxoCount: 1,
            hasFailedRevocation: false
        )
        return .inProgress(send: send)
    }
    
    func getLightningInvoice(amountSats: UInt64, description: String?) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        // Return a realistic mock Lightning invoice for testing
        let mockInvoice = "lnbc\(amountSats)u1p3xnhl2pp5ur35u5kj8hvdkqf95g8nf8xk2r7x7qxwqjg6z5rf3rxns8wzh0vsdq2gd5hcaqxqrrsssp5mq4g5lqhqhpgjdp5z5v3g3lxktnd8nz2r6t6h4jm0d5yhzckzzqe0xqjzsnqtyqd5hzpjrgvlr5zpajm5g3vdgfr9kqtj3t4epm5gxvhvttzc8q4uqzj9pnfhzjv2e3pj8hx3g0vc2h6y2nywcyqcpfqjxxf"
        print("getLightningInvoice mock: Generated invoice for \(amountSats) sats")
        return mockInvoice
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
    
    func sendOnchainWithSafetyCheck(to address: String, amount: Int, feeRateSatPerVb: UInt64?) async throws -> String {
        try validateMainnetOperation()
        return try await sendOnchain(to: address, amount: amount, feeRateSatPerVb: feeRateSatPerVb)
    }
    
    // MARK: - Development Methods
    
    func executeCustomCommand(_ commandString: String) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔧 Mock: Executing custom command: \(commandString)")
        return "Mock: Custom command executed successfully"
    }
    
    // MARK: - Wallet Lifecycle (New)
    
    func openWalletIfNeeded() async -> Bool {
        // Mock implementation - wallet is always "open" in mock mode
        print("ℹ️ Mock: Wallet already open")
        return true
    }
    
    // MARK: - Exit Operations (New overload)
    
    func exitVTXO(vtxo_id: String, to address: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let result = "Mock: Exit initiated for VTXO \(vtxo_id) to address \(address)"
        print("🚪 \(result)")
        return result
    }
    
    func startExitForVTXOs(vtxo_ids: [String]) async throws -> String {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let result = "Mock: Exit process started for \(vtxo_ids.count) VTXOs"
        print("🚪 \(result)")
        return result
    }
    
    // MARK: - Advanced VTXO Operations (New in FFI)
    
    func allVtxos() async throws -> [Vtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📦 Mock: Returning all VTXOs (including spent)")
        // Return mock Vtxo objects
        return [
            Vtxo(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:0",
                amountSats: 25000,
                expiryHeight: 274500,
                kind: "pubkey",
                state: .spendable,
                exitDepth: 1,
                exitTxWeightWu: 500,
                registered: true
            ),
            Vtxo(
                id: "def456abc123789012345678901234567890abcdef123456789012345678901234:1",
                amountSats: 15000,
                expiryHeight: 274600,
                kind: "pubkey",
                state: .spent,
                exitDepth: 2,
                exitTxWeightWu: 750,
                registered: true
            )
        ]
    }
    
    func spendableVtxos() async throws -> [Vtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("💰 Mock: Returning spendable VTXOs only")
        return [
            Vtxo(
                id: "abc123def456789012345678901234567890abcdef123456789012345678901234:0",
                amountSats: 25000,
                expiryHeight: 274500,
                kind: "pubkey",
                state: .spendable,
                exitDepth: 1,
                exitTxWeightWu: 500,
                registered: true
            )
        ]
    }

    func getExpiringVtxos(thresholdBlocks: UInt32) async throws -> [Vtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("⏰ Mock: Returning VTXOs expiring within \(thresholdBlocks) blocks")
        // Return empty array - no expiring VTXOs in mock
        return []
    }
    
    func getVtxosToRefresh() async throws -> [Vtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Returning VTXOs needing refresh")
        return []
    }
    
    func getVtxoById(vtxoId: String) async throws -> Vtxo {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔍 Mock: Returning VTXO with ID \(vtxoId)")
        return Vtxo(
            id: vtxoId,
            amountSats: 10000,
            expiryHeight: 274500,
            kind: "pubkey",
            state: .spendable,
            exitDepth: 1,
            exitTxWeightWu: 500,
            registered: true
        )
    }
    
    func getFirstExpiringVtxoBlockheight() async throws -> UInt32? {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📅 Mock: Returning first expiring VTXO blockheight")
        return 274500
    }
    
    func getNextRequiredRefreshBlockheight() async throws -> UInt32? {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📅 Mock: Returning next required refresh blockheight")
        return 274400
    }
    
    func importVtxo(vtxoBase64: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📦 Mock: Importing VTXO")
        print("   VTXO data length: \(vtxoBase64.count) chars")
        // Mock implementation - just log the import
    }

    func vtxoEncoded(vtxoId: String) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📦 Mock: Returning encoded VTXO for ID \(vtxoId)")
        return "deadbeef"
    }
    
    // MARK: - Advanced Exit Operations (New in FFI)
    
    func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus] {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("🔄 Mock: Progressing exits with fee rate: \(feeRateSatPerVb ?? 0) sat/vB")
        // Return empty array - no exits in progress
        return []
    }
    
    func syncExits() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Syncing exits")
    }

    func syncForceExitedVtxos() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Syncing force-exited VTXOs")
    }
    
    func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("💸 Mock: Draining \(vtxoIds.isEmpty ? "all" : "\(vtxoIds.count)") exits to \(address)")
        return ExitClaimTransaction(
            psbtBase64: "mock_psbt_base64_string",
            feeSats: 1000
        )
    }
    
    func listClaimableExits() async throws -> [ExitVtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📋 Mock: Listing claimable exits")
        return []
    }
    
    func getExitVtxos() async throws -> [ExitVtxo] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📋 Mock: Getting exit VTXOs")
        return []
    }
    
    func hasPendingExits() async throws -> Bool {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("❓ Mock: Checking for pending exits")
        return false
    }
    
    func pendingExitsTotalSats() async throws -> UInt64 {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💰 Mock: Getting pending exits total")
        return 0
    }
    
    func getExitStatus(vtxoId: String, includeHistory: Bool, includeTransactions: Bool) async throws -> ExitTransactionStatus? {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔍 Mock: Getting exit status for VTXO \(vtxoId)")
        return nil
    }
    
    func allExitsClaimableAtHeight() async throws -> UInt32? {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("📅 Mock: Getting claimable height for all exits")
        return nil
    }
    
    // MARK: - Maintenance Operations (New in FFI)
    
    func maintenanceRefresh() async throws -> String? {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("🔧 Mock: Performing maintenance refresh")
        // Return nil to indicate no refresh was needed
        return nil
    }
    
    // MARK: - Delegated / Non-interactive Operations

    func maintenanceDelegated() async throws {
        print("🔧 Mock: Scheduling delegated maintenance (non-blocking)")
    }

    func refreshVtxosDelegated(vtxoIds: [String]) async throws -> RoundState? {
        print("🔄 Mock: Scheduling delegated VTXO refresh for \(vtxoIds.count) VTXOs (non-blocking)")
        // Return nil to indicate no refresh was needed
        return nil
    }
    
    // MARK: - Server Connection (New in FFI)
    
    func refreshServer() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔌 Mock: Refreshing server connection")
    }
    
    // MARK: - Round Management (New in FFI)
    
    func cancelAllPendingRounds() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🚫 Mock: Canceling all pending rounds")
    }
    
    func cancelPendingRound(roundId: UInt32) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🚫 Mock: Canceling pending round \(roundId)")
    }
    
    func pendingRoundStates() async throws -> [RoundState] {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("📋 Mock: Getting pending round states")
        return []
    }
    
    func progressPendingRounds() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("🔄 Mock: Progressing pending rounds")
    }
    
    func syncPendingBoards() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔄 Mock: Syncing pending boards")
    }
    
    func nextRoundStartTime() async throws -> UInt64 {
        // Return a mock timestamp for the next round start (current time + 5 minutes)
        let mockNextRoundTime = UInt64(Date().timeIntervalSince1970) + 300
        print("🕐 Mock: Next round starts at timestamp \(mockNextRoundTime)")
        return mockNextRoundTime
    }
    
    // MARK: - Enhanced Lightning Operations (New in FFI)
    
    func payLightningOffer(offer: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let amount = amountSats ?? 10000
        print("⚡️ Mock: Paying Lightning BOLT12 offer: \(String(offer.prefix(30)))... for \(amount) sats, wait: \(wait)")
        let send = LightningSend(
            invoice: "lnbc\(amount)n1mock...",
            amountSats: amount,
            feeSats: 50,
            htlcVtxoCount: 1,
            hasFailedRevocation: false
        )
        return .inProgress(send: send)
    }
    
    func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        if let comment = comment {
            print("⚡️ Mock: Paying Lightning address: \(lightningAddress) for \(amountSats) sats with comment: \(comment), wait: \(wait)")
        } else {
            print("⚡️ Mock: Paying Lightning address: \(lightningAddress) for \(amountSats) sats, wait: \(wait)")
        }
        let send = LightningSend(
            invoice: "lnbc\(amountSats)n1mock...",
            amountSats: amountSats,
            feeSats: 50,
            htlcVtxoCount: 1,
            hasFailedRevocation: false
        )
        return .inProgress(send: send)
    }

    func payLnurl(lnurl: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        if let comment = comment {
            print("⚡️ Mock: Paying LNURL: \(lnurl) for \(amountSats) sats with comment: \(comment), wait: \(wait)")
        } else {
            print("⚡️ Mock: Paying LNURL: \(lnurl) for \(amountSats) sats, wait: \(wait)")
        }
        let send = LightningSend(
            invoice: "lnbc\(amountSats)n1mock...",
            amountSats: amountSats,
            feeSats: 50,
            htlcVtxoCount: 1,
            hasFailedRevocation: false
        )
        return .inProgress(send: send)
    }

    func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: wait ? 1_000_000_000 : 300_000_000)
        print("🔍 Mock: Checking Lightning payment status for \(String(paymentHash.prefix(16)))...")
        // Return unknown status for mock
        return .unknown
    }
    
    func lightningReceiveState(paymentHash: String) async throws -> LightningReceive {
        try await Task.sleep(nanoseconds: 500_000_000)
        print("🔍 Mock: Getting Lightning receive state for \(String(paymentHash.prefix(16)))...")
        // The mock tracks no receives, so every hash is unknown (v0.12+ throws instead of returning nil)
        throw BarkErrorArke.commandFailed("Mock: unknown payment hash")
    }

    @discardableResult
    func tryClaimLightningReceive(paymentHash: String, wait: Bool) async throws -> LightningReceive {
        try await Task.sleep(nanoseconds: wait ? 1_500_000_000 : 500_000_000)
        print("💰 Mock: Claiming Lightning receive for \(String(paymentHash.prefix(16)))...")
        return LightningReceive(
            paymentHash: paymentHash,
            invoice: "lnbc1mock...",
            amountSats: 0,
            state: "settled",
            paymentPreimage: nil,
            settledAt: Int64(Date().timeIntervalSince1970),
            claimDestination: nil
        )
    }
    
    func claimableLightningReceiveBalanceSats() async throws -> UInt64 {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💰 Mock: Getting claimable Lightning receive balance")
        return 0
    }
    
    func pendingLightningReceives() async throws -> [LightningReceive] {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("📋 Mock: Getting pending Lightning receives")
        return []
    }
    
    func cancelLightningReceive(paymentHash: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("❌ Mock: Canceling Lightning receive for payment hash: \(String(paymentHash.prefix(16)))...")
    }
    
    func allowLightningSendToExit(paymentHash: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("🚪 Mock: Allowing stuck Lightning send to exit: \(String(paymentHash.prefix(16)))...")
    }
    
    func attemptLightningReceiveExit(paymentHash: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("🚪 Mock: Attempting Lightning receive exit: \(String(paymentHash.prefix(16)))...")
    }
    
    func stuckFailedLightningSends() async throws -> [LightningSend] {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("🔍 Mock: Checking for stuck failed Lightning sends...")
        return [] // No stuck sends in mock
    }
    
    func isInvoicePaid(paymentHash: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("🔍 Mock: Checking if invoice paid for payment hash: \(String(paymentHash.prefix(16)))...")
        return false
    }
    
    func lightningSendState(paymentHash: String) async throws -> LightningSendStatus {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("🔍 Mock: Getting Lightning send state for payment hash: \(String(paymentHash.prefix(16)))...")
        return .unknown
    }
    
    // MARK: - Fee Estimation
    
    func estimateArkoorPaymentFee(amountSats: UInt64) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating Arkoor payment fee for \(amountSats) sats")
        return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateBoardFee(amountSats: UInt64) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating board fee for \(amountSats) sats")
        return FeeEstimate(grossAmountSats: 100, feeSats: 100, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateLightningReceiveFee(amountSats: UInt64) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating Lightning receive fee for \(amountSats) sats")
        return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateLightningSendFee(amountSats: UInt64) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating Lightning send fee for \(amountSats) sats")
        return FeeEstimate(grossAmountSats: 50, feeSats: 50, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateOffboardFee(address: String, vtxoIds: [String]) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating offboard fee for \(vtxoIds.count) VTXOs to \(String(address.prefix(16)))...")
        return FeeEstimate(grossAmountSats: 200, feeSats: 200, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateRefreshFee(vtxoIds: [String]) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating refresh fee for \(vtxoIds.count) VTXOs")
        return FeeEstimate(grossAmountSats: 75, feeSats: 75, netAmountSats: 0, vtxosSpent: [])
    }
    
    func estimateSendToOnchainFee(address: String, amountSats: UInt64) async throws -> FeeEstimate {
        try await Task.sleep(nanoseconds: 300_000_000)
        print("💵 Mock: Estimating send onchain fee for \(amountSats) sats to \(String(address.prefix(16)))...")
        return FeeEstimate(grossAmountSats: 150, feeSats: 150, netAmountSats: 0, vtxosSpent: [])
    }
    
    // MARK: - Mailbox Operations
    
    func mailboxIdentifier() throws -> String {
        print("📮 Mock: Getting mailbox identifier")
        return "02a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890"
    }
    
    func mailboxAuthorization() throws -> String {
        print("🔐 Mock: Getting mailbox authorization")
        return "mock_authorization_token_abc123def456"
    }
    
    // MARK: - Utilities
    
    func extractTxFromPsbt(psbtBase64: String) throws -> String {
        print("🔧 Mock: Extracting transaction from PSBT")
        return "mock_transaction_hex_string"
    }
    
    func broadcastTx(txHex: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("📡 Mock: Broadcasting transaction: \(String(txHex.prefix(16)))...")
        return "mock_txid_abc123def456789012345678901234567890abcdef123456789012345678901234"
    }
    
    /**
     * Get a pull-based notification holder for this wallet.
     *
     * Call `next_notification()` in a loop to receive events.
     * Call `cancel_next_notification_wait()` to unblock a pending wait without
     * destroying the stream.
     */
    func notifications() -> NotificationHolder {
        fatalError("Mock implementation does not support notifications")
    }
    
    func runDaemon() async throws {
        print("🤖 Mock: Starting wallet daemon")
    }
    
    func stopDaemon() async throws {
        print("🛑 Mock: Stopping wallet daemon")
    }
    
    func updateNetworkConfig(_ newConfig: NetworkConfig) {
        self.networkConfig = newConfig
    }
}
#endif


