//
//  RatesCache.swift
//  Arké
//
//  The persisted exchange-rate cache, per-currency freshness, and the
//  pure validate/merge step between a downloaded file and that cache
//  (Docs/Features/Fiat_Rates.md). Everything here is nonisolated and
//  free of I/O so the spec's test cases run as plain unit tests.
//

import Foundation

/// One currency's rate together with the server time of the file that carried it
nonisolated struct RateSnapshot: Codable, Equatable, Sendable {
    /// Fiat units per 1 BTC
    let value: Decimal

    /// `updated_at` of the file this value came from — NOT download time
    let updatedAt: Date
}

/// How much to trust a snapshot for display, by the age of its file timestamp
nonisolated enum RateFreshness: Equatable, Sendable {
    /// Younger than 15 minutes: show the fiat value normally
    case fresh
    /// 15 minutes to 24 hours: still show fiat, with a subtle "as of" indicator
    case stale
    /// 24 hours or older, or no snapshot at all: hide fiat, sats only
    case unavailable

    nonisolated static let staleAfter: TimeInterval = 15 * 60
    nonisolated static let unavailableAfter: TimeInterval = 24 * 60 * 60

    init(snapshot: RateSnapshot?, now: Date) {
        guard let snapshot else {
            self = .unavailable
            return
        }
        let age = now.timeIntervalSince(snapshot.updatedAt)
        if age < Self.staleAfter {
            self = .fresh
        } else if age < Self.unavailableAfter {
            self = .stale
        } else {
            self = .unavailable
        }
    }
}

/// What RatesService keeps on disk. Small: the ETag, when we last completed
/// a check, and one snapshot per currency.
nonisolated struct RatesCache: Codable, Equatable, Sendable {
    /// ETag of the last file that passed validation; sent back as If-None-Match
    var etag: String?

    /// When the last check completed with a 200 or 304 — failed attempts
    /// are tracked in memory only
    var lastChecked: Date?

    /// Merged per currency: a new file overwrites the codes it contains,
    /// codes it lacks keep their previous value and timestamp
    var rates: [String: RateSnapshot]

    nonisolated static let empty = RatesCache(etag: nil, lastChecked: nil, rates: [:])

    /// Newest file timestamp present — the floor a new file must meet
    var newestUpdatedAt: Date? {
        rates.values.map(\.updatedAt).max()
    }

    /// Codes present in the cache, sorted, for the currency picker
    var availableCurrencies: [String] {
        rates.keys.sorted()
    }
}

/// Why a downloaded file was rejected as a whole (the cache is kept)
nonisolated enum RatesFileRejection: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case unsupportedBase(String)
    case updatedAtInFuture(Date)
    case olderThanCache(file: Date, cache: Date)

    var description: String {
        switch self {
        case .unsupportedVersion(let version):
            return "unsupported version \(version)"
        case .unsupportedBase(let base):
            return "unsupported base \(base)"
        case .updatedAtInFuture(let date):
            return "updated_at in the future (\(date.timeIntervalSince1970))"
        case .olderThanCache(let file, let cache):
            return "older than cache (\(file.timeIntervalSince1970) < \(cache.timeIntervalSince1970))"
        }
    }
}

/// Pure validate + merge between a decoded file and the cache
nonisolated enum RatesFileProcessor {

    /// Clock-skew allowance for `updated_at` ahead of the device clock
    nonisolated static let maxClockSkew: TimeInterval = 10 * 60

    /// ISO 4217 codes the system knows; anything else in the file is ignored
    nonisolated static let knownCurrencyCodes: Set<String> = Set(
        Locale.Currency.isoCurrencies.map(\.identifier)
    )

    /// Checks the file against the contract and the cache. Throws a
    /// `RatesFileRejection` when the whole file must be discarded; otherwise
    /// returns the usable per-currency snapshots (bad individual entries —
    /// non-positive values, unknown codes — are dropped, the rest kept).
    nonisolated static func validate(
        _ file: RatesFileV1,
        against cache: RatesCache,
        now: Date
    ) throws -> [String: RateSnapshot] {
        guard file.version == RatesFileV1.supportedVersion else {
            throw RatesFileRejection.unsupportedVersion(file.version)
        }
        guard file.base == RatesFileV1.supportedBase else {
            throw RatesFileRejection.unsupportedBase(file.base)
        }
        guard file.updatedAt.timeIntervalSince(now) <= maxClockSkew else {
            throw RatesFileRejection.updatedAtInFuture(file.updatedAt)
        }
        // Never go backwards; equal is fine (the same file seen again)
        if let newest = cache.newestUpdatedAt, file.updatedAt < newest {
            throw RatesFileRejection.olderThanCache(file: file.updatedAt, cache: newest)
        }

        var snapshots: [String: RateSnapshot] = [:]
        for (code, value) in file.rates {
            guard value.isFinite, value > 0, knownCurrencyCodes.contains(code) else { continue }
            snapshots[code] = RateSnapshot(value: value, updatedAt: file.updatedAt)
        }
        return snapshots
    }

    /// Per-currency merge: `snapshots` overwrite their codes, everything else
    /// in `cache` survives untouched. The ETag is replaced only here, i.e.
    /// only together with a file that passed validation.
    nonisolated static func merge(
        _ snapshots: [String: RateSnapshot],
        etag: String?,
        checkedAt: Date,
        into cache: RatesCache
    ) -> RatesCache {
        var merged = cache
        merged.rates.merge(snapshots) { _, new in new }
        merged.etag = etag
        merged.lastChecked = checkedAt
        return merged
    }
}
