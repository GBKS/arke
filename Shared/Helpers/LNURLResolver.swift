//
//  LNURLResolver.swift
//  Arké
//
//  LNURL-pay protocol resolver
//  Decodes bech32-encoded LNURL strings and fetches payment parameters
//

import Foundation
import OSLog

/// Resolves LNURL-pay endpoints and fetches payment parameters
class LNURLResolver {
    
    // MARK: - Logger
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "LNURLResolver")
    
    // MARK: - Types
    
    struct ResolvedLNURL {
        let originalLNURL: String      // Original lnurl1... string
        let callback: String            // URL to request invoice from
        let minSendable: Int            // Minimum amount in millisatoshis
        let maxSendable: Int            // Maximum amount in millisatoshis
        let metadata: String?           // LNURL metadata JSON string
        let commentAllowed: Int?        // Max comment length allowed
        let tag: String                 // Should be "payRequest"
        let resolvedAt: Date            // Timestamp for cache expiration
        
        /// Minimum sendable amount in satoshis
        var minSendableSats: Int { minSendable / 1000 }
        
        /// Maximum sendable amount in satoshis
        var maxSendableSats: Int { maxSendable / 1000 }
        
        /// Whether this is a fixed-amount LNURL (min == max)
        /// Common for point-of-sale systems where the amount is predetermined
        var isFixedAmount: Bool { minSendable == maxSendable }
        
        /// The fixed amount in satoshis (only valid if isFixedAmount is true)
        var fixedAmountSats: Int? {
            isFixedAmount ? minSendableSats : nil
        }

        /// Human-readable description parsed from the LUD-06 metadata, if any.
        /// Prefers the short `text/plain` description, falling back to `text/long-desc`.
        var descriptionText: String? {
            guard let metadata = metadata else { return nil }
            return LNURLResolver.extractDescription(fromMetadata: metadata)
        }
    }
    
    enum LNURLError: LocalizedError {
        case invalidFormat
        case decodingFailed
        case networkError(Error)
        case invalidResponse
        case notLNURLPay
        case serverError(String)
        case notHTTPS
        
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid LNURL format"
            case .decodingFailed:
                return "Failed to decode LNURL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from LNURL endpoint"
            case .notLNURLPay:
                return "Endpoint does not support LNURL-pay"
            case .serverError(let message):
                return "Server error: \(message)"
            case .notHTTPS:
                return "LNURL must decode to HTTPS URL"
            }
        }
    }
    
    // MARK: - Cache
    
    private static var cache: [String: ResolvedLNURL] = [:]
    private static let cacheDuration: TimeInterval = 600  // 10 minutes
    private static let cacheQueue = DispatchQueue(label: "com.ark.lnurlcache")
    
    // MARK: - Public API
    
    /// Check if a string looks like an LNURL (lnurl1... prefix)
    static func isLNURL(_ string: String) -> Bool {
        return string.lowercased().hasPrefix("lnurl1")
    }
    
    /// Decode a bech32-encoded LNURL to an HTTPS URL
    static func decode(_ lnurl: String) throws -> URL {
        let lowercased = lnurl.lowercased()
        
        // Validate prefix
        guard lowercased.hasPrefix("lnurl1") else {
            logger.error("Invalid prefix (doesn't start with 'lnurl1')")
            throw LNURLError.invalidFormat
        }
        
        // Use bech32 decoder (same logic as LightningInvoiceParser)
        guard let (hrp, data5) = bech32Decode(lowercased) else {
            logger.error("Bech32 decode failed")
            throw LNURLError.decodingFailed
        }
        
        logger.debug("Bech32 decoded: hrp=\(hrp), data length=\(data5.count)")
        
        // Strip the 6-character checksum from the end (bech32 includes checksum in data)
        guard data5.count > 6 else {
            logger.error("Data too short (need > 6 bytes for checksum)")
            throw LNURLError.decodingFailed
        }
        let dataWithoutChecksum = Array(data5.dropLast(6))
        logger.debug("Stripped checksum, payload length=\(dataWithoutChecksum.count)")
        
        // Convert 5-bit groups to 8-bit bytes
        guard let bytes = convertBits(from: dataWithoutChecksum, fromBits: 5, toBits: 8, pad: false) else {
            logger.error("Bit conversion failed")
            throw LNURLError.decodingFailed
        }
        
        logger.debug("Converted to \(bytes.count) bytes")
        
        // Decode as UTF-8 string
        guard let urlString = String(bytes: bytes, encoding: .utf8) else {
            logger.error("UTF-8 decoding failed")
            throw LNURLError.decodingFailed
        }
        
        logger.debug("Decoded URL string: \(urlString)")
        
        // Parse as URL
        guard let url = URL(string: urlString) else {
            logger.error("URL parsing failed")
            throw LNURLError.decodingFailed
        }
        
        // Validate HTTPS only (security requirement)
        guard url.scheme == "https" else {
            logger.error("URL scheme is not HTTPS: \(url.scheme ?? "nil")")
            throw LNURLError.notHTTPS
        }
        
        return url
    }
    
    /// Resolve an LNURL-pay endpoint to get payment parameters
    static func resolve(_ lnurl: String) async throws -> ResolvedLNURL {
        // Check cache first
        if let cached = getCached(lnurl) {
            return cached
        }
        
        logger.info("Resolving LNURL: \(lnurl)")
        
        // Decode LNURL to URL
        let url = try decode(lnurl)
        
        logger.debug("Decoded to: \(url.absoluteString)")
        
        // Fetch LNURL-pay response
        let resolved = try await fetchLNURLPayResponse(lnurl: lnurl, url: url)
        
        logger.debug("Callback: \(resolved.callback)")
        logger.debug("Min: \(resolved.minSendableSats) sats, Max: \(resolved.maxSendableSats) sats")
        logger.info("Resolved successfully")
        
        // Cache the result
        cache(resolved, for: lnurl)
        
        return resolved
    }
    
    // MARK: - Metadata Parsing

    /// Extracts a human-readable description from LUD-06 metadata JSON.
    ///
    /// The metadata is a JSON-encoded array of `[type, content]` pairs, e.g.
    /// `[["text/plain", "Coffee"], ["text/long-desc", "..."], ["image/png;base64", "..."]]`.
    /// Prefers the short `text/plain` entry; falls back to `text/long-desc` if the short
    /// description is missing or empty. Images are ignored.
    ///
    /// - Parameter metadata: The raw metadata JSON string from an LNURL-pay response.
    /// - Returns: A trimmed description string, or nil if none is usable.
    static func extractDescription(fromMetadata metadata: String) -> String? {
        guard let data = metadata.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return nil
        }

        func firstContent(forType type: String) -> String? {
            for entry in entries where entry.count >= 2 {
                if let entryType = entry[0] as? String, entryType == type,
                   let content = entry[1] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        return firstContent(forType: "text/plain") ?? firstContent(forType: "text/long-desc")
    }

    // MARK: - Bech32 Decoding (from LightningInvoiceParser)
    
    private static let bech32Charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    
    private static func bech32Decode(_ input: String) -> (hrp: String, data: [UInt8])? {
        let lower = input.lowercased()
        guard let pos = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[..<pos])
        let dataPart = lower[lower.index(after: pos)...]
        var data = [UInt8]()
        for ch in dataPart {
            guard let idx = bech32Charset.firstIndex(of: ch) else { return nil }
            data.append(UInt8(idx))
        }
        return (hrp, data)
    }
    
    private static func convertBits(from data: [UInt8], fromBits: Int = 5, toBits: Int = 8, pad: Bool = false) -> [UInt8]? {
        var acc = 0
        var bits = 0
        let maxv = (1 << toBits) - 1
        var ret = [UInt8]()
        for value in data {
            if (value >> fromBits) != 0 { return nil }
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                let v = (acc >> bits) & maxv
                ret.append(UInt8(v))
            }
        }
        if pad {
            if bits > 0 {
                let v = (acc << (toBits - bits)) & maxv
                ret.append(UInt8(v))
            }
        } else {
            if bits >= fromBits { return nil }
            if ((acc << (toBits - bits)) & maxv) != 0 { return nil }
        }
        return ret
    }
    
    // MARK: - Network Request
    
    private static func fetchLNURLPayResponse(lnurl: String, url: URL) async throws -> ResolvedLNURL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LNURLError.networkError(error)
        }
        
        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw LNURLError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LNURLError.invalidResponse
        }
        
        // Check for error response
        if let status = json["status"] as? String, status == "ERROR" {
            let reason = json["reason"] as? String ?? "Unknown error"
            throw LNURLError.serverError(reason)
        }
        
        // Validate tag is "payRequest"
        guard let tag = json["tag"] as? String, tag == "payRequest" else {
            throw LNURLError.notLNURLPay
        }
        
        // Extract required fields
        guard let callback = json["callback"] as? String,
              let minSendable = json["minSendable"] as? Int,
              let maxSendable = json["maxSendable"] as? Int else {
            throw LNURLError.invalidResponse
        }
        
        // Extract optional fields
        let metadata = json["metadata"] as? String
        let commentAllowed = json["commentAllowed"] as? Int
        
        return ResolvedLNURL(
            originalLNURL: lnurl,
            callback: callback,
            minSendable: minSendable,
            maxSendable: maxSendable,
            metadata: metadata,
            commentAllowed: commentAllowed,
            tag: tag,
            resolvedAt: Date()
        )
    }
    
    // MARK: - Cache Management
    
    private static func getCached(_ lnurl: String) -> ResolvedLNURL? {
        return cacheQueue.sync {
            guard let cached = cache[lnurl] else { return nil }
            
            let age = Date().timeIntervalSince(cached.resolvedAt)
            if age > cacheDuration {
                cache.removeValue(forKey: lnurl)
                return nil
            }
            
            logger.debug("Using cached resolution for \(lnurl) (age: \(Int(age))s)")
            return cached
        }
    }
    
    private static func cache(_ resolved: ResolvedLNURL, for lnurl: String) {
        cacheQueue.sync {
            cache[lnurl] = resolved
        }
    }
    
    /// Clear all cached resolutions
    static func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
        }
    }
    
    /// Clear cache for a specific LNURL
    static func clearCache(for lnurl: String) {
        cacheQueue.sync {
            _ = cache.removeValue(forKey: lnurl)
        }
    }
}
