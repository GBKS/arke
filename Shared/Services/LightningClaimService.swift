//
//  LightningClaimService.swift
//  Ark wallet prototype
//
//  Service responsible for automatically claiming Lightning receives in the background
//

import Foundation
import SwiftUI
import Bark

/// Service responsible for automatically claiming pending Lightning receives in the background
/// 
/// This service runs a timer that periodically checks for pending Lightning receives and
/// automatically claims them. Once claimed, the Bark SDK creates Movement events which
/// trigger WalletNotificationService notifications, causing transactions to appear in the UI.
///
/// Lightning Receive Flow:
/// 1. User generates Lightning invoice
/// 2. External user pays the invoice → Payment sits in "pending" state
/// 3. Service detects pending receive (state == "htlcs-ready")
/// 4. Service auto-claims → SDK creates Movement → Notification fires → Transaction appears
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every 30 seconds (fast response for incoming payments)
/// - SDK-driven: No complex state tracking, just polls SDK
/// - Silent failures: Logs errors but doesn't interrupt user
/// - Debounced: Prevents overlapping claims with isClaiming flag
@MainActor
@Observable
class LightningClaimService {
    
    // MARK: - Configuration
    
    /// How often to check for pending Lightning receives (in seconds)
    /// Set to 30s for relatively quick response to incoming payments
    private let checkInterval: TimeInterval = 30
    
    // MARK: - State
    
    /// Whether the service is currently running
    private(set) var isRunning: Bool = false
    
    /// Whether a claim operation is currently in progress (prevents overlapping claims)
    private var isClaiming: Bool = false
    
    /// Last time receives were checked/claimed
    private(set) var lastCheckTime: Date?
    
    /// Last error encountered (for debugging)
    private(set) var lastError: String?
    
    /// Count of receives claimed in last operation
    private(set) var lastClaimCount: Int = 0
    
    // MARK: - Dependencies
    
    private let wallet: BarkWalletProtocol
    private weak var walletManager: WalletManager?
    
    // MARK: - Timer
    
    private var timer: Timer?
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet
    }
    
    /// Set the wallet manager reference (needed for cache invalidation)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }
    
    // MARK: - Lifecycle
    
    /// Start the Lightning claim service
    func start() {
        guard !isRunning else {
            print("⚠️ [LightningClaim] Service already running")
            return
        }
        
        print("▶️ [LightningClaim] Starting service (check interval: \(Int(checkInterval))s)")
        isRunning = true
        
        // Run initial check immediately
        Task {
            await checkAndClaimReceives()
        }
        
        // Schedule timer for periodic checks with tolerance for battery optimization
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndClaimReceives()
            }
        }
        timer?.tolerance = 5 // Allow 5 second variance for battery optimization
    }
    
    /// Stop the Lightning claim service
    func stop() {
        guard isRunning else { return }
        
        print("⏹️ [LightningClaim] Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            print("⚠️ [LightningClaim] Cannot trigger check - service not running")
            return
        }
        
        print("🔄 [LightningClaim] Manual check triggered")
        Task {
            await checkAndClaimReceives()
        }
    }
    
    // MARK: - Lightning Claim Logic
    
    /// Check for pending Lightning receives and claim them if needed
    private func checkAndClaimReceives() async {
        print("🔍 [LightningClaim] Check started...")
        
        // Prevent overlapping claims
        guard !isClaiming else {
            print("⏭️ [LightningClaim] Claim already in progress, skipping")
            return
        }
        
        isClaiming = true
        defer { isClaiming = false }
        
        let startTime = Date()
        
        do {
            // Step 1: Sync wallet state with server to discover new Lightning receives
            print("   [LightningClaim] Syncing wallet state with server...")
            try await wallet.sync()
            print("   [LightningClaim] Sync complete")
            
            // Step 2: Quick check - get claimable balance
            print("   [LightningClaim] Checking claimable balance...")
            let claimableBalance = try await wallet.claimableLightningReceiveBalanceSats()
            print("   [LightningClaim] Claimable balance: \(claimableBalance) sats")
            
            // Step 3: Always get detailed list to see what's there
            let pendingReceives = try await wallet.pendingLightningReceives()
            print("   [LightningClaim] Found \(pendingReceives.count) pending receive(s)")
            
            // Log details of all pending receives for debugging
            for (index, receive) in pendingReceives.enumerated() {
                print("   [LightningClaim] Receive #\(index + 1):")
                print("      Amount: \(receive.amountSats) sats")
                print("      State: \(receive.state)")
                print("      Payment Hash: \(String(receive.paymentHash.prefix(16)))...")
            }
            
            if claimableBalance == 0 {
                // No receives to claim according to balance check
                print("   [LightningClaim] Claimable balance is 0 - nothing to claim")
                lastCheckTime = Date()
                lastError = nil
                lastClaimCount = 0
                return
            }
            
            print("🔍 [LightningClaim] Found \(claimableBalance) sats to claim")
            
            let claimableReceives = pendingReceives.filter { $0.state == "htlcs-ready" }

            if claimableReceives.isEmpty {
                print("⚠️ [LightningClaim] Claimable balance reported but no claimable receives found")
                lastCheckTime = Date()
                lastError = nil
                lastClaimCount = 0
                return
            }
            
            print("📋 [LightningClaim] Found \(claimableReceives.count) receive(s) ready to claim:")
            for receive in claimableReceives {
                print("   • \(receive.amountSats) sats - Payment hash: \(String(receive.paymentHash.prefix(16)))...")
            }
            
            // Step 4: Claim all pending receives
            print("💰 [LightningClaim] Claiming all pending receives...")
            _ = try await wallet.claimLightningInvoice(invoice: "") // Claims all, invoice param unused
            print("   ✅ Claimed \(claimableReceives.count) receive(s)")
            
            // Step 5: Refresh balances and transactions
            // Note: WalletNotificationService will receive Movement notifications automatically
            // But we still refresh to ensure UI is up to date
            await walletManager?.refreshBalances()
            print("   ✅ Refreshed balances")
            
            // Success
            lastCheckTime = Date()
            lastError = nil
            lastClaimCount = claimableReceives.count
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ [LightningClaim] Claimed \(claimableReceives.count) receive(s) totaling \(claimableBalance) sats in \(String(format: "%.2f", duration))s")
            
        } catch {
            // Log error but don't stop the service
            let errorMessage = error.localizedDescription
            print("❌ [LightningClaim] Error during check: \(errorMessage)")
            lastError = errorMessage
            lastCheckTime = Date()
            
            // Continue running despite errors - will retry on next interval
        }
    }
    
    // MARK: - Manual Operations
    
    /// Manually claim receives (exposed for UI triggers like pull-to-refresh)
    func claimReceivesManually() async throws {
        print("🔄 [LightningClaim] Manual claim requested")
        
        let claimableBalance = try await wallet.claimableLightningReceiveBalanceSats()
        guard claimableBalance > 0 else {
            print("   ℹ️ No Lightning receives to claim")
            return
        }
        
        let pendingReceives = try await wallet.pendingLightningReceives()
        let claimableReceives = pendingReceives.filter { $0.state == "htlcs-ready" }
        
        guard !claimableReceives.isEmpty else {
            print("   ⚠️ Claimable balance reported but no claimable receives found")
            return
        }

        _ = try await wallet.claimLightningInvoice(invoice: "") // Claims all
        await walletManager?.refreshBalances()
        
        print("   ✅ Manually claimed \(claimableReceives.count) receive(s) totaling \(claimableBalance) sats")
    }
}
