//
//  BarkWalletFFI+Server.swift
//  Arke
//
//  Server connection management and sync operations
//  Handles connection establishment, polling, and wallet synchronization
//
//  Created by Christoph on 4/20/26.
//

import Foundation
import Bark
import os

extension BarkWalletFFI {
    
    // MARK: - Server Connection
    
    /// Attempts to establish connection to the Ark server
    /// This should be called after wallet is opened and before operations requiring server access
    /// - Returns: `true` if connection established, `false` otherwise
    @discardableResult
    func ensureServerConnection() async -> Bool {
        guard let wallet = wallet else {
            Self.logger.warning("[ensureServerConnection] No wallet - cannot connect")
            return false
        }
        
        Self.logger.debug("[ensureServerConnection] Attempting to establish server connection, Target server: \(self.config.serverAddress)")
        
        // Strategy 1: Try to fetch ArkInfo (this requires server connection)
        // Note: arkInfo() returns ArkInfo? (optional), doesn't throw
        if let arkInfo = await wallet.arkInfo() {
            Self.logger.info("[ensureServerConnection] Server connection verified, Round interval: \(arkInfo.roundIntervalSecs)s")
            return true
        } else {
            Self.logger.error("[ensureServerConnection] Cannot fetch ArkInfo (returns nil)")
            Self.logger.debug("[ensureServerConnection] Investigating if wallet needs explicit connection...")
            
            // TODO: Check Rust FFI documentation for:
            // - wallet.connect()
            // - wallet.sync()
            // - wallet.refreshServerInfo()
            // Or any method that establishes connection
            
            return false
        }
    }
    
    /// Polls for server connection at regular intervals until connected or timeout
    /// - Parameters:
    ///   - intervalSeconds: How often to check (default: 1 second)
    ///   - timeoutSeconds: Maximum time to wait (default: 20 seconds)
    /// - Returns: `true` if connection established, `false` if timeout reached
    @discardableResult
    func waitForServerConnection(intervalSeconds: TimeInterval = 1.0, timeoutSeconds: TimeInterval = 20.0) async -> Bool {
        guard let wallet = wallet else {
            Self.logger.warning("[waitForServerConnection] No wallet - cannot connect")
            return false
        }
        
        let startTime = Date()
        var attemptCount = 0
        
        Self.logger.debug("[waitForServerConnection] Starting connection polling, Check interval: \(intervalSeconds)s, Timeout: \(timeoutSeconds)s, Target server: \(self.config.serverAddress)")
        
        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            attemptCount += 1
            let elapsed = Date().timeIntervalSince(startTime)
            
            Self.logger.debug("[waitForServerConnection] Attempt #\(attemptCount) (elapsed: \(String(format: "%.1f", elapsed))s)")
            
            // Try to fetch ArkInfo to check connection
            if let arkInfo = await wallet.arkInfo() {
                let totalTime = Date().timeIntervalSince(startTime)
                Self.logger.info("[waitForServerConnection] Connection established, Total time: \(String(format: "%.2f", totalTime))s, Attempts: \(attemptCount), Round interval: \(arkInfo.roundIntervalSecs)s, VTXO expiry: \(arkInfo.vtxoExpiryDelta) blocks")
                return true
            }
            
            // Wait before next attempt
            Self.logger.debug("No connection yet, waiting \(intervalSeconds)s before retry...")
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
        }
        
        // Timeout reached
        let totalTime = Date().timeIntervalSince(startTime)
        Self.logger.error("[waitForServerConnection] Timeout reached after \(String(format: "%.2f", totalTime))s, Total attempts: \(attemptCount), Server may be unreachable or wallet needs explicit connection step")
        
        return false
    }
    
    // MARK: - Sync Operations
    
    // DIAGNOSTIC: Test basic connectivity to the server
    private func testServerConnectivity() async {
        guard let url = URL(string: config.serverAddress) else {
            Self.logger.debug("[DIAGNOSTIC] Invalid server URL")
            return
        }
        
        Self.logger.debug("[DIAGNOSTIC] Testing connection to: \(url.absoluteString)")
        
        do {
            var request = URLRequest(url: url, timeoutInterval: 5.0)
            request.httpMethod = "HEAD"
            
            let startTime = Date()
            let (_, response) = try await URLSession.shared.data(for: request)
            let endTime = Date()
            
            if let httpResponse = response as? HTTPURLResponse {
                Self.logger.debug("[DIAGNOSTIC] Server response: Status Code: \(httpResponse.statusCode), Response Time: \(endTime.timeIntervalSince(startTime)) seconds, Headers: \(httpResponse.allHeaderFields)")
            }
        } catch {
            Self.logger.debug("[DIAGNOSTIC] Server connectivity test failed: \(error), Error type: \(type(of: error)), Error description: \(error.localizedDescription)")
        }
    }
    
    func sync() async throws {
        // Synchronize wallet state with the ASP server
        
        if isPreview {
            Self.logger.info("Mock: Synced wallet (preview mode)")
            return
        }
        
        // Ensure wallet is initialized
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Syncing wallet with ASP server...")
        
        do {
            // Sync the onchain wallet if available (non-fatal if it fails)
            if let onchainWallet = onchainWallet {
                do {
                    _ = try await onchainWallet.sync()
                    Self.logger.info("Onchain wallet synced successfully")
                } catch {
                    // Don't crash the app if onchain sync fails
                    // This can happen if Esplora is unreachable or returns unexpected data
                    Self.logger.warning("Onchain wallet sync failed (non-fatal): \(error), Continuing with Ark wallet sync...")
                }
            }
            
            // Call FFI sync method
            _ = try await wallet.sync()
            
            Self.logger.info("Wallet synced successfully")
            
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error syncing wallet: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to sync wallet: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error syncing wallet: \(error)")
            throw error
        }
    }
    
    // MARK: - Server Connection (New in FFI)
    
    func refreshServer() async throws {
        // Refresh the Ark server connection
        
        if isPreview {
            return
        }
        
        guard let wallet = wallet else {
            throw BarkWalletFFIError.walletNotInitialized
        }
        
        Self.logger.debug("Refreshing server connection via FFI...")
        
        do {
            try await wallet.refreshServer()
            Self.logger.info("Server connection refreshed")
        } catch let error as Bark.Error {
            Self.logger.error("FFI Error refreshing server: \(error)")
            throw BarkWalletFFIError.configurationError("Failed to refresh server: \(error.localizedDescription)")
        } catch {
            Self.logger.error("Error refreshing server: \(error)")
            throw error
        }
    }
}
