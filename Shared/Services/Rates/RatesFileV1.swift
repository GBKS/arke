//
//  RatesFileV1.swift
//  Arké
//
//  The published exchange-rate file, format version 1, as served at
//  https://rates.arke.cash/v1/rates.json (Docs/Features/Fiat_Rates.md).
//
//  Decoding is tolerant where the contract says to be: unknown top-level
//  fields are ignored (a future `signature`, for instance), and a rate
//  entry that is not a JSON number is dropped rather than failing the
//  whole file. Everything else — version, base, timestamps, ordering
//  against the cache — is checked by RatesFileProcessor, not here.
//

import Foundation

nonisolated struct RatesFileV1: Equatable, Sendable {
    /// Format version; this client only ever accepts 1 (a breaking change gets a new URL)
    let version: Int

    /// When the server produced the file. Every staleness decision is based
    /// on this, never on download time.
    let updatedAt: Date

    /// Always "BTC" for a valid file
    let base: String

    /// Fiat units per 1 BTC, keyed by ISO 4217 code. Only entries that
    /// decoded as a finite number are present; the `> 0` check and the
    /// known-code filter happen in validation.
    let rates: [String: Decimal]

    /// Informational list of price sources the server aggregated
    let sources: [String]?

    nonisolated static let supportedVersion = 1
    nonisolated static let supportedBase = "BTC"

    init(version: Int, updatedAt: Date, base: String, rates: [String: Decimal], sources: [String]? = nil) {
        self.version = version
        self.updatedAt = updatedAt
        self.base = base
        self.rates = rates
        self.sources = sources
    }

    /// JSONDecoder reads numbers as Double. Going through the shortest
    /// round-trip string gives back the digits the server published
    /// (85841.88 stays 85841.88) instead of the binary approximation
    /// Decimal(Double) would preserve. Falls back to the direct conversion
    /// for the rare representation Decimal(string:) cannot parse.
    nonisolated static func decimal(from value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        if let exact = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) {
            return exact
        }
        return Decimal(value)
    }
}

// MARK: - Decodable

nonisolated extension RatesFileV1: Decodable {

    private enum CodingKeys: String, CodingKey {
        case version
        case updatedAt = "updated_at"
        case base
        case rates
        case sources
    }

    /// Dynamic key for iterating the `rates` object without knowing the codes up front
    private struct CurrencyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        base = try container.decode(String.self, forKey: .base)
        sources = try container.decodeIfPresent([String].self, forKey: .sources)

        // Unix seconds; accept a fractional number too so a server-side
        // formatting change does not reject every file
        if let seconds = try? container.decode(Int64.self, forKey: .updatedAt) {
            updatedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
        } else {
            let seconds = try container.decode(Double.self, forKey: .updatedAt)
            updatedAt = Date(timeIntervalSince1970: seconds)
        }

        let ratesContainer = try container.nestedContainer(keyedBy: CurrencyKey.self, forKey: .rates)
        var decoded: [String: Decimal] = [:]
        for key in ratesContainer.allKeys {
            // Drop individual non-numeric entries, keep the rest
            guard let value = try? ratesContainer.decode(Double.self, forKey: key),
                  let decimal = Self.decimal(from: value) else { continue }
            decoded[key.stringValue] = decimal
        }
        rates = decoded
    }
}
