//
//  CloudKitObserver.swift
//  Arké mobile
//
//  Created by Assistant on 12/3/25.
//

import SwiftUI
import SwiftData
import CoreData
import Combine

/// Observes CloudKit remote change notifications and triggers SwiftData refreshes
/// This enables real-time sync across devices when changes are made
/// Works on both iOS and macOS
@Observable
final class CloudKitObserver {
    private var cancellables = Set<AnyCancellable>()
    private let modelContainer: ModelContainer
    
    // Debouncing and deduplication state
    private var lastChangeTimestamp: Date?
    private let minimumChangeInterval: TimeInterval = 2.0 // Space handled changes at least this far apart
    private var pendingChangeTask: Task<Void, Never>?

    /// A change that arrived too soon after the last handled one and is
    /// waiting out the remainder of `minimumChangeInterval`. One at a time:
    /// everything arriving while it waits is covered by it.
    private var deferredChangeTask: Task<Void, Never>?
    
    /// Initialize and start observing CloudKit remote changes
    /// - Parameter modelContainer: The ModelContainer to refresh when changes arrive
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        startObserving()
    }
    
    /// Start listening for CloudKit remote change notifications
    private func startObserving() {
        // Observe NSPersistentStoreRemoteChange notifications from Core Data
        // These are posted when CloudKit pushes changes from other devices
        // Using the actual Core Data system notification instead of a custom string
        // Apply debouncing at the publisher level to batch rapid changes
        NotificationCenter.default
            .publisher(for: NSNotification.Name.NSPersistentStoreRemoteChange)
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main) // Batch changes within 1.5s window
            .sink { [weak self] notification in
                self?.handleRemoteChange(notification)
            }
            .store(in: &cancellables)
        
        print("🌥️ [CloudKit] Started observing remote changes (debounced: 1.5s)")
        print("📡 [CloudKit] Listening for: \(NSNotification.Name.NSPersistentStoreRemoteChange.rawValue)")
    }
    
    /// Handle incoming CloudKit remote change notifications
    private func handleRemoteChange(_ notification: Notification) {
        // Rate-limit handled changes — but defer the ones that arrive too
        // soon, never drop them. The publisher above only emits after 1.5s of
        // quiet, so consecutive emissions are always ≥1.5s apart, which put
        // the whole 1.5–2.0s band inside the old early-return: those batches
        // were discarded outright and stayed invisible until some later,
        // unrelated change. Anything refreshed *only* by
        // `cloudKitDataDidChange` inherited that hole — which is most of the
        // read-only device path (balances, addresses, device registry).
        // `@Query`-backed UI was unaffected, hence "tags updated but the
        // balance didn't".
        let now = Date()
        switch RemoteChangeThrottle.decide(
            now: now,
            lastHandled: lastChangeTimestamp,
            minimumInterval: minimumChangeInterval,
            deferralPending: deferredChangeTask != nil
        ) {
        case .handleNow:
            // A due notification supersedes any still-pending deferral: without
            // this, the deferred task fires moments later and runs a second
            // processChange inside the minimum interval this class enforces.
            deferredChangeTask?.cancel()
            deferredChangeTask = nil
        case .coalesceIntoPendingDeferral:
            print("🔁 [CloudKit] Rapid-fire notification folded into the pending deferred refresh")
            return
        case .deferBy(let delay):
            print("⏳ [CloudKit] Rapid-fire notification deferred \(String(format: "%.2f", delay))s (was within \(minimumChangeInterval)s of last change)")
            // Deliberately doesn't capture `notification` (not Sendable, and
            // only its description was ever used) — the deferred run posts the
            // same change-happened signal either way.
            deferredChangeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.deferredChangeTask = nil
                self.processChange(source: "deferred")
            }
            return
        }

        print("📦 [CloudKit] Notification object: \(String(describing: notification.object))")
        processChange(source: "immediate")
    }

    /// Marks the change handled and posts to the cache-holding services after
    /// a short merge delay.
    private func processChange(source: String) {
        lastChangeTimestamp = Date()

        print("🌥️ [CloudKit] Remote change detected (\(source)) - refreshing data")

        // Cancel any pending change task to avoid duplicate notifications
        pendingChangeTask?.cancel()

        // SwiftData automatically merges remote changes from CloudKit
        // We just need to notify observers that data has changed
        pendingChangeTask = Task { @MainActor in
            // Small delay to let SwiftData finish merging changes
            try? await Task.sleep(for: .milliseconds(100))
            
            guard !Task.isCancelled else {
                print("⏭️ [CloudKit] Change notification cancelled (superseded by newer change)")
                return
            }
            
            // SwiftData's ModelContext automatically receives updates from the persistent store
            // when CloudKit pushes changes. @Query properties will update automatically.
            // We just post a notification for any services that maintain their own caches.
            
            print("✅ [CloudKit] Data refreshed from remote changes")
            
            // Post notification for services to refresh their cached data
            NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
            print("📢 [CloudKit] Posted cloudKitDataDidChange notification")
            
            self.pendingChangeTask = nil
        }
    }
    
    deinit {
        pendingChangeTask?.cancel()
        deferredChangeTask?.cancel()
        cancellables.removeAll()
        print("🌥️ [CloudKit] Stopped observing remote changes")
    }
}

// MARK: - Remote Change Throttle

/// The rate-limiting decision for an incoming remote-change notification,
/// extracted so it can be pinned by tests without waiting on real clocks
/// (`ReadOnlySyncedDataTests`).
enum RemoteChangeThrottle {

    enum Decision: Equatable {
        /// Enough time has passed (or nothing has been handled yet) — handle it.
        case handleNow
        /// Too soon; handle it once this much time has passed.
        case deferBy(TimeInterval)
        /// Too soon, and a deferred run is already scheduled — that run covers
        /// this notification, so scheduling a second one would only duplicate
        /// the work.
        case coalesceIntoPendingDeferral
    }

    /// - Parameters:
    ///   - now: Arrival time of the notification.
    ///   - lastHandled: When a change was last *handled* (not last received);
    ///     nil before the first one.
    ///   - minimumInterval: Smallest gap allowed between handled changes.
    ///   - deferralPending: Whether a deferred run is already scheduled.
    static func decide(
        now: Date,
        lastHandled: Date?,
        minimumInterval: TimeInterval,
        deferralPending: Bool
    ) -> Decision {
        guard let lastHandled else { return .handleNow }

        let elapsed = now.timeIntervalSince(lastHandled)
        guard elapsed < minimumInterval else { return .handleNow }

        // A clock that jumped backwards would otherwise produce a deferral
        // longer than the interval itself
        guard elapsed >= 0 else {
            return deferralPending ? .coalesceIntoPendingDeferral : .deferBy(minimumInterval)
        }

        if deferralPending { return .coalesceIntoPendingDeferral }
        return .deferBy(minimumInterval - elapsed)
    }
}

// MARK: - Notification.Name Extension

extension Notification.Name {
    /// Custom notification posted after CloudKit remote changes have been processed
    /// Services can observe this to refresh their cached data
    static let cloudKitDataDidChange = Notification.Name("cloudKitDataDidChange")
}
