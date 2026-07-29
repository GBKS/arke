//
//  WalletManager+Notifications.swift
//  Arké
//
//  Push notification registration and handling (iOS only)
//  Registers device with relay server for mailbox update notifications via APNs
//

import Foundation
import OSLog
import ArkeUI

#if os(iOS)
extension WalletManager {
    
    // MARK: - Push Notification Registration
    
    /// Register device for push notifications with the relay server
    /// Called automatically after wallet initialization and when APNs token is received
    /// Requires valid APNs token and wallet to be initialized
    func registerForPushNotifications() async {
        // Ensure wallet is initialized before attempting registration
        guard isInitialized else {
            Self.logger.info("Cannot register for push - wallet not yet initialized (normal during app startup; registration will be retried after initialization)")
            return
        }

        // Check if user has enabled notifications in settings
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
        guard notificationsEnabled else {
            Self.logger.warning("Notifications disabled in settings")
            return
        }

        _ = await mintAndRegisterWithRelay()
    }

    /// Deadline for the next relay auth refresh (expiry minus buffer), if a
    /// registration is active. Drives the BGTask request date.
    var relayAuthNextRefreshDate: Date? {
        relayRegistrationService?.nextRefreshDate
    }

    /// Background-wake variant of `registerForPushNotifications()`: does the
    /// minimum to keep the relay authorization fresh from a BGTask launch —
    /// opens the wallet database if needed but skips full initialization
    /// (refresh pipeline, service startup, UI state). Returns whether the pass
    /// succeeded, for `setTaskCompleted(success:)`.
    func refreshRelayAuthInBackground() async -> Bool {
        guard UserDefaults.standard.bool(forKey: "notifications_enabled") else {
            Self.logger.info("Background relay auth refresh: notifications disabled - nothing to do")
            return true
        }

        // Keychain-unavailable (device between reboot and first unlock) is a
        // normal branch: report failure so the wake chain retries, and never
        // treat it as "no wallet" (same failure mode the startup detection
        // hardening handles - see Shared/Docs/Initialization/)
        switch SecurityService.mnemonicKeychainStatus() {
        case .found:
            break
        case .notFound:
            Self.logger.info("Background relay auth refresh: no wallet - nothing to do")
            return true
        case .unavailable(let osStatus):
            Self.logger.warning("Background relay auth refresh: keychain unavailable (OSStatus \(osStatus)) - retrying on a later wake")
            return false
        }

        // A BGTask launch skips the UI flow that normally calls initialize().
        // Minting a mailbox authorization only needs the wallet database open,
        // not the full refresh pipeline - so open it directly.
        if !isInitialized, let ffiWallet = wallet as? BarkWalletFFI {
            guard await ffiWallet.openWalletIfNeeded() else {
                Self.logger.error("Background relay auth refresh: wallet failed to open")
                return false
            }
        }

        // Clear the dedupe state so this registration isn't skipped as an
        // unchanged duplicate (mirrors what the in-process timer does before
        // calling onNeedsRefresh)
        relayRegistrationService?.forceRefresh()

        return await mintAndRegisterWithRelay()
    }

    /// Mints mailbox credentials and registers with the relay. Shared core of
    /// the foreground and background registration paths - callers own the
    /// gating (initialization, settings, keychain).
    private func mintAndRegisterWithRelay() async -> Bool {
        guard let wallet = wallet,
              let relayService = relayRegistrationService else {
            Self.logger.warning("Cannot register for push - wallet or relay service not available")
            return false
        }

        // Get APNs token from UserDefaults (set by AppDelegate)
        guard let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token"),
              !deviceToken.isEmpty else {
            Self.logger.warning("No APNs device token available")
            return false
        }

        do {
            // Get mailbox credentials from wallet
            let mailboxId = try wallet.mailboxIdentifier()
            let authorizationHex = try wallet.mailboxAuthorization()

            // Get Ark server URL from config
            let config = try await wallet.getConfig()
            let arkAddr = config.ark
            guard !arkAddr.isEmpty else {
                Self.logger.error("No Ark server URL in config")
                return false
            }

            // Get bundle identifier for APNs topic
            let apnsTopic = Bundle.main.bundleIdentifier ?? "com.arke.wallet"

            // Debug: Log registration parameters (redact sensitive auth)
            Self.logger.debug("Registration params: mailboxId: \(mailboxId.prefix(8))... (len: \(mailboxId.count)), authorizationHex: \(authorizationHex.prefix(8))... (len: \(authorizationHex.count)), arkAddr: \(arkAddr), deviceToken: \(deviceToken.prefix(8))... (len: \(deviceToken.count)), apnsTopic: \(apnsTopic)")

            // Register with relay
            try await relayService.registerDevice(
                mailboxId: mailboxId,
                authorizationHex: authorizationHex,
                arkAddr: arkAddr,
                deviceToken: deviceToken,
                apnsTopic: apnsTopic
            )

            Self.logger.info("Successfully registered for push notifications")
            return true
        } catch {
            Self.logger.error("Failed to register for push: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Unregister device from push notifications with the relay server
    /// Should be called when user logs out or deletes wallet
    func unregisterFromPushNotifications() async {
        guard let wallet = wallet,
              let relayService = relayRegistrationService else {
            return
        }
        
        guard let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token"),
              !deviceToken.isEmpty else {
            return
        }
        
        do {
            let mailboxId = try wallet.mailboxIdentifier()
            
            try await relayService.unregisterDevice(
                mailboxId: mailboxId,
                deviceToken: deviceToken
            )
            
            Self.logger.info("Successfully unregistered from push notifications")
        } catch {
            Self.logger.error("Failed to unregister from push: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notification Observers
    
    /// Set up observer for mailbox update notifications from APNs
    /// Called automatically during WalletManager initialization
    /// Triggers wallet refresh when mailbox updates are received
    func setupMailboxNotificationObserver() {
        Self.logger.debug("Setting up mailbox update observer...")
        NotificationCenter.default.addObserver(
            forName: .mailboxUpdateReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                Self.logger.info("Mailbox update notification received, refreshing... (dataVersion: \(self.dataVersion))")
                await self.refresh()
                Self.logger.info("Mailbox refresh complete. New dataVersion: \(self.dataVersion)")
            }
        }
    }
}
#endif
