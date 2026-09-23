//
//  ReadOnlyAddressService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import SwiftData

/// Read-only version of AddressService for secondary devices
/// Only reads addresses from SwiftData (synced via CloudKit), cannot generate new ones
@MainActor
@Observable
class ReadOnlyAddressService {

    // MARK: - Properties

    /// Current Ark address (cached for quick access)
    var arkAddress: String = ""

    /// Current onchain address (cached for quick access)
    var onchainAddress: String = ""

    /// Error message if address operations fail
    var error: String?

    // MARK: - Private Properties

    private let modelContext: ModelContext

    /// Token for the CloudKit change observer, so it is only installed once
    @ObservationIgnored private var cloudKitChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Load cached addresses immediately
        updateCachedAddresses()

        observeCloudKitChanges()
    }

    // MARK: - CloudKit Change Observation

    /// Re-reads the address rows whenever CloudKit imports records mid-session.
    /// Like the balances, these are read once at init, which on a fresh install
    /// happens before the first import lands — leaving the receive screen empty
    /// for the rest of the session (2026-09-23, second iPhone).
    /// CloudKitObserver already debounces the underlying remote-change
    /// notifications.
    private func observeCloudKitChanges() {
        guard cloudKitChangeObserver == nil else { return }

        cloudKitChangeObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCachedAddresses()
            }
        }
    }

    // MARK: - Public Methods

    /// Load addresses from SwiftData (CloudKit-synced)
    func loadAddresses() async {
        updateCachedAddresses()
    }

    /// Refresh addresses by reloading from database
    func refreshAddresses() async {
        updateCachedAddresses()
    }

    /// Clear cached addresses
    func clearAddresses() {
        arkAddress = ""
        onchainAddress = ""
        error = nil
    }

    // MARK: - Private Methods

    /// Update cached address values from database
    private func updateCachedAddresses() {
        // Get most recent Ark address
        if let arkAddr = getMostRecentArkAddress() {
            arkAddress = arkAddr.address
            print("📍 [ReadOnlyAddressService] Loaded Ark address from database: \(arkAddress)")
        } else {
            arkAddress = ""
            print("⚠️ [ReadOnlyAddressService] No Ark address found in database")
        }

        // Get most recent unused onchain address (or most recent if all used)
        if let onchainAddr = getUnusedOnchainAddress() ?? getMostRecentOnchainAddress() {
            onchainAddress = onchainAddr.address
            print("📍 [ReadOnlyAddressService] Loaded onchain address from database: \(onchainAddress)")
        } else {
            onchainAddress = ""
            print("⚠️ [ReadOnlyAddressService] No onchain address found in database")
        }
    }

    /// Get most recent Ark address from database
    private func getMostRecentArkAddress() -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate { $0.addressType == "ark" && $0.isActive },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Get most recent onchain address from database
    private func getMostRecentOnchainAddress() -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate { $0.addressType == "onchain" && $0.isActive },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Get first unused onchain address from database
    private func getUnusedOnchainAddress() -> PersistentAddress? {
        let descriptor = FetchDescriptor<PersistentAddress>(
            predicate: #Predicate { $0.addressType == "onchain" && $0.isActive && !$0.isUsed },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }
}
