//
//  BIP353Resolver.swift
//  Arké
//
//  BIP-353: DNS Payment Instructions.
//  Resolves ₿user@domain / user@domain to the bitcoin: URI published in the
//  TXT record at user.user._bitcoin-payment.domain.
//
//  Validation model (DECIDED 2026-10-29, Docs/Features/BIP353_DNSSEC.md §4):
//  the OS validator never completes on iOS 27 / macOS 27, so two independent
//  validating resolvers are asked over HTTPS and the answer is accepted only
//  when both report the chain as authenticated (AD) and return the same
//  records. This is a documented deviation from the BIP's "MUST NOT trust a
//  remote resolver"; `DNSTXTSource` is the seam where in-app validation can
//  replace it without touching callers.
//

import Foundation
import OSLog

// MARK: - Validated TXT answers

/// What a validating resolver said about one TXT name.
nonisolated struct DNSTXTAnswer: Equatable, Sendable {
    /// DNS response code: 0 NOERROR, 3 NXDOMAIN, 2 SERVFAIL.
    let rcode: Int
    /// The resolver's Authenticated Data bit: it validated the DNSSEC chain.
    let authenticated: Bool
    /// Each TXT record with its character-strings concatenated in RDATA order.
    let records: [String]
    /// Smallest TTL among the TXT records, nil when there are none.
    let minimumTTL: TimeInterval?

    static let serverFailure = 2
    static let nxdomain = 3
}

/// A resolver that can answer a TXT query with a DNSSEC verdict.
nonisolated protocol DNSTXTSource: Sendable {
    var name: String { get }
    func queryTXT(_ dnsName: String) async throws -> DNSTXTAnswer
}

// MARK: - TXT RDATA presentation parsing

/// Turns the presentation form of TXT RDATA into the concatenated string the
/// BIP wants: character-strings "in RDATA order, without inserting separators".
nonisolated enum TXTRecordData {
    /// Cloudflare returns `"part one" "part two"` with RFC 1035 escapes;
    /// Google returns the already-concatenated text without quotes.
    static func concatenated(_ presentation: String) -> String {
        guard presentation.first == "\"" else { return presentation }

        // Work on bytes: a \DDD escape is one byte of the record, and multi-byte
        // UTF-8 (Cloudflare writes "é" as \195\169) must reassemble before decoding.
        var bytes: [UInt8] = []
        var inQuotes = false
        let input = Array(presentation.utf8)
        var index = 0
        while index < input.count {
            let byte = input[index]
            if !inQuotes {
                if byte == UInt8(ascii: "\"") { inQuotes = true }
                index += 1
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inQuotes = false
                index += 1
            case UInt8(ascii: "\\"):
                // \DDD is a decimal byte, \X is the literal X.
                if let value = decimalEscape(input, at: index + 1) {
                    bytes.append(value)
                    index += 4
                } else if index + 1 < input.count {
                    bytes.append(input[index + 1])
                    index += 2
                } else {
                    index += 1
                }
            default:
                bytes.append(byte)
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decimalEscape(_ bytes: [UInt8], at start: Int) -> UInt8? {
        guard start + 2 < bytes.count else { return nil }
        var value = 0
        for digit in bytes[start...start + 2] {
            guard digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(digit - UInt8(ascii: "0"))
        }
        guard value <= 255 else { return nil }
        return UInt8(value)
    }
}

// MARK: - DNS-over-HTTPS JSON source

/// A public resolver speaking the DNS-over-HTTPS JSON API.
nonisolated struct DoHJSONSource: DNSTXTSource {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum DoHError: Swift.Error, Equatable {
        case badEndpoint
        case httpStatus(Int)
        case malformedResponse
    }

    let name: String
    let endpoint: String
    let acceptHeader: String?
    let fetch: Fetch

    init(name: String, endpoint: String, acceptHeader: String?, fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.name = name
        self.endpoint = endpoint
        self.acceptHeader = acceptHeader
        self.fetch = fetch
    }

    static let cloudflare = DoHJSONSource(
        name: "Cloudflare",
        endpoint: "https://cloudflare-dns.com/dns-query",
        acceptHeader: "application/dns-json"
    )

    static let google = DoHJSONSource(
        name: "Google",
        endpoint: "https://dns.google/resolve",
        acceptHeader: nil
    )

    func queryTXT(_ dnsName: String) async throws -> DNSTXTAnswer {
        guard var components = URLComponents(string: endpoint) else { throw DoHError.badEndpoint }
        components.queryItems = [
            URLQueryItem(name: "name", value: dnsName),
            URLQueryItem(name: "type", value: "TXT"),
        ]
        guard let url = components.url else { throw DoHError.badEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        if let acceptHeader {
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DoHError.httpStatus(http.statusCode)
        }
        return try Self.parse(data)
    }

    /// The JSON shape both Cloudflare and Google return (verified 2026-10-29).
    private struct Response: Decodable {
        struct Answer: Decodable {
            let type: Int
            let TTL: Int
            let data: String
        }
        let Status: Int
        let AD: Bool
        let Answer: [Answer]?
    }

    /// Parses a dns-json body into an answer; TXT records only, strings concatenated.
    static func parse(_ data: Data) throws -> DNSTXTAnswer {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DoHError.malformedResponse
        }
        let txt = (decoded.Answer ?? []).filter { $0.type == 16 }
        return DNSTXTAnswer(
            rcode: decoded.Status,
            authenticated: decoded.AD,
            records: txt.map { TXTRecordData.concatenated($0.data) },
            minimumTTL: txt.map { TimeInterval($0.TTL) }.min()
        )
    }
}

// MARK: - Validation policy

/// The decisions that turn resolver answers into an accepted bitcoin: URI.
nonisolated enum BIP353Validation {
    /// Accepts the payment records only when at least two resolvers answered,
    /// every one reports an authenticated chain, and they agree on the
    /// `bitcoin:` records. Sibling records (SPF, decoys) are not compared:
    /// the two providers present escapes differently and they carry no payment.
    static func combine(_ answers: [DNSTXTAnswer]) throws -> [String] {
        guard answers.count >= 2 else {
            throw BIP353Resolver.BIP353Error.dnsLookupFailed("fewer than two resolver answers")
        }
        // SERVFAIL carries AD=false by definition, whether the cause is an
        // outage or a bogus signature; it must not read as "unsigned".
        if answers.contains(where: { $0.rcode == DNSTXTAnswer.serverFailure }) {
            throw BIP353Resolver.BIP353Error.resolverFailure
        }
        if answers.allSatisfy({ $0.rcode == DNSTXTAnswer.nxdomain }) {
            // A validating resolver authenticates its denial too.
            guard answers.allSatisfy(\.authenticated) else {
                throw BIP353Resolver.BIP353Error.dnssecValidationFailed
            }
            throw BIP353Resolver.BIP353Error.noDNSRecord
        }
        guard answers.allSatisfy({ $0.rcode == 0 }) else {
            throw BIP353Resolver.BIP353Error.resolversDisagree
        }
        guard answers.allSatisfy(\.authenticated) else {
            throw BIP353Resolver.BIP353Error.dnssecValidationFailed
        }
        if answers.allSatisfy({ $0.records.isEmpty }) {
            throw BIP353Resolver.BIP353Error.noDNSRecord
        }
        let candidateSets = answers.map { bitcoinCandidates(in: $0.records).sorted() }
        guard let first = candidateSets.first, candidateSets.allSatisfy({ $0 == first }) else {
            throw BIP353Resolver.BIP353Error.resolversDisagree
        }
        return first
    }

    /// The records that begin with `bitcoin:`, ignoring case.
    static func bitcoinCandidates(in records: [String]) -> [String] {
        records.filter { $0.lowercased().hasPrefix("bitcoin:") }
    }

    /// Exactly one record may begin with `bitcoin:` (ignoring case); others are ignored.
    static func selectBitcoinURI(from records: [String]) throws -> String {
        let matches = bitcoinCandidates(in: records)
        switch matches.count {
        case 0: throw BIP353Resolver.BIP353Error.noBitcoinRecord
        case 1: return matches[0]
        default: throw BIP353Resolver.BIP353Error.multipleBitcoinRecords
        }
    }
}

// MARK: - Resolver

/// Resolves BIP-353 human-readable Bitcoin addresses via validating DNS resolvers.
class BIP353Resolver {

    // MARK: Types

    enum BIP353Format {
        case bitcoinSymbol(String)  // ₿alice@example.com
        case userAtDomain(String)   // alice@example.com (ambiguous with Lightning Address)
    }

    struct ResolvedBIP353 {
        let originalAddress: String      // ₿alice@example.com or alice@example.com
        let bip21URI: String             // The bitcoin: URI from the DNS TXT record
        let resolvedFrom: String         // DNS name that was queried
        let resolvedAt: Date
        let expiresAt: Date              // Never later than the record TTL allows

        func isFresh(at date: Date = Date()) -> Bool {
            date < expiresAt
        }
    }

    enum BIP353Error: LocalizedError, Equatable {
        case invalidFormat
        case noDNSRecord
        case noBitcoinRecord
        case multipleBitcoinRecords
        case dnssecValidationFailed
        case resolversDisagree
        case resolverFailure
        case dnsLookupFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return String(localized: "bip353_error_invalid_format", defaultValue: "This isn't a valid ₿user@domain address.")
            case .noDNSRecord:
                return String(localized: "bip353_error_no_record", defaultValue: "No payment instructions are published for this address.")
            case .noBitcoinRecord:
                return String(localized: "bip353_error_no_bitcoin_record", defaultValue: "This address publishes DNS records, but none with Bitcoin payment instructions.")
            case .multipleBitcoinRecords:
                return String(localized: "bip353_error_multiple_records", defaultValue: "This address publishes more than one payment record, which the standard doesn't allow.")
            case .dnssecValidationFailed:
                return String(localized: "bip353_error_not_signed", defaultValue: "This address's DNS records aren't DNSSEC-signed, so they can't be trusted.")
            case .resolversDisagree:
                return String(localized: "bip353_error_resolvers_disagree", defaultValue: "Two DNS resolvers returned different records for this address, so it can't be trusted.")
            case .resolverFailure:
                return String(localized: "bip353_error_resolver_failure", defaultValue: "A DNS resolver couldn't verify this address's records. That can be a temporary outage or a broken DNSSEC signature on the recipient's side.")
            case .dnsLookupFailed:
                return String(localized: "bip353_error_lookup_failed", defaultValue: "Couldn't look up this address's DNS records right now.")
            }
        }
    }

    // MARK: Configuration

    /// Both must agree; see `BIP353Validation.combine`.
    static let defaultSources: [any DNSTXTSource] = [DoHJSONSource.cloudflare, DoHJSONSource.google]

    private static let maximumCacheDuration: TimeInterval = 600
    private static var cache: [String: ResolvedBIP353] = [:]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GBKS.Arke", category: "BIP353Resolver")

    // MARK: Public API

    /// Resolves a BIP-353 address to its BIP-21 URI through the default resolvers.
    static func resolve(_ address: String) async throws -> ResolvedBIP353 {
        try await resolve(address, using: defaultSources)
    }

    /// Resolves through the given sources; every source is queried and all must agree.
    static func resolve(_ address: String, using sources: [any DNSTXTSource], now: Date = Date()) async throws -> ResolvedBIP353 {
        if let cached = cache[address], cached.isFresh(at: now) {
            logger.debug("Using cached resolution for \(address, privacy: .private)")
            return cached
        }
        cache.removeValue(forKey: address)

        let format = try detectFormat(address)
        let dnsName = constructDNSName(address, format: format)
        logger.info("Resolving \(address, privacy: .private) via \(sources.count) resolver(s)")

        let answers: [DNSTXTAnswer]
        do {
            answers = try await withThrowingTaskGroup(of: DNSTXTAnswer.self) { group in
                for source in sources {
                    group.addTask { try await source.queryTXT(dnsName) }
                }
                var collected: [DNSTXTAnswer] = []
                for try await answer in group { collected.append(answer) }
                return collected
            }
        } catch let error as BIP353Error {
            throw error
        } catch is CancellationError {
            // The caller moved on (a Lightning-address race was won); not a failure.
            throw CancellationError()
        } catch {
            logger.error("Resolver query failed: \(error.localizedDescription, privacy: .public)")
            throw BIP353Error.dnsLookupFailed(error.localizedDescription)
        }

        let records = try BIP353Validation.combine(answers)
        let bip21URI = try BIP353Validation.selectBitcoinURI(from: records)

        let ttl = answers.compactMap(\.minimumTTL).min() ?? 0
        let resolved = ResolvedBIP353(
            originalAddress: address,
            bip21URI: bip21URI,
            resolvedFrom: dnsName,
            resolvedAt: now,
            expiresAt: now.addingTimeInterval(min(maximumCacheDuration, ttl))
        )
        cache[address] = resolved
        logger.info("Resolved \(address, privacy: .private); both resolvers authenticated, \(records.count) TXT record(s)")
        return resolved
    }

    /// Check if an address looks like a BIP-353 address
    static func isBIP353Format(_ address: String) -> Bool {
        return detectFormatOrNil(address) != nil
    }

    // MARK: Format Detection

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

    // MARK: DNS Name Construction

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

    // MARK: Cache Management

    /// Clear all cached resolutions (for testing or manual refresh)
    static func clearCache() {
        cache.removeAll()
    }

    /// Clear cache for a specific address
    static func clearCache(for address: String) {
        cache.removeValue(forKey: address)
    }
}
