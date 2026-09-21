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

/// Outcome of a background relay auth pass, mapped by each wake source to
/// its own completion contract: `setTaskCompleted(success:)` for BGTasks
/// (`nothingToDo` counts as success), `UIBackgroundFetchResult` for the
/// `mailbox_auth_refresh` wake push (`.newData`/`.noData`/`.failed`).
enum RelayAuthRefreshOutcome: Sendable {
    /// A fresh authorization was minted and registered with the relay
    case refreshed
    /// Nothing needed doing: notifications disabled, no wallet, or a wake
    /// for a mailbox this device no longer holds
    case nothingToDo
    /// The pass couldn't register (keychain locked, wallet open or
    /// registration failure) - report failure so the wake chain retries
    case failed
}

extension WalletManager {

    // MARK: - Push Notification Registration

    /// Register device for push notifications with the relay server
    /// Called automatically after wallet initialization and when APNs token is received
    /// Requires valid APNs token and wallet to be initialized
    func registerForPushNotifications(trigger: RelayRegistrationTrigger = .foreground) async {
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

        _ = await mintAndRegisterWithRelay(trigger: trigger)
    }

    /// Date the BGTask fallback should be scheduled at (midpoint of the
    /// token's remaining life), if a registration is active. Drives the
    /// BGTask request date; the in-process timer keeps its own tighter
    /// expiry-minus-buffer deadline inside RelayRegistrationService.
    var relayAuthBackgroundRefreshDate: Date? {
        relayRegistrationService?.backgroundRefreshDate
    }

    /// Read-only registration state for the X-Ray background activity header
    /// (this session's knowledge only; history lives in the event journal).
    var relayAuthExpiry: Date? {
        relayRegistrationService?.authorizationExpiresAt
    }

    /// When the in-process timer will next re-mint, if a registration is active.
    var relayAuthNextForegroundRefresh: Date? {
        relayRegistrationService?.nextRefreshDate
    }

    /// Asks the relay what it currently holds for this wallet's mailbox
    /// (X-Ray cross-check row). Returns nil when the wallet or relay service
    /// isn't available; throws on network/decode failure.
    func fetchRelayRegistrations() async throws -> RelayRegistrationsResponse? {
        guard let wallet, let relayService = relayRegistrationService else { return nil }
        let mailboxId = try wallet.mailboxIdentifier()
        return try await relayService.fetchRegistrations(mailboxId: mailboxId)
    }

    /// Background-wake variant of `registerForPushNotifications()`: does the
    /// minimum to keep the relay authorization fresh from a background launch —
    /// opens the wallet database if needed but skips full initialization
    /// (refresh pipeline, service startup, UI state).
    /// - Parameters:
    ///   - expectedMailboxId: For wake pushes, the mailbox the relay sent the
    ///     wake for; a mismatch with the current wallet (wallet was replaced
    ///     on this device) makes the pass a no-op.
    ///   - trigger: What woke us, reported to the relay on registration.
    func refreshRelayAuthInBackground(
        expectedMailboxId: String? = nil,
        trigger: RelayRegistrationTrigger = .backgroundTask
    ) async -> RelayAuthRefreshOutcome {
        guard UserDefaults.standard.bool(forKey: "notifications_enabled") else {
            Self.logger.info("Background relay auth refresh: notifications disabled - nothing to do")
            return .nothingToDo
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
            return .nothingToDo
        case .unavailable(let osStatus):
            Self.logger.warning("Background relay auth refresh: keychain unavailable (OSStatus \(osStatus)) - retrying on a later wake")
            return .failed
        }

        // A background launch skips the UI flow that normally calls initialize().
        // Minting a mailbox authorization only needs the wallet database open,
        // not the full refresh pipeline - so open it directly.
        if !isInitialized, let ffiWallet = wallet as? BarkWalletFFI {
            guard await ffiWallet.openWalletIfNeeded() else {
                Self.logger.error("Background relay auth refresh: wallet failed to open")
                return .failed
            }
        }

        // A wake push names the mailbox it was sent for. If the wallet on this
        // device was replaced since that registration, the wake is stale -
        // unregister the orphaned pair instead of minting anything (the
        // current wallet's own refresh chain is unaffected)
        if let expectedMailboxId {
            guard let wallet else {
                Self.logger.warning("Background relay auth refresh: no wallet to compare mailbox id against")
                return .failed
            }
            do {
                let currentMailboxId = try wallet.mailboxIdentifier()
                guard RelayRegistrationService.isWakeForCurrentMailbox(
                    payloadMailboxId: expectedMailboxId,
                    currentMailboxId: currentMailboxId
                ) else {
                    Self.logger.notice("Background relay auth refresh: wake targets mailbox \(expectedMailboxId.prefix(8), privacy: .public)... but current wallet holds \(currentMailboxId.prefix(8), privacy: .public)... - unregistering stale mailbox")
                    return await unregisterStaleMailboxFromWake(staleMailboxId: expectedMailboxId)
                }
            } catch {
                Self.logger.error("Background relay auth refresh: failed to read mailbox id: \(error.localizedDescription)")
                return .failed
            }
        }

        // Clear the dedupe state so this registration isn't skipped as an
        // unchanged duplicate (mirrors what the in-process timer does before
        // calling onNeedsRefresh)
        relayRegistrationService?.forceRefresh()

        return await mintAndRegisterWithRelay(trigger: trigger) ? .refreshed : .failed
    }

    /// Cleans up the orphaned registration a stale wake names: the wallet on
    /// this device was replaced, nothing can renew that mailbox's token any
    /// more, and APNs never reports the device token invalid (the app is
    /// still installed) - so without this DELETE the relay keeps a dead
    /// worker and daily wakes alive forever. Deliberately does NOT mint,
    /// register, or touch the current wallet's registration state.
    /// - Returns: `.nothingToDo` on success or when unregistering is
    ///   impossible (no token/service); `.failed` on a request error, so the
    ///   relay's next scheduled wake retries the cleanup.
    private func unregisterStaleMailboxFromWake(staleMailboxId: String) async -> RelayAuthRefreshOutcome {
        guard let relayService = relayRegistrationService else {
            Self.logger.warning("Stale mailbox cleanup: no relay service available - skipping")
            return .nothingToDo
        }
        guard let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token"),
              !deviceToken.isEmpty else {
            Self.logger.warning("Stale mailbox cleanup: no APNs device token - skipping")
            return .nothingToDo
        }

        do {
            // The relay stores lowercased ids; DELETE matches exactly
            try await relayService.unregisterStaleMailbox(
                mailboxId: staleMailboxId.lowercased(),
                deviceToken: deviceToken
            )
            Self.logger.notice("Stale mailbox cleanup: unregistered \(staleMailboxId.prefix(8), privacy: .public)... from relay")
            BackgroundEventJournal.record(
                .staleMailboxUnregister,
                outcome: "success",
                trigger: RelayRegistrationTrigger.wakePush.rawValue
            )
            return .nothingToDo
        } catch {
            Self.logger.error("Stale mailbox cleanup: failed to unregister \(staleMailboxId.prefix(8), privacy: .public)...: \(error.localizedDescription)")
            BackgroundEventJournal.record(
                .staleMailboxUnregister,
                outcome: "failure",
                trigger: RelayRegistrationTrigger.wakePush.rawValue
            )
            return .failed
        }
    }

    /// Mints mailbox credentials and registers with the relay. Shared core of
    /// the foreground and background registration paths - callers own the
    /// gating (initialization, settings, keychain).
    private func mintAndRegisterWithRelay(trigger: RelayRegistrationTrigger) async -> Bool {
        // Launch double-fire dedupe (journal finding, 2026-09-18): the launch
        // flow and the APNs token observer both register within seconds, each
        // minting a new token the hash dedupe can't catch. Skip while the
        // registration is fresh; a changed device token or forceRefresh()
        // (timer/BGTask/wake-push paths) defeats freshness. Skips aren't
        // journaled - the journal records actual relay traffic only.
        let currentToken = UserDefaults.standard.string(forKey: "apns_device_token")
        if relayRegistrationService?.isRegistrationFresh(currentDeviceToken: currentToken) == true {
            Self.logger.info("Skipping relay registration (trigger: \(trigger.rawValue, privacy: .public)) - current registration is fresh")
            return true
        }

        let success = await mintAndRegisterWithRelayCore(trigger: trigger)
        BackgroundEventJournal.record(
            .relayRegistration,
            outcome: success ? "success" : "failure",
            trigger: trigger.rawValue
        )
        return success
    }

    private func mintAndRegisterWithRelayCore(trigger: RelayRegistrationTrigger) async -> Bool {
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
                apnsTopic: apnsTopic,
                trigger: trigger
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
