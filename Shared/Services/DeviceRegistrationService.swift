//
//  DeviceRegistrationService.swift
//  Arké
//
//  Created by Christoph on 12/04/25.
//

import Foundation
import SwiftData
import Observation
import os

#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
class DeviceRegistrationService {
    // MARK: - Logging
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "DeviceRegistration")
    
    // MARK: - Published Properties
    
    /// All registered devices for the current wallet
    var registeredDevices: [DeviceRegistration] = []
    
    /// Error message for device registration operations
    var error: String?
    
    /// Loading state
    var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    private var modelContext: ModelContext?
    private let taskManager: TaskDeduplicationManager
    
    // MARK: - Constants
    
    private let keychainService = "com.arke.device"
    private let deviceIdAccount = "deviceId"
    private let lastHeartbeatKey = "com.arke.device.lastHeartbeat"
    private let heartbeatInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    /// Key prefix for the fast device registry in iCloud KVS. Static so the pure
    /// key-parsing helper (`otherRegisteredDeviceIds`) can share it with the writers.
    nonisolated static let registeredDevicesPrefix = "com.arke.device.registered."
    
    // MARK: - Cached Values
    
    private var cachedDeviceId: String?
    
    /// Pending registration (for lazy registration pattern)
    private var pendingRegistration: (hash: String, hasSeed: Bool)?

    /// Observer token for CloudKit remote-change refreshes
    @ObservationIgnored private var cloudKitChangeObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        observeCloudKitChanges()

        // Load registered devices
        Task {
            await loadRegisteredDevices()
            await processPendingRegistrations()
        }
    }

    /// Refreshes the device list (and resolves primary conflicts) whenever CloudKit
    /// imports records mid-session. Without this, registrations arriving from other
    /// devices are invisible until the next launch re-runs loadRegisteredDevices().
    /// CloudKitObserver already debounces the underlying remote-change notifications.
    private func observeCloudKitChanges() {
        guard cloudKitChangeObserver == nil else { return }

        cloudKitChangeObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.loadRegisteredDevices()
                await self.reconcilePrimaryConflicts()
            }
        }
    }
    
    // MARK: - Lazy Registration Pattern
    
    /// Schedules a device registration to occur when ModelContext becomes available
    /// Use this when you need to register a device but ModelContext might not be ready yet
    func schedulePendingRegistration(walletHash: String, hasSeed: Bool) {
        pendingRegistration = (hash: walletHash, hasSeed: hasSeed)
        
        Self.logger.debug("Scheduled pending registration (hasSeed=\(hasSeed))")
    }
    
    /// Processes any pending registrations (called after ModelContext is set)
    private func processPendingRegistrations() async {
        guard let pending = pendingRegistration else { return }
        
        pendingRegistration = nil
        
        do {
            try await registerCurrentDevice(
                walletHash: pending.hash,
                hasSeed: pending.hasSeed
            )
            
            Self.logger.info("Processed pending registration")
        } catch {
            Self.logger.warning("Pending registration failed: \(error)")
        }
    }
    
    // MARK: - Device ID Management
    
    /// Gets or creates a stable device ID stored in Keychain
    /// This ID survives app reinstall and NEVER syncs via iCloud Keychain
    func getOrCreateDeviceId() throws -> String {
        // Return cached value if available
        if let cached = cachedDeviceId {
            return cached
        }
        
        // Try to load from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: deviceIdAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let deviceId = String(data: data, encoding: .utf8) {
            cachedDeviceId = deviceId
            
            Self.logger.info("Loaded existing device ID: \(deviceId)")
            
            return deviceId
        }
        
        // Generate new device ID
        let newDeviceId = UUID().uuidString
        guard let data = newDeviceId.data(using: .utf8) else {
            throw DeviceRegistrationError.encodingFailed
        }
        
        // Store in Keychain with ThisDeviceOnly
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: deviceIdAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false  // NEVER sync!
        ]
        
        status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceRegistrationError.keychainError(status)
        }
        
        cachedDeviceId = newDeviceId
        
        Self.logger.info("Created new device ID: \(newDeviceId)")
        
        return newDeviceId
    }
    
    /// Gets the current device name from the system
    private func getDeviceName() -> String {
        #if os(iOS)
        // Use model name instead of user-assigned name (which requires special entitlement)
        return getDeviceModelName()
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown Device"
        #endif
    }
    
    /// Gets a user-friendly device model name (e.g., "iPhone 15 Pro")
    private func getDeviceModelName() -> String {
        #if os(iOS)
        guard let identifier = getDeviceModelIdentifier() else {
            return UIDevice.current.model // Fallback to generic "iPhone", "iPad", etc.
        }
        
        // Map common identifiers to friendly names
        // Note: This list should be updated periodically with new models
        let modelMap: [String: String] = [
            // iPhone 15 series
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            
            // iPhone 14 series
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            
            // iPhone 13 series
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            
            // iPhone 12 series
            "iPhone13,2": "iPhone 12",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone12,8": "iPhone SE (2nd gen)",
            
            // iPad Pro
            "iPad14,3": "iPad Pro 11\" (4th gen)",
            "iPad14,4": "iPad Pro 11\" (4th gen)",
            "iPad14,5": "iPad Pro 12.9\" (6th gen)",
            "iPad14,6": "iPad Pro 12.9\" (6th gen)",
            
            // iPad Air
            "iPad13,16": "iPad Air (5th gen)",
            "iPad13,17": "iPad Air (5th gen)",
            
            // iPad
            "iPad13,18": "iPad (10th gen)",
            "iPad13,19": "iPad (10th gen)",
            
            // iPad mini
            "iPad14,1": "iPad mini (6th gen)",
            "iPad14,2": "iPad mini (6th gen)"
        ]
        
        // Return friendly name if found, otherwise return the identifier
        return modelMap[identifier] ?? identifier
        #else
        return "Unknown Device"
        #endif
    }
    
    /// Gets the current platform
    private func getDevicePlatform() -> DevicePlatform {
        return DevicePlatform.current
    }
    
    /// Gets the device model identifier (e.g., "iPhone15,3")
    private func getDeviceModelIdentifier() -> String? {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return nil
        #endif
    }
    
    // MARK: - Device Registration
    
    /// Registers the current device in the device registry
    ///
    /// Primary status is claimed only by explicit user actions (wallet create/import,
    /// `allowPrimaryClaim: true`), and only when no other device is currently known to
    /// hold it. Detection paths must pass `allowPrimaryClaim: false`: a device whose
    /// seed arrived via iCloud Keychain didn't create the wallet, and racing
    /// "first device" heuristics against KVS/CloudKit sync lag is what produced
    /// duplicate primaries. A device that wrongly ends up secondary recovers via the
    /// no-primary banner (promote flow); duplicate primaries converge via
    /// `reconcilePrimaryConflicts()`.
    ///
    /// - Parameters:
    ///   - walletHash: The hash of the wallet this device is associated with
    ///   - hasSeed: Whether this device has the seed phrase stored locally
    ///   - allowPrimaryClaim: Whether this registration may claim primary status
    ///     (true only for create/import flows)
    func registerCurrentDevice(walletHash: String, hasSeed: Bool, allowPrimaryClaim: Bool = false) async throws {
        // The assertion wraps the whole pass — save, devices reload and
        // primary reconcile all write — and also covers joining an in-flight
        // registration. Registration runs on launch and on every foreground
        // pass, so it regularly overlaps the app heading to the background,
        // and a process suspended mid-save is killed for holding the store's
        // SQLite lock (0xdead10cc; TestFlight build 23 died in this save).
        try await withBackgroundActivityAssertion("device-registration") {
            try await self.registerCurrentDeviceUnprotected(
                walletHash: walletHash,
                hasSeed: hasSeed,
                allowPrimaryClaim: allowPrimaryClaim
            )
        }
    }

    private func registerCurrentDeviceUnprotected(
        walletHash: String,
        hasSeed: Bool,
        allowPrimaryClaim: Bool
    ) async throws {
        return try await taskManager.execute(key: "registerCurrentDevice") {
            guard let modelContext = self.modelContext else {
                throw DeviceRegistrationError.noModelContext
            }

            let deviceId = try self.getOrCreateDeviceId()
            let deviceName = self.getDeviceName()
            let platform = self.getDevicePlatform()
            let modelIdentifier = self.getDeviceModelIdentifier()
            
            // Check if device already registered
            let descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate { $0.deviceId == deviceId }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                // Update existing registration
                let walletChanged = existing.walletHash != walletHash

                existing.deviceName = deviceName
                existing.walletHash = walletHash
                existing.hasSeed = hasSeed
                existing.lastSeenAt = Date()
                existing.lastAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                existing.isActive = true
                existing.deviceModelIdentifier = modelIdentifier

                if walletChanged {
                    // Primary status never carries over from another wallet
                    let claim = allowPrimaryClaim && !self.activePrimaryExists(for: walletHash, excludingDeviceId: deviceId, in: modelContext)
                    existing.isPrimaryDevice = claim
                    existing.becamePrimaryAt = claim ? Date() : nil
                    existing.demotedAt = nil
                    Self.logger.info("Wallet changed for this device - primary reset (claimed=\(claim))")
                } else if allowPrimaryClaim && !existing.isPrimaryDevice
                            && !self.activePrimaryExists(for: walletHash, excludingDeviceId: deviceId, in: modelContext) {
                    // A deliberate create/import on this device may claim a vacant primary
                    existing.isPrimaryDevice = true
                    existing.becamePrimaryAt = Date()
                }
                // Otherwise isPrimaryDevice is preserved - detection-path updates never change it

                // Ensure device is registered in KV store with current primary status
                self.registerDeviceInKVStore(deviceId: deviceId, walletHash: walletHash)

                self.writeOwnPrimaryFlag(existing.isPrimaryDevice, deviceId: deviceId)

                Self.logger.info("Updated existing device registration")
            } else {
                // Primary is claimed only by explicit create/import actions, and only
                // when no other device is currently known to hold it. No "first device"
                // inference: sync lag would let a detecting device win that race.
                let shouldBePrimary = allowPrimaryClaim && !self.activePrimaryExists(for: walletHash, excludingDeviceId: deviceId, in: modelContext)

                // Register device in KV store registry (used for cleanup bookkeeping)
                self.registerDeviceInKVStore(deviceId: deviceId, walletHash: walletHash)

                // Store primary status in KV store (read by shouldBlockWalletAccess and
                // the MainView demotion/promotion observers)
                self.writeOwnPrimaryFlag(shouldBePrimary, deviceId: deviceId)

                // Create new registration
                let registration = DeviceRegistration(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    platform: platform,
                    walletHash: walletHash,
                    hasSeed: hasSeed,
                    isPrimaryDevice: shouldBePrimary,
                    deviceModelIdentifier: modelIdentifier,
                    becamePrimaryAt: shouldBePrimary ? Date() : nil
                )

                modelContext.insert(registration)

                Self.logger.info("Created new device registration (isPrimary=\(shouldBePrimary), claimAllowed=\(allowPrimaryClaim))")
            }
            
            try modelContext.save()

            // Update last heartbeat timestamp
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastHeartbeatKey)

            // Reload devices list
            await self.loadRegisteredDevices()

            // Resolve any duplicate-primary state that is already visible
            await self.reconcilePrimaryConflicts()
        }
    }

    /// Whether another active device currently holds primary for the given wallet
    private func activePrimaryExists(for walletHash: String, excludingDeviceId deviceId: String, in modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate {
                $0.walletHash == walletHash && $0.isPrimaryDevice == true && $0.isActive == true && $0.deviceId != deviceId
            }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }
    
    /// Updates the current device's seed status
    /// Call this when a device imports the seed via QR code
    func updateCurrentDeviceHasSeed(_ hasSeed: Bool) async throws {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let deviceId = try getOrCreateDeviceId()
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        
        guard let registration = try? modelContext.fetch(descriptor).first else {
            throw DeviceRegistrationError.deviceNotRegistered
        }
        
        registration.hasSeed = hasSeed
        registration.lastSeenAt = Date()
        
        try modelContext.save()
        
        Self.logger.info("Updated device hasSeed to \(hasSeed)")
        
        await loadRegisteredDevices()
    }
    
    /// Unregisters the current device from the device registry
    func unregisterCurrentDevice() async throws {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let deviceId = try getOrCreateDeviceId()
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        
        let registration = try? modelContext.fetch(descriptor).first

        if let registration {
            modelContext.delete(registration)
            try modelContext.save()
        }

        // Remove the fast-registry mirror unconditionally, and for every wallet
        // hash — this device is leaving, so none of its entries are valid.
        //
        // This used to sit inside `if let registration`, so a missing row meant
        // the mirror entry survived: a fresh adopt whose CloudKit row hadn't
        // imported yet, a row already collapsed by dedupeOwnRecords, or an
        // unreadable context all left a permanent ghost. Since the mirror is what
        // the deletion decision reads, that ghost blocks every *remaining*
        // device's full wipe indefinitely — and each reinstall of this device
        // re-writes it, so it never ages out. Clearing across hashes also removes
        // the case where the row's hash and the account's hash disagree.
        let removedMirrorEntries = removeMirrorEntries(deviceId: deviceId)

        Self.logger.debug("Unregistered current device (registry row existed: \(registration != nil), mirror entries removed: \(removedMirrorEntries))")

        await loadRegisteredDevices()
    }
    
    // MARK: - Heartbeat System
    
    /// Updates the heartbeat timestamp if needed (>24h since last update)
    func updateHeartbeatIfNeeded() async {
        let lastHeartbeat = UserDefaults.standard.double(forKey: lastHeartbeatKey)
        let timeSinceLastHeartbeat = Date().timeIntervalSince1970 - lastHeartbeat
        
        // Only update if more than 24 hours have passed
        guard timeSinceLastHeartbeat > heartbeatInterval else {
            let hoursRemaining = (heartbeatInterval - timeSinceLastHeartbeat) / 3600
            Self.logger.debug("Skipping heartbeat (next in \(String(format: "%.1f", hoursRemaining)) hours)")
            return
        }
        
        do {
            try await updateHeartbeat()
        } catch {
            Self.logger.warning("Heartbeat update failed: \(error.localizedDescription)")
        }
    }
    
    /// Updates the last seen timestamp for the current device
    func updateHeartbeat() async throws {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let deviceId = try getOrCreateDeviceId()
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        
        guard let registration = try? modelContext.fetch(descriptor).first else {
            // Device not registered yet - this is OK, will register when wallet is created
            return
        }
        
        registration.lastSeenAt = Date()
        registration.lastAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        try modelContext.save()
        
        // Update last heartbeat timestamp
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastHeartbeatKey)
        
        Self.logger.debug("Heartbeat updated")

        await loadRegisteredDevices()
        await reconcilePrimaryConflicts()
    }
    
    // MARK: - Queries
    
    /// Loads all registered devices from SwiftData
    func loadRegisteredDevices() async {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        
        if let devices = try? modelContext.fetch(descriptor) {
            registeredDevices = devices
            
            Self.logger.debug("Loaded \(devices.count) registered devices")
        }
    }
    
    /// Gets all active devices (excluding inactive and stale devices)
    func getActiveDevices() async throws -> [DeviceRegistration] {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        
        let devices = try modelContext.fetch(descriptor)
        
        // Filter out stale devices
        return devices.filter { !$0.isStale }
    }
    
    /// Gets all devices except the current one
    /// - Parameter walletHash: When provided, only considers devices registered for
    ///   that wallet - registrations left over from another (test) wallet must not
    ///   count, the same scoping `getPrimaryDevice(walletHash:)` applies
    func getOtherDevices(walletHash: String? = nil) async throws -> [DeviceRegistration] {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }

        let currentDeviceId = try getOrCreateDeviceId()

        let descriptor: FetchDescriptor<DeviceRegistration>
        if let walletHash = walletHash {
            descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate {
                    $0.deviceId != currentDeviceId && $0.isActive == true && $0.walletHash == walletHash
                },
                sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate { $0.deviceId != currentDeviceId && $0.isActive == true },
                sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
            )
        }

        return try modelContext.fetch(descriptor)
    }

    /// Device IDs the fast KVS registry knows about for a wallet, excluding this device.
    ///
    /// Pure and testable. Keys are `com.arke.device.registered.<walletHash>.<deviceId>`;
    /// the wallet hash is base64 (PBKDF2, no dots) and device IDs are UUID strings
    /// (no dots), so a prefix match isolates the device ID exactly.
    nonisolated static func otherRegisteredDeviceIds(
        kvsKeys: [String],
        walletHash: String,
        currentDeviceId: String
    ) -> Set<String> {
        let prefix = "\(registeredDevicesPrefix)\(walletHash)."
        var ids: Set<String> = []

        for key in kvsKeys where key.hasPrefix(prefix) {
            let deviceId = String(key.dropFirst(prefix.count))
            guard !deviceId.isEmpty, deviceId != currentDeviceId else { continue }
            ids.insert(deviceId)
        }

        return ids
    }

    /// Checks if there are other active devices registered for this wallet.
    ///
    /// Thin wrapper over `otherDeviceReport(walletHash:)` — see that method for
    /// the store-ordering rationale. Kept as the answer the deletion strategy
    /// needs; callers that must *show* the blocking devices use the report.
    func hasOtherActiveDevices(walletHash: String?) async throws -> Bool {
        try await otherDeviceReport(walletHash: walletHash).hasOthers
    }

    /// Every other device the account's registries say still holds this wallet.
    ///
    /// Reads the fast iCloud KVS registry AND the CloudKit-backed SwiftData
    /// registry, and lets KVS evidence stand on its own. That precedence is
    /// load-bearing, not an optimization: KVS converges in seconds while a
    /// CloudKit import can take minutes or never arrive offline, and a joining
    /// secondary that asks this question inside that window would otherwise be
    /// told it is the last device — which routes the delete flow to a full wipe
    /// and destroys the account's shared seed (Multi_Device_Design.md,
    /// Principle 3). Detection already routes launch on KVS; the deletion scope,
    /// the one irreversible decision, must not read the slower store alone.
    ///
    /// KVS entries carry no staleness filter: their timestamp is "last
    /// registered", not "last seen" (heartbeats don't refresh it), so ageing them
    /// out would drop live devices. A mirror-only entry therefore blocks the full
    /// wipe indefinitely — the conservative direction. Unlike the boolean it
    /// replaces, this report says *which* devices block and whether each one has
    /// a registry row, because a mirror-only entry has no remedy in the delete
    /// flow today: `unlinkDevice` needs a row to delete.
    ///
    /// - Parameter walletHash: the wallet to scope the question to. `nil` or empty
    ///   means the account wallet is unknown (KVS detached after an iCloud
    ///   sign-out, S10) — the KVS registry can't be queried without it, so this
    ///   falls back to the unscoped SwiftData check, which is exactly the
    ///   pre-2026-09-21 behaviour. Answering a blanket "others exist" instead
    ///   was tried and reverted: it buys no safety (the dangerous case — a
    ///   joining secondary — always has a hash, since detection routes on it)
    ///   while making the wallet undeletable on a signed-out device, and a
    ///   local-only deletion with no hash records no tombstone, so the retained
    ///   seed resurrects the wallet on the next launch.
    /// - Throws: only when *neither* store could be read. An unreadable registry
    ///   with corroborating mirror entries still answers "others exist"; an
    ///   unreadable registry with an empty mirror is genuine ignorance, and the
    ///   caller must map it to the conservative strategy rather than to "alone".
    func otherDeviceReport(walletHash: String?) async throws -> OtherDeviceReport {
        let currentDeviceId = try getOrCreateDeviceId()

        guard let walletHash, !walletHash.isEmpty else {
            Self.logger.warning("Other-device check without a wallet hash — falling back to the unscoped registry check")
            let others = try await getOtherDevices()
            return Self.otherDeviceReport(
                kvsEntries: [:],
                walletHash: nil,
                registryDevices: others.map(Self.snapshot(of:)),
                currentDeviceId: currentDeviceId,
                registryError: nil,
                now: Date()
            )
        }

        // Tolerate an unreadable registry: the mirror alone can still prove that
        // others exist, and that proof is the one that must not be lost
        var registryDevices: [RegistryDeviceSnapshot] = []
        var registryError: Error?
        do {
            registryDevices = try await getOtherDevices(walletHash: walletHash).map(Self.snapshot(of:))
        } catch {
            registryError = error
            Self.logger.warning("Device registry unreadable during the other-device check: \(error.localizedDescription)")
        }

        let report = Self.otherDeviceReport(
            kvsEntries: NSUbiquitousKeyValueStore.default.dictionaryRepresentation,
            walletHash: walletHash,
            registryDevices: registryDevices,
            currentDeviceId: currentDeviceId,
            registryError: registryError,
            now: Date()
        )

        // Neither store had anything to say — propagate the ignorance instead of
        // letting it read as "this is the last device"
        if let errorToPropagate = Self.registryErrorToPropagate(report: report, registryError: registryError) {
            throw errorToPropagate
        }

        if report.hasOthers {
            Self.logger.info("Other-device check: \(report.others.count) device(s) hold this wallet (\(report.mirrorOnly.count) mirror-only)")
        }

        return report
    }

    /// The account's wallet hash, as launch detection and the deletion decision
    /// both see it.
    ///
    /// Surfaces that list devices need it to scope themselves to the wallet
    /// actually in use — an unscoped list shows leftover registrations from other
    /// (test) wallets, and the delete flow has always been scoped, so an unscoped
    /// list is also a way for the two to disagree.
    func accountWalletHash() -> String? {
        ServiceContainer.shared.securityService.getUbiquitousHash()
    }

    /// `otherDeviceReport(walletHash:)` for the account's current wallet.
    ///
    /// The one entry point for UI: every surface that tells the user something
    /// about other devices must read this, so the devices list and the delete
    /// dialog cannot drift apart the way they did on 2026-09-23 (Linked Devices
    /// said "1 device" while the delete dialog said others kept access).
    func currentOtherDeviceReport() async throws -> OtherDeviceReport {
        try await otherDeviceReport(walletHash: accountWalletHash())
    }

    /// An unreadable registry with corroborating mirror entries still answers
    /// "others exist"; with an empty mirror it is genuine ignorance and must
    /// propagate — otherwise it reads as "last device" downstream, which is
    /// the destructive direction.
    nonisolated static func registryErrorToPropagate(report: OtherDeviceReport, registryError: Error?) -> Error? {
        guard let registryError, !report.hasOthers else { return nil }
        return registryError
    }

    /// Pure-data view of a registry row. `@MainActor` because it reads the model.
    private static func snapshot(of device: DeviceRegistration) -> RegistryDeviceSnapshot {
        RegistryDeviceSnapshot(
            deviceId: device.deviceId,
            deviceName: device.deviceName,
            walletHash: device.walletHash,
            lastSeenAt: device.lastSeenAt,
            isActive: device.isActive
        )
    }

    /// Merges the two registries into one answer. Pure and testable: the stores
    /// disagree in practice, and which of them wins each question is exactly the
    /// part worth pinning.
    ///
    /// The blocking set is deliberately identical to the boolean this replaced:
    /// every non-stale registry row, plus every mirror entry regardless of what
    /// the registry says about it. A stale registry row does not block on its
    /// own, but a mirror entry for that same device does — and then the row's
    /// name is used, since naming a blocker beats calling it unknown.
    ///
    /// - Parameters:
    ///   - kvsEntries: `NSUbiquitousKeyValueStore.dictionaryRepresentation`, warts
    ///     and all — it also holds the wallet hash, network config and primary
    ///     flags, so non-registry keys and non-numeric values must be ignored.
    ///   - walletHash: `nil` when the account wallet is unknown: the mirror can't
    ///     be queried without it and the registry is read unscoped.
    ///   - registryError: what went wrong reading the registry, if anything. Only
    ///     recorded here; whether it is fatal depends on the mirror.
    ///   - now: injected so staleness is deterministic under test.
    nonisolated static func otherDeviceReport(
        kvsEntries: [String: Any],
        walletHash: String?,
        registryDevices: [RegistryDeviceSnapshot],
        currentDeviceId: String,
        registryError: Error?,
        now: Date,
        staleThresholdDays: Int = 30
    ) -> OtherDeviceReport {
        let mirrorIds: Set<String>
        var registeredAt: [String: Date] = [:]

        if let walletHash, !walletHash.isEmpty {
            mirrorIds = otherRegisteredDeviceIds(
                kvsKeys: Array(kvsEntries.keys),
                walletHash: walletHash,
                currentDeviceId: currentDeviceId
            )
            let prefix = "\(registeredDevicesPrefix)\(walletHash)."
            for deviceId in mirrorIds {
                // Written as a timeIntervalSince1970 Double; anything else is not
                // ours to interpret, and a missing timestamp must not drop the
                // entry — it still blocks
                if let seconds = kvsEntries["\(prefix)\(deviceId)"] as? Double {
                    registeredAt[deviceId] = Date(timeIntervalSince1970: seconds)
                }
            }
        } else {
            mirrorIds = []
        }

        // Rows for other devices, scoped to this wallet when we know it
        let candidates = registryDevices.filter { device in
            guard device.deviceId != currentDeviceId, device.isActive else { return false }
            guard let walletHash, !walletHash.isEmpty else { return true }
            return device.walletHash == walletHash
        }
        let namesByDeviceId = Dictionary(
            registryDevices.map { ($0.deviceId, $0.deviceName) },
            uniquingKeysWith: { first, _ in first }
        )

        let staleThreshold = TimeInterval(staleThresholdDays * 24 * 60 * 60)
        var others: [OtherWalletDevice] = []
        var claimed: Set<String> = []

        for device in candidates {
            let isStale = now.timeIntervalSince(device.lastSeenAt) > staleThreshold
            // A stale row blocks only when the mirror corroborates it
            guard !isStale || mirrorIds.contains(device.deviceId) else { continue }

            claimed.insert(device.deviceId)
            others.append(OtherWalletDevice(
                deviceId: device.deviceId,
                deviceName: device.deviceName.isEmpty ? nil : device.deviceName,
                lastSeenAt: device.lastSeenAt,
                registeredAt: registeredAt[device.deviceId],
                isStale: isStale,
                source: .registry
            ))
        }

        for deviceId in mirrorIds.subtracting(claimed).sorted() {
            // No active registry row for this wallet: either the CloudKit import
            // hasn't landed (seconds to never, offline) or it never will, because
            // the row was deleted without its mirror entry. `unlinkDevice` cannot
            // clear these — there is no row to delete.
            let name = namesByDeviceId[deviceId]
            others.append(OtherWalletDevice(
                deviceId: deviceId,
                deviceName: (name?.isEmpty ?? true) ? nil : name,
                lastSeenAt: nil,
                registeredAt: registeredAt[deviceId],
                isStale: false,      // unknowable: the mirror has no heartbeat
                source: .kvsOnly
            ))
        }

        // Most recently heard from first; mirror-only entries fall back to their
        // registration date, which is the only timestamp they have
        others.sort { lhs, rhs in
            let lhsDate = lhs.lastSeenAt ?? lhs.registeredAt ?? .distantPast
            let rhsDate = rhs.lastSeenAt ?? rhs.registeredAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.deviceId < rhs.deviceId
        }

        return OtherDeviceReport(others: others, registryUnreadable: registryError != nil)
    }
    
    /// Gets the current device registration
    func getCurrentDevice() async throws -> DeviceRegistration? {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let deviceId = try getOrCreateDeviceId()
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Gets stale devices (not seen in specified number of days)
    func getStaleDevices(olderThan days: Int = 30) async throws -> [DeviceRegistration] {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        
        let allDevices = try modelContext.fetch(descriptor)
        
        return allDevices.filter { $0.isStale(threshold: days) }
    }
    
    /// Gets the primary device for the wallet
    /// - Parameter walletHash: When provided, only considers devices registered for
    ///   that wallet - stale registrations from other (test) wallets must not count
    func getPrimaryDevice(walletHash: String? = nil) async throws -> DeviceRegistration? {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }

        let descriptor: FetchDescriptor<DeviceRegistration>
        if let walletHash = walletHash {
            descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate { $0.isPrimaryDevice == true && $0.isActive == true && $0.walletHash == walletHash }
            )
        } else {
            descriptor = FetchDescriptor<DeviceRegistration>(
                predicate: #Predicate { $0.isPrimaryDevice == true && $0.isActive == true }
            )
        }

        return try? modelContext.fetch(descriptor).first
    }
    
    /// Checks if the current device is the primary device
    func isCurrentDevicePrimary() async throws -> Bool {
        let currentDevice = try await getCurrentDevice()
        return currentDevice?.isPrimaryDevice ?? false
    }
    
    // MARK: - Device Management
    
    /// Unlinks a specific device by deviceId
    func unlinkDevice(_ deviceId: String) async throws {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        
        guard let registration = try? modelContext.fetch(descriptor).first else {
            throw DeviceRegistrationError.deviceNotFound
        }
        
        // Delete the registration (could also set isActive = false to keep history)
        modelContext.delete(registration)
        try modelContext.save()

        // Also remove from the KV store mirror — across ALL wallet hashes,
        // same rationale as unregisterCurrentDevice (2026-09-24): a mirror
        // entry left under a different hash keeps blocking that wallet's full
        // wipe with nothing to unlink. Multi-wallet test devices lose their
        // other-wallet entry too; accepted.
        removeMirrorEntries(deviceId: deviceId)

        Self.logger.debug("Unlinked device: \(deviceId)")

        await loadRegisteredDevices()
    }

    /// Unlinks all devices except the current one, scoped to the account's
    /// wallet — an unscoped pass would also unlink registrations belonging to
    /// other (test) wallets. Nil hash keeps the unscoped fallback.
    func unlinkAllOtherDevices() async throws {
        let others = try await getOtherDevices(walletHash: accountWalletHash())

        for device in others {
            try await unlinkDevice(device.deviceId)
        }

        Self.logger.debug("Unlinked \(others.count) other devices")
    }
    
    /// Cleans up stale devices (not seen in specified number of days)
    func cleanupStaleDevices(olderThan days: Int = 30) async throws {
        let staleDevices = try await getStaleDevices(olderThan: days)
        
        guard !staleDevices.isEmpty else {
            Self.logger.info("No stale devices to cleanup")
            return
        }
        
        for device in staleDevices {
            try await unlinkDevice(device.deviceId)
        }
        
        Self.logger.debug("Cleaned up \(staleDevices.count) stale devices")
    }
    
    /// Migrates primary device status to the current device
    /// Sets current device as primary and removes primary status from all other devices
    func migrateToThisDevice() async throws {
        guard let modelContext = modelContext else {
            throw DeviceRegistrationError.noModelContext
        }
        
        let currentDeviceId = try getOrCreateDeviceId()
        
        // Get all devices for this wallet
        let currentDevice = try await getCurrentDevice()
        guard let walletHash = currentDevice?.walletHash else {
            throw DeviceRegistrationError.deviceNotRegistered
        }
        
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.walletHash == walletHash }
        )
        
        let allDevices = try modelContext.fetch(descriptor)
        
        // Update all devices: current becomes primary, others become secondary
        for device in allDevices {
            if device.deviceId == currentDeviceId {
                device.isPrimaryDevice = true
                Self.logger.info("Set current device as primary")
            } else if device.isPrimaryDevice {
                device.isPrimaryDevice = false
                Self.logger.debug("Removed primary status from device: \(device.deviceName)")
            }
        }
        
        try modelContext.save()
        await loadRegisteredDevices()
        
        Self.logger.info("Migration complete - this device is now primary")
    }
    
    // MARK: - Manual Primary Device Assignment
    
    /// Demote this device from primary to secondary
    /// User must then promote another device to complete migration
    func demoteThisDevice() async throws {
        // 1. Verify we are currently primary
        guard try await isCurrentDevicePrimary() else {
            throw MigrationError.notPrimaryDevice
        }

        // 2. Get current device
        guard let currentDevice = try await getCurrentDevice() else {
            throw MigrationError.deviceNotFound
        }

        // 3. CRITICAL: Backup wallet state to iCloud BEFORE demotion
        // This ensures the new primary has the latest wallet state
        // Note: The actual backup will be triggered by WalletManager's closeWalletForMigration()
        // which is called when it receives the deviceDemotedFromPrimary notification
        Self.logger.debug("Backup will occur during wallet closure")

        // 4. Update current device to be secondary
        currentDevice.isPrimaryDevice = false
        currentDevice.demotedAt = Date()

        // 5. Save to CloudKit
        try modelContext?.save()

        // 6. Update iCloud KV Store for faster sync
        writeOwnPrimaryFlag(false, deviceId: currentDevice.deviceId)

        // 7. Set local UserDefaults flag for instant detection on next launch
        UserDefaults.standard.set(true, forKey: "device_\(currentDevice.deviceId)_wasDemoted")

        // 8. Signal to WalletManager to close wallet immediately
        NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)

        Self.logger.info("Device demoted to secondary")
        
        // 9. Notify that there's no primary device now
        NotificationCenter.default.post(name: .showNoPrimaryDeviceBanner, object: nil)
    }

    /// Promote this device from secondary to primary
    /// Should only be called when no other primary device exists
    func promoteThisDeviceToPrimary() async throws {
        // 1. Get current device
        guard let currentDevice = try await getCurrentDevice() else {
            throw MigrationError.deviceNotFound
        }
        
        // 2. Verify we are NOT currently primary
        guard !currentDevice.isPrimaryDevice else {
            throw MigrationError.alreadyPrimary
        }
        
        // 3. Check if another primary device already exists for this wallet
        let existingPrimary = try await getPrimaryDevice(walletHash: currentDevice.walletHash)
        if existingPrimary != nil {
            throw MigrationError.primaryDeviceAlreadyExists
        }

        // 4. Update current device to be primary
        currentDevice.isPrimaryDevice = true
        currentDevice.becamePrimaryAt = Date()

        // 5. Save to CloudKit
        try modelContext?.save()

        // 6. Update iCloud KV Store for faster sync
        writeOwnPrimaryFlag(true, deviceId: currentDevice.deviceId)

        // 7. Clear any demotion flags
        UserDefaults.standard.removeObject(forKey: "device_\(currentDevice.deviceId)_wasDemoted")

        // 8. Signal to WalletManager to initialize as primary
        // WalletManager's observeMigrationNotifications() handler will:
        // - Call initialize(forceReadOnly: false)
        // - Which triggers initializePrimaryMode() to:
        //   * Open the wallet
        //   * Restore from backup if needed
        //   * Load all wallet data
        //   * Start all background services (exit, round, vtxo progression)
        //   * Start wallet notification service
        //   * Register for push notifications
        NotificationCenter.default.post(name: .devicePromotedToPrimary, object: nil)

        Self.logger.info("Device promoted to primary")
    }

    /// Check if there is currently no primary device
    /// Returns true if no active device has isPrimaryDevice = true
    /// Scoped to this device's wallet when known - a stale primary registration
    /// from another (test) wallet must not mask a missing primary here
    func checkForNoPrimaryDevice() async throws -> Bool {
        guard modelContext != nil else {
            throw DeviceRegistrationError.noModelContext
        }

        let walletHash = (try? await getCurrentDevice())?.walletHash
        return try await getPrimaryDevice(walletHash: walletHash) == nil
    }

    // MARK: - Primary Conflict Reconciliation

    /// Resolves duplicate-primary states by self-demotion.
    ///
    /// Registration coordinates over eventually-consistent iCloud channels, so two
    /// devices can transiently both believe they are primary (e.g. the same seed
    /// imported on two devices before either synced the other's claim). Each device
    /// only ever demotes ITSELF - it owns its record, so there are no CloudKit write
    /// conflicts - and all devices apply the same deterministic winner rule, so the
    /// system converges as soon as the conflicting records are mutually visible.
    func reconcilePrimaryConflicts() async {
        guard let modelContext = modelContext else { return }
        guard let deviceId = try? getOrCreateDeviceId() else { return }

        // A reinstall registers a fresh record before the pre-reinstall record has
        // synced down; once both are visible, collapse them to one.
        dedupeOwnRecords(deviceId: deviceId, in: modelContext)

        let ownDescriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        guard let current = try? modelContext.fetch(ownDescriptor).first,
              current.isPrimaryDevice, current.isActive else {
            // Only a primary device ever needs to consider stepping down
            return
        }

        let walletHash = current.walletHash
        let conflictDescriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate {
                $0.walletHash == walletHash && $0.isPrimaryDevice == true && $0.isActive == true
            }
        )
        guard let primaries = try? modelContext.fetch(conflictDescriptor), primaries.count > 1 else {
            return
        }

        let winnerId = Self.primaryConflictWinner(candidates: primaries.map {
            PrimaryDeviceCandidate(deviceId: $0.deviceId, becamePrimaryAt: $0.becamePrimaryAt, registeredAt: $0.registeredAt)
        })

        guard winnerId != deviceId else {
            Self.logger.warning("⚠️ Primary conflict (\(primaries.count) primaries) - this device wins, expecting others to self-demote")

            // Clear any stale demotion breadcrumbs so the winning claim survives the
            // next launch - shouldBlockWalletAccess reads both before initialization
            writeOwnPrimaryFlag(true, deviceId: deviceId)
            UserDefaults.standard.removeObject(forKey: "device_\(deviceId)_wasDemoted")
            return
        }

        Self.logger.warning("⚠️ Primary conflict (\(primaries.count) primaries) - self-demoting, winner is another device")

        current.isPrimaryDevice = false
        current.demotedAt = Date()
        try? modelContext.save()

        writeOwnPrimaryFlag(false, deviceId: deviceId)

        UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")

        // Close the wallet if it's currently running in primary mode
        NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)

        await loadRegisteredDevices()
    }

    /// Deterministic winner among conflicting primaries: the earliest claim wins
    /// (the incumbent keeps primary; a deliberate takeover goes through the explicit
    /// demote/promote flow), with deviceId as a total-order tiebreaker so every
    /// device independently picks the same winner.
    nonisolated static func primaryConflictWinner(candidates: [PrimaryDeviceCandidate]) -> String? {
        candidates.min { a, b in
            let aDate = a.becamePrimaryAt ?? a.registeredAt
            let bDate = b.becamePrimaryAt ?? b.registeredAt
            if aDate != bDate { return aDate < bDate }
            return a.deviceId < b.deviceId
        }?.deviceId
    }

    /// Removes duplicate registrations for this device (same deviceId).
    /// Keeps the strongest record: primary beats secondary, then most recently seen.
    /// Preferring the primary record deliberately restores primary status after a
    /// reinstall, where the fresh registration was secondary but the pre-reinstall
    /// record (same Keychain deviceId) was primary.
    private func dedupeOwnRecords(deviceId: String, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DeviceRegistration>(
            predicate: #Predicate { $0.deviceId == deviceId }
        )
        guard let records = try? modelContext.fetch(descriptor), records.count > 1 else { return }

        let sorted = records.sorted { a, b in
            if a.isPrimaryDevice != b.isPrimaryDevice { return a.isPrimaryDevice }
            return a.lastSeenAt > b.lastSeenAt
        }
        for stale in sorted.dropFirst() {
            modelContext.delete(stale)
        }
        try? modelContext.save()

        if let survivor = sorted.first, survivor.isPrimaryDevice {
            // Restoring primary from the pre-reinstall record: the fresh secondary
            // registration wrote device_<id>_isPrimary = false, which
            // shouldBlockWalletAccess treats as a demotion at every launch. Reset
            // the flag to match the surviving record or the device wedges in
            // read-only despite being primary.
            writeOwnPrimaryFlag(true, deviceId: deviceId)
            UserDefaults.standard.removeObject(forKey: "device_\(deviceId)_wasDemoted")
        }

        Self.logger.warning("Deduplicated \(records.count - 1) duplicate registration(s) for this device")
    }

    // MARK: - Fast Device Registry (NSUbiquitousKeyValueStore)

    /// Local breadcrumb recording that *this* device wrote its own KVS primary
    /// flag, and what it wrote.
    ///
    /// Every writer of `device_<id>_isPrimary` in this file targets this device's
    /// own ID — nothing anywhere writes another device's flag, and promote/demote
    /// act only on the current device. `WalletManager.shouldBlockWalletAccess`
    /// layer 2 reads that flag to catch a demotion, so without this breadcrumb it
    /// cannot tell a demotion from its own registration having written `false`
    /// seconds earlier, and logged a fresh secondary's perfectly normal
    /// registration as "🛑 iCloud KV store indicates demotion".
    ///
    /// Deliberately local (UserDefaults, not KVS): it records what happened on
    /// this device, and syncing it would make it answer a different question.
    nonisolated static func selfWrotePrimaryFlagKey(deviceId: String) -> String {
        "device_\(deviceId)_selfWroteIsPrimary"
    }

    /// Mirrors this device's primary status to iCloud KVS and leaves the
    /// breadcrumb. Use this rather than writing the flag directly.
    private func writeOwnPrimaryFlag(_ isPrimary: Bool, deviceId: String) {
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.set(isPrimary, forKey: "device_\(deviceId)_isPrimary")
        kvStore.synchronize()

        UserDefaults.standard.set(isPrimary, forKey: Self.selfWrotePrimaryFlagKey(deviceId: deviceId))
    }

    /// Registers a device in the fast KV store registry
    /// This syncs much faster than CloudKit and prevents race conditions during app reinstall
    private func registerDeviceInKVStore(deviceId: String, walletHash: String) {
        let kvStore = NSUbiquitousKeyValueStore.default
        let key = "\(Self.registeredDevicesPrefix)\(walletHash).\(deviceId)"
        
        // Store timestamp when device was registered
        kvStore.set(Date().timeIntervalSince1970, forKey: key)
        kvStore.synchronize()
        
        Self.logger.debug("Registered device in KV store: \(deviceId)")
    }
    
    /// Every fast-mirror key belonging to a device, across all wallet hashes.
    ///
    /// Pure and testable. Keys are `com.arke.device.registered.<walletHash>.<deviceId>`;
    /// wallet hashes are base64 (no dots) and device IDs are UUIDs (no dots), so
    /// matching the `.<deviceId>` suffix isolates the device exactly — the same
    /// reasoning `otherRegisteredDeviceIds` relies on from the other end.
    nonisolated static func mirrorKeys(forDeviceId deviceId: String, in kvsKeys: [String]) -> [String] {
        guard !deviceId.isEmpty else { return [] }
        return kvsKeys.filter { $0.hasPrefix(registeredDevicesPrefix) && $0.hasSuffix(".\(deviceId)") }
    }

    /// Removes a device's fast-mirror entries for every wallet hash.
    /// - Returns: how many entries were removed, for logging.
    @discardableResult
    private func removeMirrorEntries(deviceId: String) -> Int {
        let kvStore = NSUbiquitousKeyValueStore.default
        let keys = Self.mirrorKeys(forDeviceId: deviceId, in: Array(kvStore.dictionaryRepresentation.keys))

        for key in keys {
            kvStore.removeObject(forKey: key)
        }
        if !keys.isEmpty {
            kvStore.synchronize()
        }

        return keys.count
    }

    /// Clears all device registrations from KV store for a specific wallet
    /// Used when importing a wallet fresh with mnemonic + backup to avoid conflicts
    func clearDeviceRegistrationsFromKVStore(walletHash: String) {
        let kvStore = NSUbiquitousKeyValueStore.default
        let allKeys = kvStore.dictionaryRepresentation.keys
        let prefix = "\(Self.registeredDevicesPrefix)\(walletHash)."
        
        // Find and remove all keys for this wallet
        let keysToRemove = allKeys.filter { $0.hasPrefix(prefix) }
        
        for key in keysToRemove {
            kvStore.removeObject(forKey: key)
        }
        
        kvStore.synchronize()
        
        Self.logger.debug("Cleared \(keysToRemove.count) device registration(s) from KV store for wallet")
    }
    
    // `cleanupKVStoreRegistry()` was deleted 2026-09-25. It removed any OTHER
    // device's mirror entry whose SwiftData row was locally absent — which is
    // exactly the CloudKit-import-lag condition the mirror exists to survive
    // (a fresh install's row can take seconds to never to arrive). One future
    // caller would have deleted live devices' blocking evidence and re-opened
    // the account-wide seed-wipe hole. Any future mirror pruning must go
    // through the per-blocker unlink flow, where the user names the device.
}

// MARK: - Supporting Types

/// Pure-data view of a primary-conflict candidate, extracted for testability
struct PrimaryDeviceCandidate {
    let deviceId: String
    let becamePrimaryAt: Date?
    let registeredAt: Date
}

/// Pure-data view of a device-registry row, extracted for testability: the
/// SwiftData model can't be built without a container, and the merge rules in
/// `otherDeviceReport` are the part worth testing.
nonisolated struct RegistryDeviceSnapshot: Equatable, Sendable {
    let deviceId: String
    let deviceName: String
    let walletHash: String
    let lastSeenAt: Date
    let isActive: Bool
}

/// Another device that the account says still holds this wallet.
///
/// Merged from the two stores that disagree in practice: the CloudKit-backed
/// SwiftData registry, which has names and heartbeats but converges slowly, and
/// the iCloud KVS mirror, which has neither but converges first and is what the
/// deletion decision must not ignore.
nonisolated struct OtherWalletDevice: Equatable, Identifiable, Sendable {
    enum Source: Equatable, Sendable {
        /// Backed by an active registry row for this wallet, so it has a name, a
        /// heartbeat, and `unlinkDevice` can remove it.
        case registry
        /// Present only in the KVS mirror. Either the CloudKit row hasn't
        /// imported yet (seconds to never, when offline) or it never will,
        /// because the row was deleted without its mirror entry. `unlinkDevice`
        /// cannot clear these: it throws `deviceNotFound` with no row to delete.
        case kvsOnly
    }

    let deviceId: String
    /// `nil` when no registry row anywhere carries a name for this device — the
    /// honest state for a mirror entry whose row never arrived. A `.kvsOnly`
    /// device can still be named if an inactive or foreign-wallet row knows it.
    let deviceName: String?
    /// Last heartbeat. Registry-backed devices only.
    let lastSeenAt: Date?
    /// When the device last *registered*. This is what the mirror stores, and it
    /// is NOT a heartbeat — registration writes it and heartbeats never refresh
    /// it, which is why mirror entries cannot be aged out (S7).
    let registeredAt: Date?
    /// Heartbeat older than the staleness threshold. Always `false` for
    /// `.kvsOnly`, where staleness is unknowable rather than known to be false.
    let isStale: Bool
    let source: Source

    var id: String { deviceId }
}

/// The answer to "is this really the last device?", with its reasons intact.
///
/// Replaces a `Bool` that could not explain itself: the delete flow used it to
/// tell the user "your other devices keep access" while Linked Devices, reading
/// the other store, said there was only one device. Anything shown to the user
/// about blocking devices must come from here, so the two surfaces cannot drift
/// apart again.
nonisolated struct OtherDeviceReport: Equatable, Sendable {
    /// Every device that keeps a deletion local, most recently heard from first.
    let others: [OtherWalletDevice]

    /// The registry could not be read at all. `others` then holds mirror entries
    /// only, so its contents are a floor, not a total.
    let registryUnreadable: Bool

    /// Whether anything at all blocks treating this as the last device.
    var hasOthers: Bool { !others.isEmpty }

    /// Blockers with an active registry row — the ones `unlinkDevice` can clear.
    var unlinkable: [OtherWalletDevice] { others.filter { $0.source == .registry } }

    /// Blockers that exist only in the mirror. These have no remedy in today's
    /// delete flow and are why the informed override is load-bearing.
    var mirrorOnly: [OtherWalletDevice] { others.filter { $0.source == .kvsOnly } }
}

// MARK: - Error Types

enum DeviceRegistrationError: LocalizedError {
    case noModelContext
    case keychainError(OSStatus)
    case encodingFailed
    case deviceNotRegistered
    case deviceNotFound
    
    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "Model context not available"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode device ID"
        case .deviceNotRegistered:
            return "Device not registered"
        case .deviceNotFound:
            return "Device not found"
        }
    }
}

enum MigrationError: LocalizedError {
    case notPrimaryDevice
    case alreadyPrimary
    case deviceNotFound
    case cloudKitSyncFailed
    case backupFailed
    case primaryDeviceAlreadyExists
    
    var errorDescription: String? {
        switch self {
        case .notPrimaryDevice:
            return "This device is not currently primary"
        case .alreadyPrimary:
            return "This device is already primary"
        case .deviceNotFound:
            return "Could not find current device"
        case .cloudKitSyncFailed:
            return "Failed to sync with iCloud"
        case .backupFailed:
            return "Failed to backup wallet"
        case .primaryDeviceAlreadyExists:
            return "Another device is already set as primary. Demote that device first before promoting this one."
        }
    }
}
