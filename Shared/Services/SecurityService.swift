//
//  SecurityService.swift
//  Arké
//
//  Created by Christoph on 11/28/25.
//

import Foundation
import SwiftData
import CryptoKit
import LocalAuthentication
import Observation
import CommonCrypto
import OSLog

@MainActor
@Observable
class SecurityService {
    // MARK: - Logging
    
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "SecurityService")
    
    // MARK: - Published Properties
    
    /// Current wallet state for cross-device detection
    var walletState: WalletState = .unknown

    /// Whether the last wallet state detection reached a definitive keychain answer.
    /// False means the keychain was unavailable (e.g. protected data not ready) and the
    /// returned state is low-confidence — callers should re-run detection when the
    /// keychain becomes readable (foreground, protectedDataDidBecomeAvailable).
    private(set) var lastDetectionWasDefinitive: Bool = true
    
    /// Error message for security operations
    var error: String?
    
    /// Loading state
    var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    private var modelContext: ModelContext?
    private let taskManager: TaskDeduplicationManager
    
    // MARK: - Constants
    
    private let keychainService = "com.arke.wallet"
    private let mnemonicAccount = "mnemonic"
    private let hashSalt = "com.arke.mnemonic.hash.v1"
    private let pbkdf2Iterations = 100_000
    private let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Static Lightweight Detection

    /// Lightweight synchronous check for wallet existence (no dependencies required)
    /// Use this for early app initialization before full service stack is available
    ///
    /// Distinguishes "the item definitively does not exist" from "the keychain could not
    /// be read right now" (e.g. errSecInteractionNotAllowed when protected data is not yet
    /// available at cold launch / prewarming). Only `.notFound` may ever route to onboarding.
    nonisolated static func mnemonicKeychainStatus() -> MnemonicKeychainStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arke.wallet",
            kSecAttrAccount as String: "mnemonic",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            logger.debug("Keychain mnemonic check: found")
            return .found
        case errSecItemNotFound:
            logger.info("Keychain mnemonic check: definitively not found (errSecItemNotFound)")
            return .notFound
        default:
            logger.warning("Keychain mnemonic check indeterminate: OSStatus \(status)")
            return .unavailable(status)
        }
    }
    
    // MARK: - Local Wallet Evidence

    /// UserDefaults key marking that a wallet was created or imported on this install.
    /// Used as a tiebreaker when the keychain is unreadable: a device that ran a wallet
    /// before must never be routed to onboarding on an indeterminate check.
    private nonisolated static let hasRunWalletLocallyKey = "com.arke.wallet.hasRunLocally"

    /// Records that a wallet demonstrably exists on this install
    nonisolated static func recordLocalWalletEvidence() {
        UserDefaults.standard.set(true, forKey: hasRunWalletLocallyKey)
    }

    /// Clears the local wallet evidence after deliberate wallet deletion
    nonisolated static func clearLocalWalletEvidence() {
        UserDefaults.standard.removeObject(forKey: hasRunWalletLocallyKey)
        logger.info("Cleared local wallet evidence")
    }

    // MARK: - Stale Wallet Directory

    /// UserDefaults key set when a deletion completed account-side but the bark
    /// directory could not be removed (`DeleteWalletSettingView`, route-anyway,
    /// DECIDED 2026-10-15). The leftover database belongs to a wallet that no
    /// longer exists: it is not evidence of a wallet, and the next create or
    /// import removes it first — bark refuses to open a database for a
    /// different phrase ("incorrect mnemonic"), so without this an import of
    /// another phrase would fail on every attempt (review finding 2026-10-15,
    /// `Wallet_Deletion_Partial_Failure.md` §10).
    private nonisolated static let staleWalletDirectoryKey = "com.arke.wallet.staleWalletDirectory"

    nonisolated static func recordStaleWalletDirectory() {
        UserDefaults.standard.set(true, forKey: staleWalletDirectoryKey)
        logger.error("Wallet directory could not be removed after deletion — marked stale for the next create or import")
    }

    nonisolated static func hasStaleWalletDirectory() -> Bool {
        UserDefaults.standard.bool(forKey: staleWalletDirectoryKey)
    }

    nonisolated static func clearStaleWalletDirectory() {
        UserDefaults.standard.removeObject(forKey: staleWalletDirectoryKey)
    }

    /// True if this install shows signs of having run a wallet: the UserDefaults
    /// breadcrumb, or the bark database on disk (covers installs predating the
    /// flag). A directory marked stale after a failed deletion teardown does not
    /// count — the keychain-unreadable detection branch would otherwise route a
    /// wiped install back into the wallet UI on it.
    nonisolated static func hasLocalWalletEvidence() -> Bool {
        if UserDefaults.standard.bool(forKey: hasRunWalletLocallyKey) {
            return true
        }
        if hasStaleWalletDirectory() {
            return false
        }
        return localWalletDatabaseExists()
    }

    /// Checks for the bark wallet database on disk.
    /// Path mirrors `BarkWalletFFI.getWalletDirectory()` (also duplicated in
    /// `WalletManager.getWalletDirectory()`); no directories are created here.
    private nonisolated static func localWalletDatabaseExists() -> Bool {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }

        let walletDirectory = appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GBKS.Arke")
            .appendingPathComponent("bark-data-ffi")

        // Check the current (bark 0.11+) name first, then the pre-0.11 legacy name
        return [WalletBackupService.currentDatabaseFileName, WalletBackupService.legacyDatabaseFileName]
            .contains { name in
                FileManager.default.fileExists(atPath: walletDirectory.appendingPathComponent(name).path)
            }
    }

    // MARK: - Wallet State Detection

    /// Detects if user has a wallet on another device
    /// Does NOT register the device - coordinator should call device registration separately
    func detectWalletState() async -> WalletState {
        return await taskManager.execute(key: "detectWalletState") {
            return await self.performWalletStateDetection()
        }
    }
    
    /// Checks if current device is primary, returns walletActiveElsewhere state if not
    private func checkDevicePrimaryStatus(modelContext: ModelContext) -> WalletState? {
        do {
            // Get the device ID from keychain
            guard let deviceIdData = getDeviceIdFromKeychain(),
                  let deviceId = String(data: deviceIdData, encoding: .utf8) else {
                Self.logger.warning("⚠️ Could not get device ID from keychain")
                return nil
            }

            // Get the current wallet hash
            guard let currentWalletHash = getUbiquitousHash() else {
                Self.logger.warning("⚠️ Could not get current wallet hash")
                return nil
            }
            
            // Fetch devices for the CURRENT wallet only
            let descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate<DeviceRegistration> { device in
                    device.walletHash == currentWalletHash && device.isActive
                }
            )
            let walletDevices = try modelContext.fetch(descriptor)
            
            // Find current device by matching deviceId
            let currentDevice = walletDevices.first { $0.deviceId == deviceId }
            
            if let current = currentDevice {
                if !current.isPrimaryDevice {
                    // Get the primary device name
                    let primaryDevice = walletDevices.first { $0.isPrimaryDevice }
                    let primaryDeviceName = primaryDevice?.deviceName ?? "Another Device"
                    
                    Self.logger.info("⚠️ Wallet exists locally but device is not primary. Primary device: \(primaryDeviceName)")
                    return .walletActiveElsewhere(deviceName: primaryDeviceName)
                }
            }
        } catch {
            Self.logger.warning("⚠️ Failed to check device primary status: \(error)")
            // Continue with normal flow if check fails
        }
        
        return nil
    }
    
    /// Gets the device ID from keychain
    private func getDeviceIdFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.arke.device",
            kSecAttrAccount as String: "deviceId",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        
        return nil
    }
    
    /// Best-effort lookup of the primary device's name for user-facing routing
    /// states.
    ///
    /// Returns nil when the account has no primary device, when the registry
    /// can't be read, or when the record carries an empty name — all three are
    /// "we cannot name it", and the caller must say so rather than show a
    /// placeholder. The previous "Another Device" fallback was injected into
    /// localized copy as a hardcoded English string and asserted a fact (some
    /// other device holds the wallet) that is false for a zero-primary account.
    private func lookupPrimaryDeviceName(walletHash: String) async -> String? {
        guard modelContext != nil else { return nil }

        do {
            let deviceService = ServiceContainer.shared.deviceRegistrationService
            let primaryDevice = try await deviceService.getPrimaryDevice(walletHash: walletHash)
            return Self.displayableDeviceName(primaryDevice?.deviceName)
        } catch {
            Self.logger.warning("⚠️ Failed to look up primary device: \(error)")
            return nil
        }
    }

    /// A device name is displayable only if it exists and isn't blank — registry
    /// rows default `deviceName` to `""`, which would render as an empty gap in
    /// the middle of a sentence.
    private static func displayableDeviceName(_ name: String?) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return name
    }

    /// Internal method that performs the actual wallet state detection
    private func performWalletStateDetection() async -> WalletState {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            Self.logger.info("⏱️ Wallet state detection took \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime), privacy: .public)s")
        }
        // 0. The link record decides whether this install may adopt the
        // account's wallet at all (Device_Linking.md §12.1, contract rule 28).
        // The keychain is resolved first because the route needs it; the
        // retrying resolver turns a transiently unreadable keychain into
        // "unknown", never into "no wallet".
        let mnemonicStatus = await resolveMnemonicStatus()
        let accountHash = getUbiquitousHash()
        let seedFound = mnemonicStatus == .found
        var seedUnreadable = false
        if case .unavailable = mnemonicStatus { seedUnreadable = true }
        let ownRow = await ServiceContainer.shared.deviceRegistrationService.ownRowEvidence(fallbackContainer: nil)
        var route = DeviceLinkStore.launchRoute(
            record: DeviceLinkStore.record(),
            left: DeviceLinkStore.left(),
            accountHash: accountHash,
            seedFound: seedFound,
            seedUnreadable: seedUnreadable,
            ownRow: ownRow
        )
        // Only the mismatch needs to know whether an iCloud account is
        // present (deleted elsewhere vs signed out); ask CloudKit only then
        if case .awaitingLink(.walletMismatch) = route {
            let presence = await ICloudAccountStatus.presence()
            let identityMatches = ICloudAccountIdentity.matches(stored: DeviceLinkStore.accountToken())
            route = DeviceLinkStore.launchRoute(
                record: DeviceLinkStore.record(),
                left: DeviceLinkStore.left(),
                accountHash: accountHash,
                seedFound: seedFound,
                seedUnreadable: seedUnreadable,
                ownRow: ownRow,
                iCloudAccount: presence,
                accountIdentityMatches: identityMatches
            )
        }
        switch route {
        case .awaitingLink(let reason):
            // A keychain or registry that could not be read is re-checked when
            // protected data becomes available; every other reason is settled
            lastDetectionWasDefinitive = !seedUnreadable && ownRow != .unavailable
            Self.logger.notice("🔗 Account wallet awaiting link on this install (\(String(describing: reason), privacy: .public))")
            return .accountWalletAwaitingLink(reason: reason)
        case .selfHeal:
            // An install from before the link record existed: its own
            // registry row is the proof it linked. Write the record silently.
            let hash = accountHash ?? (try? loadMnemonic()).flatMap { $0 }.map(hashMnemonic)
            if let hash {
                DeviceLinkStore.recordLink(walletHash: hash, replacingExisting: true)
                Self.logger.notice("🔗 Link record written for an existing install (own registry row present)")
            }
        case .noAccountWallet:
            // The breadcrumb must not outlive the wallet it remembers: left
            // behind after a wipe elsewhere it would refuse creation forever.
            // But a blank KVS and a seedless keychain are definitive only
            // with an iCloud account present; signed out, nothing is known,
            // and clearing would let Create run while signed out, to collide
            // with the account's seed on sign-in (adversarial pass
            // 2026-11-16, F5). The status call runs only with a breadcrumb.
            if DeviceLinkStore.leftBreadcrumbIsStale(left: DeviceLinkStore.left(), accountHash: accountHash, seedFound: seedFound, seedUnreadable: seedUnreadable) {
                if await ICloudAccountStatus.presence() == .absent {
                    Self.logger.notice("🔗 Left breadcrumb kept: signed out of iCloud, the account wallet's fate is unknown")
                } else {
                    DeviceLinkStore.clearLeft()
                    Self.logger.notice("🔗 Left breadcrumb cleared: the account wallet it remembered is gone")
                }
            }
        case .linked:
            // Records from before the identity was stored learn it on a
            // healthy launch, so a later mismatch can be told apart
            if DeviceLinkStore.accountToken() == nil {
                DeviceLinkStore.recordAccountToken(ICloudAccountIdentity.currentTokenData())
            }
        }

        Self.logger.debug("Wallet state detection: checking local keychain...")

        switch mnemonicStatus {
        case .found:
            lastDetectionWasDefinitive = true

            // The keychain is provably readable at this point — migrate the mnemonic
            // to AfterFirstUnlock if it still has the old accessibility class
            // (background wakes on a locked device need it; Background_Execution.md).
            _ = Self.migrateMnemonicAccessibilityIfNeeded()

            // Self-healing breadcrumb for installs that predate the evidence flag
            Self.recordLocalWalletEvidence()

            Self.logger.debug("Wallet state detection: mnemonic found, checking device primary status...")

            // 1.5. Check if this device is the primary device
            // If wallet exists but device is not primary, return walletActiveElsewhere
            if let modelContext = self.modelContext {
                if let state = self.checkDevicePrimaryStatus(modelContext: modelContext) {
                    return state
                }
            }

            return .walletWithSeed

        case .unavailable(let osStatus):
            // Retries exhausted and the keychain still can't be read: the answer is
            // unknown, not "no wallet". Never route to onboarding from here.
            lastDetectionWasDefinitive = false

            let hasCloudHash = self.getUbiquitousHash() != nil
            let hasLocalEvidence = Self.hasLocalWalletEvidence()

            if hasCloudHash || hasLocalEvidence {
                // Some signal says a wallet exists — assume the seed is present too
                // (low confidence). Callers observing `lastDetectionWasDefinitive ==
                // false` should re-detect once the keychain becomes readable.
                Self.logger.error("Keychain unavailable after retries (OSStatus \(osStatus)) but wallet signals present (kvsHash=\(hasCloudHash), localEvidence=\(hasLocalEvidence)) — assuming wallet exists (low confidence)")
                return .walletWithSeed
            }

            // No corroborating signal anywhere: treat as fresh install. Wallet creation
            // will surface keychain errors on its own if the keychain is truly broken.
            Self.logger.error("Keychain unavailable after retries (OSStatus \(osStatus)), no KVS hash, no local evidence — treating as fresh install (low confidence)")
            return .noWallet

        case .notFound:
            lastDetectionWasDefinitive = true
        }

        Self.logger.debug("Wallet state detection: no local mnemonic, checking iCloud KVS...")

        // 2. Check NSUbiquitousKeyValueStore for synced hash
        // This is the single source of truth for cross-device wallet detection
        if let cloudWalletHash = self.getUbiquitousHash() {
            // Wallet exists on this iCloud account but the seed hasn't reached this
            // device (iCloud Keychain off or lagging). Route into read-only mode; the
            // caller registers this device and initializes with forceReadOnly. The
            // sheet explains the missing key (ReadOnlyReason.seedNotSynced) and offers
            // recovery phrase entry. Registration status doesn't change the routing,
            // only the primary-device name we can show.
            let primaryDeviceName = await lookupPrimaryDeviceName(walletHash: cloudWalletHash)

            Self.logger.info("📱 Wallet hash found but no local seed - entering read-only mode (seed not synced, primary: \(primaryDeviceName ?? "none registered"))")
            return .walletActiveElsewhere(deviceName: primaryDeviceName)
        }
        
        Self.logger.debug("Wallet state detection: no wallet found anywhere")

        return .noWallet
    }
    
    // MARK: - Mnemonic Storage (iCloud Keychain)
    
    /// Saves mnemonic to keychain and syncs via iCloud Keychain
    /// Note: Device registration should be done by coordinator after this call
    ///
    /// The item is always synchronizable and never ACL-protected (Decision B in
    /// Startup_Wallet_Detection_Plan.md): a keychain ACL would block iCloud Keychain
    /// sync (the basis of the multi-device story) and break the existence checks that
    /// route the launch screen. Biometric gating happens at the app level via
    /// `authenticateUser()` instead.
    ///
    /// Uses update-then-add so a failed write never deletes the existing item.
    func saveMnemonic(_ mnemonic: String) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let data = mnemonic.data(using: .utf8) else {
            throw WalletError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrSynchronizable as String: true  // Sync via iCloud Keychain
        ]

        // kSecAttrAccessibleAfterFirstUnlock so background wakes on a locked device can
        // open the wallet (Background_Execution.md Phase 1). Not a ThisDeviceOnly class,
        // so iCloud Keychain sync keeps working.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let writeStartTime = CFAbsoluteTimeGetCurrent()
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            let addQuery = baseQuery.merging(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            Self.logger.error("saveMnemonic failed with OSStatus \(status) - existing item (if any) left untouched")
            throw WalletError.keychainError(status)
        }
        let writeTime = CFAbsoluteTimeGetCurrent() - writeStartTime
        Self.logger.info("⏱️ [PROFILE] Keychain write took \(String(format: "%.3f", writeTime))s")

        // Breadcrumb: this install has a wallet (covers both create and import)
        Self.recordLocalWalletEvidence()
        
        // Save hash to ubiquitous store for cross-device wallet detection
        let hashStartTime = CFAbsoluteTimeGetCurrent()
        saveHashToUbiquitousStore(mnemonic)
        let hashTime = CFAbsoluteTimeGetCurrent() - hashStartTime
        Self.logger.info("⏱️ [PROFILE] Hash generation and ubiquitous store save took \(String(format: "%.3f", hashTime))s")
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("⏱️ [PROFILE] Total saveMnemonic() took \(String(format: "%.3f", totalTime))s")
        
        #if DEBUG
        print("✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store")
        print("   ℹ️  Coordinator should call DeviceRegistrationService.registerCurrentDevice() next")
        #endif
    }
    
    // MARK: - Keychain Accessibility Migration

    /// Migrates the mnemonic keychain item from `WhenUnlocked` to `AfterFirstUnlock`
    /// so background wakes on a locked device can open the wallet
    /// (Background_Execution.md, Phase 1). Idempotent; call whenever the keychain is
    /// known to be readable. `.keychainUnavailable` means "retry on a later launch",
    /// never "give up".
    nonisolated static func migrateMnemonicAccessibilityIfNeeded() -> KeychainAccessibilityMigrationResult {
        return migrateItemToAfterFirstUnlock(service: "com.arke.wallet", account: "mnemonic")
    }

    /// Core of the accessibility migration, parametrized so tests can run it against a
    /// scratch item instead of the real mnemonic, and so the non-synchronizable
    /// device-ID item can move to `AfterFirstUnlockThisDeviceOnly` the same way
    /// (Device_Linking.md §11.1).
    nonisolated static func migrateItemToAfterFirstUnlock(
        service: String,
        account: String,
        synchronizable: Bool = true,
        target: CFString = kSecAttrAccessibleAfterFirstUnlock,
        allowReaddFallback: Bool = true
    ) -> KeychainAccessibilityMigrationResult {
        let targetClass = target as String
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable
        ]

        // Attributes-only read first: the (usual) already-migrated path never pulls
        // the secret into memory.
        var attributesQuery = baseQuery
        attributesQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        attributesQuery[kSecReturnAttributes as String] = true

        var attributesResult: AnyObject?
        let attributesStatus = SecItemCopyMatching(attributesQuery as CFDictionary, &attributesResult)

        switch attributesStatus {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return .noItem
        default:
            logger.warning("Accessibility migration: keychain unreadable (OSStatus \(attributesStatus)), retrying next launch")
            return .keychainUnavailable(attributesStatus)
        }

        let originalClass = (attributesResult as? [String: Any])?[kSecAttrAccessible as String] as? String
        if originalClass == targetClass {
            // Info-level on purpose: on a secondary device this line vs "item now..."
            // distinguishes "attribute change arrived via iCloud Keychain sync" from
            // "this device migrated its own copy locally".
            logger.info("Accessibility migration: item already \(targetClass, privacy: .public)")
            return .alreadyMigrated
        }

        // Changing kSecAttrAccessible re-encrypts the item, so the update must carry
        // the data — read it now; nothing is modified unless this read succeeds.
        var dataQuery = baseQuery
        dataQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        dataQuery[kSecReturnData as String] = true

        var dataResult: AnyObject?
        let dataStatus = SecItemCopyMatching(dataQuery as CFDictionary, &dataResult)
        guard dataStatus == errSecSuccess, let data = dataResult as? Data, !data.isEmpty else {
            logger.warning("Accessibility migration: item present but value unreadable (OSStatus \(dataStatus)), retrying next launch")
            return .keychainUnavailable(dataStatus)
        }

        // Preferred path: atomic in-place update — the item never leaves the keychain.
        let update: [String: Any] = [
            kSecAttrAccessible as String: target,
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if updateStatus != errSecSuccess {
            guard allowReaddFallback else {
                // Caller would rather keep the old class than risk the item
                // (the device ID: losing it splits the device's identity)
                logger.warning("Accessibility migration: in-place update failed (OSStatus \(updateStatus)); fallback disabled, retrying next launch")
                return .failed(updateStatus)
            }
            // Fallback for OS versions that reject in-place accessibility changes on
            // synchronizable items: delete + re-add, with the value held in memory.
            logger.warning("Accessibility migration: in-place update failed (OSStatus \(updateStatus)), falling back to delete + re-add")

            let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                logger.error("Accessibility migration: fallback delete failed (OSStatus \(deleteStatus)) — item left untouched")
                return .failed(deleteStatus)
            }

            var addQuery = baseQuery
            addQuery[kSecAttrAccessible as String] = target
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            if addStatus != errSecSuccess {
                // Put the item back under its original class rather than leave none.
                addQuery[kSecAttrAccessible as String] = originalClass ?? (kSecAttrAccessibleWhenUnlocked as String)
                let restoreStatus = SecItemAdd(addQuery as CFDictionary, nil)
                logger.error("Accessibility migration: re-add failed (OSStatus \(addStatus)); restore with original class returned OSStatus \(restoreStatus)")
                return .failed(addStatus)
            }
        }

        // A lost or corrupted mnemonic is unrecoverable — verify the item reads back
        // with the same value and the new class before declaring success.
        var verifyQuery = baseQuery
        verifyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        verifyQuery[kSecReturnAttributes as String] = true
        verifyQuery[kSecReturnData as String] = true

        var verifyResult: AnyObject?
        let verifyStatus = SecItemCopyMatching(verifyQuery as CFDictionary, &verifyResult)
        guard verifyStatus == errSecSuccess,
              let verified = verifyResult as? [String: Any],
              verified[kSecValueData as String] as? Data == data,
              verified[kSecAttrAccessible as String] as? String == targetClass else {
            logger.error("Accessibility migration: post-migration verification failed (OSStatus \(verifyStatus))")
            return .failed(verifyStatus)
        }

        logger.info("Accessibility migration: item now \(targetClass, privacy: .public)")
        return .migrated
    }

    /// Loads mnemonic from keychain
    func loadMnemonic() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true  // Match the save operation
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            Self.logger.error("loadMnemonic failed with OSStatus \(status)")
            throw WalletError.keychainError(status)
        }
        
        guard let data = result as? Data else {
            throw WalletError.encodingFailed
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Checks if mnemonic exists in keychain.
    ///
    /// Note: a `false` here means "not confirmed present" — it does NOT prove absence
    /// (the keychain may be temporarily unreadable). Callers that route UI on absence
    /// must use `mnemonicKeychainStatus()` and require `.notFound`.
    func hasMnemonic() -> Bool {
        return Self.mnemonicKeychainStatus() == .found
    }

    /// Checks the mnemonic keychain status, retrying while the keychain is unavailable.
    /// Bounded backoff (~2s worst case) for transient failures like
    /// errSecInteractionNotAllowed shortly after launch, before protected data is ready.
    private func resolveMnemonicStatus() async -> MnemonicKeychainStatus {
        var status = Self.mnemonicKeychainStatus()
        var delayMilliseconds = 300

        for attempt in 1...3 {
            guard case .unavailable = status else { break }
            Self.logger.warning("Keychain unavailable, retry \(attempt)/3 in \(delayMilliseconds)ms...")
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            delayMilliseconds *= 2
            status = Self.mnemonicKeychainStatus()
        }

        return status
    }
    
    /// Handles seed import after QR code scan
    /// Note: Device registration should be done by coordinator after this call
    func handleSeedImport(_ mnemonic: String) async throws {
        // Save mnemonic (no device registration here)
        try await saveMnemonic(mnemonic)
        
        #if DEBUG
        print("✅ [SecurityService] Seed imported - coordinator should update device registration")
        #endif
    }
    
    /// Removes mnemonic from keychain only (used for rollback during failed imports)
    /// Does not touch cloud data or device registration
    func removeMnemonic() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrSynchronizable as String: true
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletError.keychainError(status)
        }
        
        #if DEBUG
        Self.logger.debug("🗑️ [SecurityService] Removed mnemonic from keychain (rollback)")
        #endif
    }
    
    // NOTE: Wallet data deletion (keychain mnemonic, ubiquitous hash, CloudKit
    // data) is owned exclusively by WalletDataCleanupService, which applies
    // the deletion strategy (local-only vs. full wipe). A duplicate,
    // incomplete wipe implementation used to live here — removed 2026-08-19
    // (Wallet_Deletion_And_Rejoin.md). `removeMnemonic()` above remains for
    // import rollback only.

    // MARK: - Hash Management (For Validation & Cross-Device Detection)
    
    /// Generates PBKDF2 hash of mnemonic for validation
    func hashMnemonic(_ mnemonic: String) -> String {
        let passwordData = Array(mnemonic.utf8)
        let saltData = Array(hashSalt.utf8)
        
        var derivedKeyData = Data(count: 32)
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData,
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(pbkdf2Iterations),
                    derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    32
                )
            }
        }
        
        guard derivationStatus == kCCSuccess else {
            // Fallback to simple hash if PBKDF2 fails
            var combinedData = Data()
            combinedData.append(contentsOf: mnemonic.utf8)
            combinedData.append(contentsOf: hashSalt.utf8)
            return SHA256.hash(data: combinedData)
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }
        
        return derivedKeyData.base64EncodedString()
    }
    
    /// Saves hash to NSUbiquitousKeyValueStore (syncs quickly via iCloud KVS)
    /// This enables fast cross-device wallet detection before SwiftData/CloudKit is initialized
    func saveHashToUbiquitousStore(_ mnemonic: String) {
        let hash = hashMnemonic(mnemonic)
        let store = NSUbiquitousKeyValueStore.default
        store.set(hash, forKey: ubiquitousHashKey)
        store.synchronize()
        
        #if DEBUG
        print("✅ [SecurityService] Saved hash to NSUbiquitousKeyValueStore at \(Date())")
        #endif
    }
    
    /// Gets hash from NSUbiquitousKeyValueStore (fast, works before SwiftData initialization)
    func getUbiquitousHash() -> String? {
        let hash = NSUbiquitousKeyValueStore.default.string(forKey: ubiquitousHashKey)
        
        #if DEBUG
        if let hash = hash {
            print("✅ [SecurityService] Retrieved hash from NSUbiquitousKeyValueStore: \(hash.prefix(8))...")
        } else {
            print("⚠️ [SecurityService] No hash found in NSUbiquitousKeyValueStore")
        }
        #endif
        
        return hash
    }
    
    /// Saves hash to SwiftData (syncs via CloudKit, keeps metadata together)
    /// **DEPRECATED:** This method is no longer used. Hash is only stored in NSUbiquitousKeyValueStore.
    /// Kept for backward compatibility but will be removed in a future version.
    @available(*, deprecated, message: "Use NSUbiquitousKeyValueStore via saveHashToUbiquitousStore() instead")
    func saveHashToStorage(_ mnemonic: String) async throws {
        guard let modelContext = modelContext else {
            throw WalletError.unknown("No model context available")
        }
        
        let hash = hashMnemonic(mnemonic)
        
        // Check if config already exists
        let descriptor = FetchDescriptor<WalletConfiguration>()
        let existing = try? modelContext.fetch(descriptor).first
        
        if let existing = existing {
            // Update existing
            existing.mnemonicHash = hash
            existing.lastAccessedAt = Date()
        } else {
            // Create new
            let config = WalletConfiguration(mnemonicHash: hash)
            modelContext.insert(config)
        }
        
        try modelContext.save()
        
        #if DEBUG
        print("✅ [SecurityService] Saved hash to SwiftData at \(Date())")
        #endif
    }
    
    /// Restores a previously captured raw hash value to NSUbiquitousKeyValueStore.
    /// Used to roll back a failed import: the pre-import hash must be reinstated
    /// verbatim, without re-deriving it from a mnemonic we no longer have.
    func restoreUbiquitousHash(_ hash: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(hash, forKey: ubiquitousHashKey)
        store.synchronize()

        #if DEBUG
        print("🔄 [SecurityService] Restored pre-import hash to NSUbiquitousKeyValueStore at \(Date())")
        #endif
    }

    /// Deletes hash from NSUbiquitousKeyValueStore
    func deleteHashFromUbiquitousStore() {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: ubiquitousHashKey)
        store.synchronize()
        
        #if DEBUG
        print("🗑️ [SecurityService] Deleted hash from NSUbiquitousKeyValueStore at \(Date())")
        #endif
    }
    
    /// Gets locally stored hash from SwiftData
    /// **DEPRECATED:** Hash is no longer stored in SwiftData. Use getUbiquitousHash() instead.
    @available(*, deprecated, message: "Use getUbiquitousHash() instead")
    func getLocalHash() -> String? {
        guard let modelContext = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<WalletConfiguration>()
        let config = try? modelContext.fetch(descriptor).first
        
        return config?.mnemonicHash
    }
    
    /// Gets reference hash from NSUbiquitousKeyValueStore (single source of truth)
    func getReferenceHash() async -> String? {
        return getUbiquitousHash()
    }
    
    /// Gets the wallet hash for device registration purposes
    /// This allows coordinators to register devices without SecurityService doing it directly
    /// - Returns: The wallet hash if available, or nil if no wallet exists
    func getWalletHashForRegistration() -> String? {
        return getUbiquitousHash()
    }
    
    // MARK: - Validation
    
    /// Validates imported mnemonic against stored hash
    func validateMnemonic(_ mnemonic: String) async -> MnemonicValidationResult {
        // 1. Check if it's valid BIP39 format
        guard isValidBIP39(mnemonic) else {
            return .invalidFormat
        }
        
        // 2. Try to get reference hash
        guard let referenceHash = await getReferenceHash() else {
            // No reference hash exists yet - this is OK for first import
            return .validNoReference
        }
        
        // 3. Compare hashes
        let importedHash = hashMnemonic(mnemonic)
        
        return importedHash == referenceHash ? .valid : .invalid
    }
    
    /// Validates BIP39 format (basic check - enhance as needed)
    /// Word count, word list and checksum through bark's binding, so the
    /// seed is never written for a phrase bark would refuse to open
    /// (Import_Screen_Split.md §3; pinned by MnemonicChecksumTests).
    func isValidBIP39(_ mnemonic: String) -> Bool {
        RecoveryPhraseInput.isValidPhrase(mnemonic)
    }
    
    // MARK: - Biometric Authentication
    
    /// Authenticates user with Face ID / Touch ID
    func authenticateUser(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw WalletError.biometricNotAvailable
        }
        
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            throw WalletError.authenticationFailed
        }
    }
    
    /// Checks if biometrics are available
    func biometricsAvailable() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}

// MARK: - Supporting Types

/// Result of a keychain existence check for the wallet mnemonic.
/// `.unavailable` means the keychain could not be read (transient at cold launch);
/// it must never be treated as proof of absence.
enum MnemonicKeychainStatus: Equatable {
    case found
    case notFound              // errSecItemNotFound — definitively absent
    case unavailable(OSStatus) // any other error — answer unknown right now
}

/// Outcome of migrating the mnemonic keychain item to `kSecAttrAccessibleAfterFirstUnlock`.
/// `.keychainUnavailable` and `.failed` both leave a readable item in place (in the
/// worst case restored under its original class); the migration retries on a later launch.
enum KeychainAccessibilityMigrationResult: Equatable {
    case migrated               // accessibility updated and verified by read-back
    case alreadyMigrated        // item already has the new class — no-op
    case noItem                 // no mnemonic in the keychain (fresh install) — no-op
    case keychainUnavailable(OSStatus) // couldn't read; nothing was modified
    case failed(OSStatus)       // migration attempted but not completed
}

enum WalletState: Equatable {
    case unknown                // Initial state, not yet checked
    case noWallet              // No wallet exists anywhere
    case walletWithSeed        // Full wallet with local seed
    // Wallet exists but this device can't spend (not primary, or seed not synced
    // here yet - see ConnectionStatus.readOnlyReason).
    //
    // `deviceName` is nil when the account has no primary device registered, or
    // when the registry couldn't be read. It used to default to "Another Device",
    // which made a zero-primary account indistinguishable from an ordinary
    // secondary and hid the one state whose remedy is promoting *this* device.
    // Callers that display it must handle nil rather than substitute a name.
    case walletActiveElsewhere(deviceName: String?)
    // The account has a wallet this install has not linked (no link record,
    // or a record whose own registry row is gone): show the link screen, never
    // onboarding, which would offer creating a second wallet
    // (Device_Linking.md §4.2).
    case accountWalletAwaitingLink(reason: LinkPromptReason)
}

enum MnemonicValidationResult {
    case valid                 // Matches reference hash
    case invalid               // Doesn't match reference hash
    case validNoReference      // Valid BIP39, but no reference to compare
    case invalidFormat         // Not valid BIP39 format
}

enum WalletError: LocalizedError {
    // Keychain errors
    case encodingFailed
    case keychainError(OSStatus)
    case mnemonicNotFound
    
    // Security errors
    case authenticationFailed
    case biometricNotAvailable
    
    // Validation errors
    case invalidMnemonic
    case mnemonicHashMismatch
    case invalidBIP39Words
    
    // Import/Export errors
    case qrCodeGenerationFailed
    case qrCodeScanningFailed
    case exportFailed
    
    // Sync errors
    case cloudKitNotAvailable
    case syncTimeout
    case networkUnavailable
    
    // General
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode recovery phrase"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .mnemonicNotFound:
            return "No recovery phrase found"
        case .authenticationFailed:
            return "Authentication failed"
        case .biometricNotAvailable:
            return "Face ID / Touch ID not available"
        case .invalidMnemonic:
            return "Invalid recovery phrase"
        case .mnemonicHashMismatch:
            return "Recovery phrase doesn't match your wallet"
        case .invalidBIP39Words:
            return "One or more words are not valid BIP39 words"
        case .qrCodeGenerationFailed:
            return "Failed to generate QR code"
        case .qrCodeScanningFailed:
            return "Failed to scan QR code"
        case .exportFailed:
            return "Failed to export wallet"
        case .cloudKitNotAvailable:
            return "iCloud is not available"
        case .syncTimeout:
            return "Sync is taking longer than expected"
        case .networkUnavailable:
            return "No internet connection"
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .keychainError:
            return "Try restarting the app or check system settings"
        case .mnemonicNotFound:
            return "You may need to import your recovery phrase"
        case .authenticationFailed:
            return "Please try again or check your biometric settings"
        case .biometricNotAvailable:
            return "Enable Face ID or Touch ID in Settings"
        case .invalidMnemonic, .invalidBIP39Words:
            return "Check your recovery phrase and try again"
        case .mnemonicHashMismatch:
            return "Make sure you're entering the correct recovery phrase for this wallet"
        case .networkUnavailable:
            return "Check your internet connection and try again"
        default:
            return nil
        }
    }
}
