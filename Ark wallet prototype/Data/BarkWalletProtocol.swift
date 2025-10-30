//
//  BarkWalletProtocol.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation

// Protocol so both real and mock wallets can be used interchangeably
protocol BarkWalletProtocol {
    var walletDir: URL { get }
    var networkConfig: NetworkConfig { get }
    var isMainnet: Bool { get }
    var currentNetworkName: String { get }
    
    func executeCommand(_ args: [String]) async throws -> String
    func createWallet(network: String?, asp: String?) async throws -> String
    func importWallet(network: String?, asp: String?, mnemonic: String) async throws -> String
    func deleteWallet() async throws -> String
    func getArkBalance() async throws -> ArkBalanceResponse
    func getArkAddress() async throws -> String
    func getArkInfo() async throws -> ArkInfoModel
    func getOnchainAddress() async throws -> String
    func getOnchainBalance() async throws -> OnchainBalanceResponse
    func getVTXOs() async throws -> [VTXOModel]
    func getUTXOs() async throws -> [UTXOModel]
    func getMovements() async throws -> String
    func getConfig() async throws -> ArkConfigModel
    func send(to address: String, amount: Int) async throws -> String
    func sendOnchain(to address: String, amount: Int) async throws -> String
    func board(amount: Int) async throws
    func boardAll() async throws -> String
    func refreshVTXOs() async throws -> String
    func exitVTXO(vtxo_id: String) async throws -> String
    func startExit() async throws -> String
    func getLatestBlockHeight() async throws -> Int
    func getMnemonic() async throws -> String
    
    func payLightningInvoice(invoice: String, amount: Int) async throws -> String
    func getLightningInvoice(amount: Int) async throws -> String
    func getLightningInvoiceStatus(invoice: String) async throws -> String
    func listLightningInvoices() async throws -> String
    func claimLightningInvoice(invoice: String) async throws -> String
    
    // Network safety methods
    func requiresMainnetWarning() -> Bool
    func validateMainnetOperation() throws
    func sendWithSafetyCheck(to address: String, amount: Int) async throws -> String
    func sendOnchainWithSafetyCheck(to address: String, amount: Int) async throws -> String
}
