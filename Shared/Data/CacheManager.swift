//
//  CacheManager.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import ArkeUI

/// Generic cache manager that handles caching with configurable timeouts
@MainActor
class CacheManager<T> {
    private var cachedValue: T?
    private var cacheTime: Date?
    private let cacheTimeout: TimeInterval
    
    init(timeout: TimeInterval) {
        self.cacheTimeout = timeout
    }
    
    /// Get cached value if it's still valid, otherwise nil
    var value: T? {
        guard let cached = cachedValue,
              let time = cacheTime,
              Date().timeIntervalSince(time) < cacheTimeout else {
            return nil
        }
        return cached
    }

    /// The most recently cached value regardless of the timeout, for callers
    /// that can extrapolate from a stale value (block height estimation).
    var lastKnownValue: T? {
        cachedValue
    }
    
    /// Check if cache is valid
    var isValid: Bool {
        guard let _ = cachedValue,
              let time = cacheTime,
              Date().timeIntervalSince(time) < cacheTimeout else {
            return false
        }
        return true
    }
    
    /// Set a new cached value
    func setValue(_ value: T) {
        self.cachedValue = value
        self.cacheTime = Date()
    }
    
    /// Clear the cache
    func clear() {
        self.cachedValue = nil
        self.cacheTime = nil
    }
    
    /// Get cached value or execute the provider if cache is invalid
    func get(provider: () async throws -> T) async throws -> T {
        if let cached = value {
            return cached
        }
        
        let newValue = try await provider()
        setValue(newValue)
        return newValue
    }
    
    /// Get cached value or execute the provider if cache is invalid (no-throw version)
    func get(provider: () async -> T) async -> T {
        if let cached = value {
            return cached
        }
        
        let newValue = await provider()
        setValue(newValue)
        return newValue
    }
}

/// Specialized cache managers for wallet data
@MainActor
class WalletCacheManager {
    
    /// Cache for block height (1 minute timeout)
    let blockHeight = CacheManager<Int>(timeout: 60)
    
    /// Cache for Ark info (5 minutes timeout)
    let arkInfo = CacheManager<ArkInfoModel>(timeout: 300)
    
    /// Estimated current block height: the last fetched height plus the
    /// blocks that have probably been mined since, at the average block
    /// interval. Works from the last *known* height, not the still-valid
    /// cache — this used to read `blockHeight.value`, which is nil once the
    /// 60s timeout passes, so every synchronous reader (the hourly
    /// auto-refresh check, reminder scheduling) saw nil almost all the time.
    /// It also advanced by the Ark round interval instead of block time.
    /// Returns nil only when no height has ever been fetched.
    func getEstimatedBlockHeight() -> Int? {
        guard let lastHeight = blockHeight.lastKnownValue else {
            return nil
        }
        guard let cacheTime = blockHeight.cacheTimestamp else {
            return lastHeight
        }
        
        let secondsElapsed = max(0, Date().timeIntervalSince(cacheTime))
        let blocksElapsed = Int(secondsElapsed) / BlockTimeFormatter.secondsPerBlock
        
        return lastHeight + blocksElapsed
    }
}

// Extension to expose cache time for estimation calculations
extension CacheManager {
    var cacheTimestamp: Date? {
        return self.cacheTime
    }
}