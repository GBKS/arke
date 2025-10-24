//
//  CacheManager.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation

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
    
    /// Get estimated block height based on cached data and round interval
    func getEstimatedBlockHeight() -> Int? {
        guard let cachedHeight = blockHeight.value,
              let arkInfoValue = arkInfo.value,
              let roundIntervalSeconds = arkInfoValue.roundIntervalSeconds,
              let cacheTime = blockHeight.cacheTimestamp else {
            return blockHeight.value // Return cached value if we can't estimate
        }
        
        let secondsElapsed = Date().timeIntervalSince(cacheTime)
        let roundsElapsed = Int(secondsElapsed) / roundIntervalSeconds
        
        return cachedHeight + roundsElapsed
    }
}

// Extension to expose cache time for estimation calculations
extension CacheManager {
    var cacheTimestamp: Date? {
        return self.cacheTime
    }
}