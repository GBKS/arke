//
//  BIP353Resolver.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/20/25.
//
//  BIP-353: DNS Payment Instructions
//  Resolves human-readable Bitcoin addresses to BIP-21 URIs via DNS TXT records
//

import Foundation
import dnssd

// MARK: - fd_set helpers for select()

private func fdZero(_ set: inout fd_set) {
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int32(fd % 32)
    let mask: Int32 = 1 << bitOffset
    switch intOffset {
    case 0: set.fds_bits.0 = set.fds_bits.0 | mask
    case 1: set.fds_bits.1 = set.fds_bits.1 | mask
    case 2: set.fds_bits.2 = set.fds_bits.2 | mask
    case 3: set.fds_bits.3 = set.fds_bits.3 | mask
    case 4: set.fds_bits.4 = set.fds_bits.4 | mask
    case 5: set.fds_bits.5 = set.fds_bits.5 | mask
    case 6: set.fds_bits.6 = set.fds_bits.6 | mask
    case 7: set.fds_bits.7 = set.fds_bits.7 | mask
    case 8: set.fds_bits.8 = set.fds_bits.8 | mask
    case 9: set.fds_bits.9 = set.fds_bits.9 | mask
    case 10: set.fds_bits.10 = set.fds_bits.10 | mask
    case 11: set.fds_bits.11 = set.fds_bits.11 | mask
    case 12: set.fds_bits.12 = set.fds_bits.12 | mask
    case 13: set.fds_bits.13 = set.fds_bits.13 | mask
    case 14: set.fds_bits.14 = set.fds_bits.14 | mask
    case 15: set.fds_bits.15 = set.fds_bits.15 | mask
    case 16: set.fds_bits.16 = set.fds_bits.16 | mask
    case 17: set.fds_bits.17 = set.fds_bits.17 | mask
    case 18: set.fds_bits.18 = set.fds_bits.18 | mask
    case 19: set.fds_bits.19 = set.fds_bits.19 | mask
    case 20: set.fds_bits.20 = set.fds_bits.20 | mask
    case 21: set.fds_bits.21 = set.fds_bits.21 | mask
    case 22: set.fds_bits.22 = set.fds_bits.22 | mask
    case 23: set.fds_bits.23 = set.fds_bits.23 | mask
    case 24: set.fds_bits.24 = set.fds_bits.24 | mask
    case 25: set.fds_bits.25 = set.fds_bits.25 | mask
    case 26: set.fds_bits.26 = set.fds_bits.26 | mask
    case 27: set.fds_bits.27 = set.fds_bits.27 | mask
    case 28: set.fds_bits.28 = set.fds_bits.28 | mask
    case 29: set.fds_bits.29 = set.fds_bits.29 | mask
    case 30: set.fds_bits.30 = set.fds_bits.30 | mask
    case 31: set.fds_bits.31 = set.fds_bits.31 | mask
    default: break
    }
}

private func fdIsSet(_ fd: Int32, _ set: inout fd_set) -> Bool {
    let intOffset = Int(fd / 32)
    let bitOffset = Int32(fd % 32)
    let mask: Int32 = 1 << bitOffset
    switch intOffset {
    case 0: return set.fds_bits.0 & mask != 0
    case 1: return set.fds_bits.1 & mask != 0
    case 2: return set.fds_bits.2 & mask != 0
    case 3: return set.fds_bits.3 & mask != 0
    case 4: return set.fds_bits.4 & mask != 0
    case 5: return set.fds_bits.5 & mask != 0
    case 6: return set.fds_bits.6 & mask != 0
    case 7: return set.fds_bits.7 & mask != 0
    case 8: return set.fds_bits.8 & mask != 0
    case 9: return set.fds_bits.9 & mask != 0
    case 10: return set.fds_bits.10 & mask != 0
    case 11: return set.fds_bits.11 & mask != 0
    case 12: return set.fds_bits.12 & mask != 0
    case 13: return set.fds_bits.13 & mask != 0
    case 14: return set.fds_bits.14 & mask != 0
    case 15: return set.fds_bits.15 & mask != 0
    case 16: return set.fds_bits.16 & mask != 0
    case 17: return set.fds_bits.17 & mask != 0
    case 18: return set.fds_bits.18 & mask != 0
    case 19: return set.fds_bits.19 & mask != 0
    case 20: return set.fds_bits.20 & mask != 0
    case 21: return set.fds_bits.21 & mask != 0
    case 22: return set.fds_bits.22 & mask != 0
    case 23: return set.fds_bits.23 & mask != 0
    case 24: return set.fds_bits.24 & mask != 0
    case 25: return set.fds_bits.25 & mask != 0
    case 26: return set.fds_bits.26 & mask != 0
    case 27: return set.fds_bits.27 & mask != 0
    case 28: return set.fds_bits.28 & mask != 0
    case 29: return set.fds_bits.29 & mask != 0
    case 30: return set.fds_bits.30 & mask != 0
    case 31: return set.fds_bits.31 & mask != 0
    default: return false
    }
}

/// Resolves BIP-353 human-readable Bitcoin addresses via DNS
class BIP353Resolver {
    
    // MARK: - Types
    
    enum BIP353Format {
        case bitcoinSymbol(String)  // ₿alice.example.com
        case userAtDomain(String)   // alice@example.com (ambiguous with Lightning Address)
    }
    
    struct ResolvedBIP353 {
        let originalAddress: String      // ₿alice.example.com or alice@example.com
        let bip21URI: String             // The bitcoin: URI from DNS TXT record
        let dnssecVerified: Bool         // Whether DNSSEC validation succeeded
        let resolvedFrom: String         // DNS name that was queried
        let resolvedAt: Date             // Timestamp for cache expiration
    }
    
    enum BIP353Error: LocalizedError {
        case invalidFormat
        case noDNSRecord
        case noBitcoinRecord
        case dnsLookupFailed(String)
        case dnssecValidationFailed
        case networkError(Error)
        case cacheExpired
        
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid BIP-353 address format"
            case .noDNSRecord:
                return "No DNS TXT record found for this address"
            case .noBitcoinRecord:
                return "No Bitcoin payment record found in DNS"
            case .dnsLookupFailed(let reason):
                return "DNS lookup failed: \(reason)"
            case .dnssecValidationFailed:
                return "DNSSEC validation failed - address may be compromised"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .cacheExpired:
                return "Cached resolution expired"
            }
        }
    }
    
    // MARK: - Cache
    
    private static var cache: [String: ResolvedBIP353] = [:]
    private static let cacheDuration: TimeInterval = 600 // 10 minutes
    private static let cacheQueue = DispatchQueue(label: "com.ark.bip353cache")
    
    // MARK: - Public API
    
    /// Resolves a BIP-353 address to a BIP-21 URI via DNS lookup
    /// - Parameter address: BIP-353 address (₿alice.example.com or alice@example.com)
    /// - Returns: Resolved BIP-21 URI and metadata
    static func resolve(_ address: String) async throws -> ResolvedBIP353 {
        // Check cache first
        if let cached = getCached(address) {
            return cached
        }
        
        // Detect format
        let format = try detectFormat(address)
        
        // Construct DNS name
        let dnsName = constructDNSName(address, format: format)
        
        print("🔍 [BIP353Resolver] Resolving \(address)")
        print("   → DNS lookup: \(dnsName)")
        
        // Perform DNS TXT lookup
        let txtRecords = try await performDNSLookup(dnsName)
        
        print("   → Found \(txtRecords.count) TXT record(s)")
        
        // BIP-353 requires DNSSEC: without it, whoever answers the DNS query
        // chooses the payee, so an unvalidated record must not be used.
        // Callers fall back to the Lightning Address lookup, which is
        // authenticated by TLS.
        let dnssecValid = await validateDNSSEC(dnsName)
        
        guard dnssecValid else {
            print("   ⚠️ DNSSEC validation failed!")
            throw BIP353Error.dnssecValidationFailed
        }
        
        // Find Bitcoin payment record (BIP-21 URI)
        guard let bip21URI = txtRecords.first(where: { $0.hasPrefix("bitcoin:") }) else {
            throw BIP353Error.noBitcoinRecord
        }
        
        print("   → BIP-21 URI: \(bip21URI)")
        print("   ✅ Resolved successfully")
        
        let resolved = ResolvedBIP353(
            originalAddress: address,
            bip21URI: bip21URI,
            dnssecVerified: dnssecValid,
            resolvedFrom: dnsName,
            resolvedAt: Date()
        )
        
        // Cache the result
        cache(resolved, for: address)
        
        return resolved
    }
    
    /// Check if an address looks like a BIP-353 address
    static func isBIP353Format(_ address: String) -> Bool {
        return detectFormatOrNil(address) != nil
    }
    
    // MARK: - Format Detection
    
    private static func detectFormat(_ address: String) throws -> BIP353Format {
        guard let format = detectFormatOrNil(address) else {
            throw BIP353Error.invalidFormat
        }
        return format
    }
    
    private static func detectFormatOrNil(_ address: String) -> BIP353Format? {
        // Check for ₿ prefix (unambiguous BIP-353)
        if address.hasPrefix("₿") {
            // Match ₿user@domain.com format only
            let pattern = "^₿[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
            if address.range(of: pattern, options: .regularExpression) != nil {
                return .bitcoinSymbol(address)
            }
        }
        
        // Check for user@domain format (ambiguous - could be Lightning Address)
        let userAtDomainPattern = "^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        if address.range(of: userAtDomainPattern, options: .regularExpression) != nil {
            return .userAtDomain(address)
        }
        
        return nil
    }
    
    // MARK: - DNS Name Construction
    
    private static func constructDNSName(_ address: String, format: BIP353Format) -> String {
        switch format {
        case .bitcoinSymbol(let addr):
            // ₿alice@example.com → alice.user._bitcoin-payment.example.com
            let withoutSymbol = String(addr.dropFirst())
            let components = withoutSymbol.split(separator: "@")
            guard components.count == 2 else {
                return "user._bitcoin-payment.\(withoutSymbol)" // Fallback
            }
            return "\(components[0]).user._bitcoin-payment.\(components[1])"
            
        case .userAtDomain(let addr):
            // alice@example.com → alice.user._bitcoin-payment.example.com
            let components = addr.split(separator: "@")
            guard components.count == 2 else {
                return "user._bitcoin-payment.\(addr)" // Fallback
            }
            return "\(components[0]).user._bitcoin-payment.\(components[1])"
        }
    }
    
    // MARK: - DNS Resolution
    
    private static func performDNSLookup(_ dnsName: String) async throws -> [String] {
        // Use native DNS Service Discovery API for TXT record lookup
        // This works on all Apple platforms (iOS, macOS, etc.)
        
        // Helper class to bridge continuation into callback context
        class CallbackContext {
            var continuation: CheckedContinuation<[String], Error>?
            var records: [String] = []
            var hasResumed = false
            let lock = NSLock()
            
            func resume(with result: Result<[String], Error>) {
                lock.lock()
                defer { lock.unlock() }
                
                if !hasResumed {
                    hasResumed = true
                    continuation?.resume(with: result)
                    continuation = nil
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var sdRef: DNSServiceRef?
            let context = CallbackContext()
            context.continuation = continuation
            
            let callback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, _, _, rdlen, rdata, _, contextPtr in
                guard let contextPtr = contextPtr else { return }
                let context = Unmanaged<CallbackContext>.fromOpaque(contextPtr).takeUnretainedValue()
                
                guard errorCode == kDNSServiceErr_NoError else {
                    context.resume(with: .failure(BIP353Error.dnsLookupFailed("DNS error code: \(errorCode)")))
                    return
                }
                
                guard let rdata = rdata else { return }
                
                // Parse TXT record (first byte is length, rest is data)
                let dataPtr = rdata.assumingMemoryBound(to: UInt8.self)
                let length = Int(dataPtr.pointee)
                
                if length > 0 && rdlen > 1 {
                    let txtData = Data(bytes: dataPtr.advanced(by: 1), count: min(length, Int(rdlen) - 1))
                    if let txtString = String(data: txtData, encoding: .utf8) {
                        context.records.append(txtString)
                    }
                }
                
                // Check if this is the last record (MoreComing flag not set)
                if (flags & kDNSServiceFlagsMoreComing) == 0 {
                    context.resume(with: .success(context.records))
                }
            }
            
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            
            let err = DNSServiceQueryRecord(
                &sdRef,
                0, // flags
                0, // interface (0 = all interfaces)
                dnsName,
                UInt16(kDNSServiceType_TXT),
                UInt16(kDNSServiceClass_IN),
                callback,
                contextPtr
            )
            
            guard err == kDNSServiceErr_NoError, let serviceRef = sdRef else {
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
                continuation.resume(throwing: BIP353Error.dnsLookupFailed("Failed to start DNS query: \(err)"))
                return
            }
            
            // Process the DNS query on a background queue
            // We manually ensure thread safety here - both pointers are only accessed
            // in this closure and are properly deallocated in the defer block
            nonisolated(unsafe) let capturedServiceRef = serviceRef
            nonisolated(unsafe) let capturedContextPtr = contextPtr
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    DNSServiceRefDeallocate(capturedServiceRef)
                    Unmanaged<CallbackContext>.fromOpaque(capturedContextPtr).release()
                }
                
                let socketFD = DNSServiceRefSockFD(capturedServiceRef)
                guard socketFD >= 0 else {
                    context.resume(with: .failure(BIP353Error.dnsLookupFailed("Invalid socket")))
                    return
                }
                
                // Set up a timeout
                let timeoutSource = DispatchSource.makeTimerSource(queue: .global())
                timeoutSource.schedule(deadline: .now() + 10.0)
                timeoutSource.setEventHandler {
                    context.resume(with: .failure(BIP353Error.dnsLookupFailed("DNS lookup timeout")))
                }
                timeoutSource.resume()
                
                // Process results
                var fdSetVar = fd_set()
                fdZero(&fdSetVar)
                fdSet(socketFD, &fdSetVar)
                
                var timeout = timeval(tv_sec: 10, tv_usec: 0)
                let selectResult = select(socketFD + 1, &fdSetVar, nil, nil, &timeout)
                
                timeoutSource.cancel()
                
                if selectResult > 0 && fdIsSet(socketFD, &fdSetVar) {
                    let processResult = DNSServiceProcessResult(capturedServiceRef)
                    if processResult != kDNSServiceErr_NoError {
                        context.resume(with: .failure(BIP353Error.dnsLookupFailed("Process error: \(processResult)")))
                    }
                } else {
                    context.resume(with: .failure(BIP353Error.noDNSRecord))
                }
            }
        }
    }
    
    // MARK: - DNSSEC Validation
    
    private static func validateDNSSEC(_ dnsName: String) async -> Bool {
        // TODO: Implement proper DNSSEC validation using dnssd
        // For now, we can't reliably validate DNSSEC on iOS without external libraries
        // The DNSServiceQueryRecord API doesn't expose DNSSEC validation results directly
        // 
        // Options for future implementation:
        // 1. Use a third-party DNS library that supports DNSSEC
        // 2. Query for RRSIG records separately and validate them
        // 3. Use a trusted DNS-over-HTTPS resolver that validates DNSSEC
        //
        // For now, return false to indicate DNSSEC is not verified
        return false
    }
    
    // MARK: - Cache Management
    
    private static func getCached(_ address: String) -> ResolvedBIP353? {
        return cacheQueue.sync {
            guard let cached = cache[address] else { return nil }
            
            // Check if cache is expired (10 minutes)
            let age = Date().timeIntervalSince(cached.resolvedAt)
            if age > cacheDuration {
                cache.removeValue(forKey: address)
                return nil
            }
            
            print("🎯 [BIP353Resolver] Using cached resolution for \(address) (age: \(Int(age))s)")
            return cached
        }
    }
    
    private static func cache(_ resolved: ResolvedBIP353, for address: String) {
        cacheQueue.sync {
            cache[address] = resolved
        }
    }
    
    /// Clear all cached resolutions (for testing or manual refresh)
    static func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
        }
    }
    
    /// Clear cache for a specific address
    static func clearCache(for address: String) {
        cacheQueue.sync {
            _ = cache.removeValue(forKey: address)
        }
    }
}
