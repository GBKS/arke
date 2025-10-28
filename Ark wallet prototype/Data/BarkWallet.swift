import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class BarkWallet: BarkWalletProtocol, Equatable {
    let barkPath: String
    let walletDir: URL
    let isPreview: Bool
    let networkConfig: NetworkConfig
    
    init?(networkConfig: NetworkConfig = .signet) {
        // Store the network configuration
        self.networkConfig = networkConfig
        
        // Detect if we're in a SwiftUI Preview
        self.isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        if isPreview {
            print("⚠️ Running in Preview mode - using mock data")
            self.barkPath = ""
            self.walletDir = URL(fileURLWithPath: "/tmp/preview")
            return
        }
        
        guard let path = Bundle.main.path(forResource: "bark", ofType: nil) else {
            print("❌ bark binary not found in bundle")
            return nil
        }
        self.barkPath = path
        self.walletDir = Self.getWalletDirectory()
        
        makeExecutable(path)
        
        print("✅ Bark initialized")
        print("   Binary: \(barkPath)")
        print("   Wallet dir: \(walletDir.path)")
    }
    
    private func makeExecutable(_ path: String) {
        let fileManager = FileManager.default
        try? fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
    }
    
    func executeCommand(_ args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.barkPath)
                
                // IMPORTANT: Use --datadir flag instead of environment variable
                var fullArgs = ["--datadir", self.walletDir.path]
                fullArgs.append(contentsOf: args)
                process.arguments = fullArgs
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                print("🔧 Running: bark --datadir \(self.walletDir.path) \(args.joined(separator: " "))")
                
                // Set up termination handler before starting the process
                process.terminationHandler = { terminatedProcess in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    
                    if !output.isEmpty {
                        print("📤 Output: \(output)")
                    }
                    if !errorOutput.isEmpty {
                        print("📤 Error output: \(errorOutput)")
                    }
                    print("📤 Exit code: \(terminatedProcess.terminationStatus)")
                    
                    if terminatedProcess.terminationStatus != 0 {
                        let fullError = errorOutput.isEmpty ? output : errorOutput
                        continuation.resume(throwing: BarkError.commandFailed(fullError))
                    } else {
                        continuation.resume(returning: output)
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func getWalletDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        // bark will create its own .bark subdirectory, so we just need a parent dir
        let walletDir = appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yourapp.arkwallet")
            .appendingPathComponent("bark-data")
        
        /*
        do {
            try FileManager.default.createDirectory(
                at: walletDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ Wallet directory: \(walletDir.path)")
        } catch {
            print("❌ Failed to create wallet dir: \(error)")
        }
         */
        
        print("📁 Wallet directory will be: \(walletDir.path)")
        
        return walletDir
    }
    
    // Wallet commands
    // bark create --signet --ark ark.signet.2nd.dev --esplora esplora.signet.2nd.dev
    func createWallet(network: String? = nil, asp: String? = nil) async throws -> String {
        let networkType = network ?? networkConfig.networkType
        let aspURL = asp ?? networkConfig.aspURL
        let esploraURL = networkConfig.esploraURL
        
        let args = [
            "create",
            "--\(networkType)",
            "--ark", aspURL,
            "--esplora", esploraURL,
            "--force"
        ]
        let output = try await executeCommand(args)
        return output
    }
    
    // bark create --signet --ark ark.signet.2nd.dev --esplora esplora.signet.2nd.dev --mnemonic "words here"
    func importWallet(network: String? = nil, asp: String? = nil, mnemonic: String) async throws -> String {
        let networkType = network ?? networkConfig.networkType
        let aspURL = asp ?? networkConfig.aspURL
        let esploraURL = networkConfig.esploraURL
        
        let args = [
            "create",
            "--\(networkType)",
            "--ark", aspURL,
            "--esplora", esploraURL,
            "--mnemonic", mnemonic,
            "--force"
        ]
        let output = try await executeCommand(args)
        return output
    }
    
    func deleteWallet() async throws -> String {
        // Handle preview mode
        if isPreview {
            print("⚠️ Preview mode - wallet deletion skipped")
            return "Mock: Wallet deleted (preview mode)"
        }
        
        let fileManager = FileManager.default
        
        // Safety check: verify the wallet directory path looks correct
        guard walletDir.path.contains("bark-data") else {
            throw BarkError.commandFailed("Invalid wallet directory path: \(walletDir.path)")
        }
        
        // Check if wallet directory exists
        guard fileManager.fileExists(atPath: walletDir.path) else {
            print("⚠️ Wallet directory does not exist at: \(walletDir.path)")
            return "Wallet directory does not exist (already deleted)"
        }
        
        print("🗑️ Deleting wallet directory: \(walletDir.path)")
        
        do {
            // Remove the entire wallet directory and its contents
            try fileManager.removeItem(at: walletDir)
            print("✅ Successfully deleted wallet directory")
            return "Successfully deleted wallet directory at \(walletDir.path)"
        } catch {
            print("❌ Failed to delete wallet directory: \(error)")
            throw BarkError.commandFailed("Failed to delete wallet directory: \(error.localizedDescription)")
        }
    }
    
    /*
     {
       "ark": "https://ark.signet.2nd.dev/",
       "bitcoind": null,
       "bitcoind_cookie": null,
       "bitcoind_user": null,
       "bitcoind_pass": null,
       "esplora": "https://esplora.signet.2nd.dev/",
       "vtxo_refresh_expiry_threshold": 12,
       "fallback_fee_rate_kvb": 1000
     }
     */
    func getConfig() async throws -> ArkConfigModel {
        let output = try await executeCommand(["config"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getConfig: \(output)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        do {
            let config = try JSONDecoder().decode(ArkConfigModel.self, from: jsonData)
            return config
        } catch {
            throw BarkError.commandFailed("Could not parse config data: \(error.localizedDescription)")
        }
    }
    
    /*
     {
       "network": "signet",
       "server_pubkey": "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
       "round_interval": "30s",
       "nb_round_nonces": 10,
       "vtxo_exit_delta": 12,
       "vtxo_expiry_delta": 144,
       "htlc_expiry_delta": 6,
       "max_vtxo_amount": 100000000,
       "max_arkoor_depth": 5,
       "required_board_confirmations": 1
     }
     */
    func getArkInfo() async throws -> ArkInfoModel {
        let output = try await executeCommand(["ark-info"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getArkInfo: \(output)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        do {
            let arkInfo = try JSONDecoder().decode(ArkInfoModel.self, from: jsonData)
            return arkInfo
        } catch {
            throw BarkError.commandFailed("Could not parse ark info data: \(error.localizedDescription)")
        }
    }
    
    /*
     {
       "spendable_sat": 0,
       "pending_lightning_send_sat": 0,
       "pending_in_round_sat": 0,
       "pending_exit_sat": 0,
       "pending_board_sat": 0
     }
     */
    func getArkBalance() async throws -> ArkBalanceModel {
        let output = try await executeCommand(["balance"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getBalance: \(output)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        do {
            let balance = try JSONDecoder().decode(ArkBalanceModel.self, from: jsonData)
            return balance
        } catch {
            throw BarkError.commandFailed("Could not parse balance data: \(error.localizedDescription)")
        }
    }
    
    func getArkAddress() async throws -> String {
        let output = try await executeCommand(["address"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /*
     {
       "address": "tb1pdne86phvh597ztahnm58sdh6kwxqzkwcmarg2fa7rzzam4p7rfmqryhv5h"
     }
     */
    func getOnchainAddress() async throws -> String {
        let output = try await executeCommand(["onchain", "address"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
        guard let dict = json as? [String: Any],
              let address = dict["address"] as? String else {
            throw BarkError.commandFailed("Could not parse address from response")
        }
        
        return address
    }
    
    /*
     {
       "total_sat": 501197,
       "trusted_spendable_sat": 501197,
       "immature_sat": 0,
       "trusted_pending_sat": 0,
       "untrusted_pending_sat": 0,
       "confirmed_sat": 501197
     }
     */
    func getOnchainBalance() async throws -> OnchainBalanceModel {
        let output = try await executeCommand(["onchain", "balance"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getOnchainBalance: \(output)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        do {
            let balance = try JSONDecoder().decode(OnchainBalanceModel.self, from: jsonData)
            return balance
        } catch {
            throw BarkError.commandFailed("Could not parse balance data: \(error.localizedDescription)")
        }
    }
    
    /*
     [
       {
         "id": "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
         "amount_sat": 1000,
         "policy_type": "pubkey",
         "user_pubkey": "0395fe00abc5cbb5b8949f70a0b9ff161ef4fed549323c598fee8d47c531b226d2",
         "server_pubkey": "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
         "expiry_height": 274399,
         "exit_delta": 12,
         "chain_anchor": "e334ea46d851b90c173f4ce923f220a37baa4e0a52c5dfcb07f5c89902b79ef2:0",
         "exit_depth": 1,
         "arkoor_depth": 0,
         "state": "UnregisteredBoard"
       }
     ]
     */
    func getVTXOs() async throws -> [VTXOModel] {
        let output = try await executeCommand(["vtxos"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getVTXOs raw output: \(output)")
        print("getVTXOs trimmed JSON: '\(jsonString)'")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response - could not convert to data")
        }
        
        print("getVTXOs jsonData size: \(jsonData.count) bytes")
        
        // Let's also print the raw JSON string for debugging
        if let debugString = String(data: jsonData, encoding: .utf8) {
            print("getVTXOs JSON string for parsing: '\(debugString)'")
        }
        
        do {
            let decoder = JSONDecoder()
            let vtxos = try decoder.decode([VTXOModel].self, from: jsonData)
            print("getVTXOs successfully parsed \(vtxos.count) VTXOs")
            for (index, vtxo) in vtxos.enumerated() {
                print("  VTXO \(index): id=\(vtxo.id), amount=\(vtxo.amountSat), state=\(vtxo.state)")
            }
            return vtxos
        } catch let decodingError as DecodingError {
            print("getVTXOs decoding error details:")
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("  Type mismatch: expected \(type), context: \(context)")
            case .valueNotFound(let type, let context):
                print("  Value not found: \(type), context: \(context)")
            case .keyNotFound(let key, let context):
                print("  Key not found: \(key), context: \(context)")
            case .dataCorrupted(let context):
                print("  Data corrupted: \(context)")
            @unknown default:
                print("  Unknown decoding error: \(decodingError)")
            }
            throw BarkError.commandFailed("Could not parse VTXO data - JSON decoding failed: \(decodingError.localizedDescription)")
        } catch {
            print("getVTXOs general error: \(error)")
            throw BarkError.commandFailed("Could not parse VTXO data: \(error.localizedDescription)")
        }
    }
    
    /*
     [
       {
         "outpoint": "869a6f6856d1c6db0b0d2b323f13a796538c9f11dfe30a9a5d6c20ecfdcdb002:26",
         "amount_sat": 501197,
         "confirmation_height": 274144
       },
       {
         "outpoint": "2ee54cbb552dd2c3f2eccf29ecad06f70dadc8aafa92ab066415356f84732dee:22",
         "amount_sat": 1100738,
         "confirmation_height": 274156
       }
     ]
     */
    func getUTXOs() async throws -> [UTXOModel] {
        let output = try await executeCommand(["onchain", "utxos"])
        let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("getUTXOs: \(output)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BarkError.commandFailed("Invalid JSON response")
        }
        
        do {
            let utxos = try JSONDecoder().decode([UTXOModel].self, from: jsonData)
            return utxos
        } catch let decodingError as DecodingError {
            print("UTXO decoding error details: \(decodingError)")
            throw BarkError.commandFailed("Could not parse UTXO data - JSON decoding failed: \(decodingError.localizedDescription)")
        } catch {
            throw BarkError.commandFailed("Could not parse UTXO data: \(error.localizedDescription)")
        }
    }
    
    /*
    [
      {
        "id": 1,
        "fees": 0,
        "spends": [],
        "receives": [
          {
            "id": "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
            "amount_sat": 1000,
            "policy_type": "pubkey",
            "user_pubkey": "0395fe00abc5cbb5b8949f70a0b9ff161ef4fed549323c598fee8d47c531b226d2",
            "server_pubkey": "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
            "expiry_height": 274399,
            "exit_delta": 12,
            "chain_anchor": "e334ea46d851b90c173f4ce923f220a37baa4e0a52c5dfcb07f5c89902b79ef2:0",
            "exit_depth": 1,
            "arkoor_depth": 0
          }
        ],
        "recipients": [],
        "created_at": "2025-10-17 11:47:49.287"
      }
    ]
     */
    func getMovements() async throws -> String {
        let output = try await executeCommand(["movements"])
        print("getMovements: \(output)")
        return output
    }
    
    func send(to address: String, amount: Int) async throws -> String {
        let args = ["send", address, "\(amount) sats"]
        return try await executeCommand(args)
    }
    
    /*
     {
       "txid": "cc84d21157d31a76267b5874b7a61f411b394d7c4089f5505122421e6bf98dcc"
     }
     */
    func sendOnchain(to address: String, amount: Int) async throws -> String {
        let args = ["onchain", "send", address, "\(amount) sats"]
        return try await executeCommand(args)
    }
    
    /*
     {
       "funding_txid": "e334ea46d851b90c173f4ce923f220a37baa4e0a52c5dfcb07f5c89902b79ef2",
       "vtxos": [
         {
           "id": "4f35af824858dd69802af664a2d1b03d2a49d60b7f66741ba3292de3b756d49a:0",
           "amount_sat": 1000,
           "policy_type": "pubkey",
           "user_pubkey": "0395fe00abc5cbb5b8949f70a0b9ff161ef4fed549323c598fee8d47c531b226d2",
           "server_pubkey": "02f0f358c1b6173ddecec1ad06b42d3762f193e6ff98a3e112292aec21129f9f6b",
           "expiry_height": 274399,
           "exit_delta": 12,
           "chain_anchor": "e334ea46d851b90c173f4ce923f220a37baa4e0a52c5dfcb07f5c89902b79ef2:0",
           "exit_depth": 1,
           "arkoor_depth": 0
         }
       ]
     }
     */
    func board(amount: Int) async throws {
        let args = ["board", "\(amount) sat"]
        _ = try await executeCommand(args)
    }
    
    func boardAll() async throws -> String {
        let args = ["board", "--all"]
        let result = try await executeCommand(args)
        print("boardAll: \(result)")
        return result
    }
    
    func exitVTXO(vtxo_id: String) async throws -> String {
        let args = ["exit", "start", "--vtxo", vtxo_id]
        let result = try await executeCommand(args)
        print("exitVTXO: \(result)")
        return result
    }
    
    func startExit() async throws -> String {
        let args = ["exit", "progress", "--wait"]
        let result = try await executeCommand(args)
        print("startExit: \(result)")
        return result
    }
    
    /*
     {
       "participate_round": true,
       "round": "25f42356e68c001d4239f05b4e2cdaf945de42375acdc7f9e216387f4e933bdd"
     }
     */
    func refreshVTXOs() async throws -> String {
        let result = try await executeCommand(["refresh", "--all"])
        print("refreshVTXOs: \(result)")
        return result
    }
    
    // Network API calls
    func getLatestBlockHeight() async throws -> Int {
        let urlString = "\(networkConfig.esploraBaseURL)/blocks/tip/height"
        guard let url = URL(string: urlString) else {
            throw BarkError.commandFailed("Invalid esplora URL: \(urlString)")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Check if the response is successful
        if let httpResponse = response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                throw BarkError.commandFailed("HTTP error: \(httpResponse.statusCode)")
            }
        }
        
        // Convert data to string and then to integer
        guard let heightString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let height = Int(heightString) else {
            throw BarkError.commandFailed("Invalid block height response")
        }
        
        print("📊 Latest block height: \(height) from \(networkConfig.name)")
        return height
    }
    
    func payLightningInvoice(invoice: String, amount: Int) async throws -> String {
        let result = try await executeCommand(["lightning", "pay", invoice, "\(amount) sats"])
        print("payLightningInvoice: \(result)")
        return result
    }
    
    func getLightningInvoice(amount: Int) async throws -> String {
        let result = try await executeCommand(["lightning", "invoice", "\(amount) sats"])
        print("getLightningInvoice: \(result)")
        return result
    }
    
    func getLightningInvoiceStatus(invoice: String) async throws -> String {
        let result = try await executeCommand(["lightning", "status", invoice])
        print("getLightningInvoiceStatus: \(result)")
        return result
    }
    
    func listLightningInvoices() async throws -> String {
        let result = try await executeCommand(["lightning", "invoices"])
        print("listLightningInvoices: \(result)")
        return result
    }
    
    func claimLightningInvoice(invoice: String) async throws -> String {
        let result = try await executeCommand(["lightning", "claim", invoice])
        print("claimLightningInvoice: \(result)")
        return result
    }
    
    func getMnemonic() async throws -> String {
        if isPreview {
            return "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        }
        
        let mnemonicPath = walletDir.appendingPathComponent("mnemonic")
        
        guard FileManager.default.fileExists(atPath: mnemonicPath.path) else {
            throw BarkError.commandFailed("Mnemonic file not found at \(mnemonicPath.path)")
        }
        
        do {
            let mnemonic = try String(contentsOf: mnemonicPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ Mnemonic retrieved from \(mnemonicPath.path)")
            return mnemonic
        } catch {
            throw BarkError.commandFailed("Failed to read mnemonic file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Network Configuration Helpers
    
    var currentNetworkName: String {
        networkConfig.name
    }
    
    var isMainnet: Bool {
        networkConfig.isMainnet
    }
    
    func requiresMainnetWarning() -> Bool {
        networkConfig.isMainnet
    }
    
    func validateMainnetOperation() throws {
        if networkConfig.isMainnet {
            print("⚠️ MAINNET OPERATION - Real Bitcoin will be used!")
        }
    }
    
    // MARK: - Enhanced Send Methods with Safety Checks
    
    func sendWithSafetyCheck(to address: String, amount: Int) async throws -> String {
        try validateMainnetOperation()
        
        if networkConfig.isMainnet {
            print("🔴 MAINNET SEND: Sending \(amount) sats to \(address)")
        } else {
            print("🔵 \(networkConfig.networkType.uppercased()) SEND: Sending \(amount) sats to \(address)")
        }
        
        return try await send(to: address, amount: amount)
    }
    
    func sendOnchainWithSafetyCheck(to address: String, amount: Int) async throws -> String {
        try validateMainnetOperation()
        
        if networkConfig.isMainnet {
            print("🔴 MAINNET ONCHAIN SEND: Sending \(amount) sats to \(address)")
        } else {
            print("🔵 \(networkConfig.networkType.uppercased()) ONCHAIN SEND: Sending \(amount) sats to \(address)")
        }
        
        return try await sendOnchain(to: address, amount: amount)
    }
    
    // MARK: - Equatable Conformance
    static func == (lhs: BarkWallet, rhs: BarkWallet) -> Bool {
        return lhs.networkConfig == rhs.networkConfig &&
               lhs.walletDir == rhs.walletDir &&
               lhs.isPreview == rhs.isPreview
    }
}

enum BarkError: Error, LocalizedError {
    case binaryNotFound
    case commandFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "bark binary not found in app bundle"
        case .commandFailed(let message):
            return message
        }
    }
}
