//
//  RatesService.swift
//  Arké
//
//  Fetches the single public exchange-rate file, validates it, merges it
//  into a small on-disk cache and never throws to the UI
//  (Docs/Features/Fiat_Rates.md). Modelled on FeeRateService: keep
//  last-known-good on any failure, pure parsing in nonisolated helpers.
//
//  Privacy property: every client makes the identical request. No auth,
//  no query string, no cookies, no custom headers except If-None-Match,
//  and no per-currency requests — the file already holds every currency.
//

import Foundation
import Observation
import OSLog

/// Injected transport so tests can script responses and inspect requests
typealias RatesFetcher = @Sendable (URLRequest) async throws -> (Data, URLResponse)

@MainActor
@Observable
final class RatesService {

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "RatesService")

    // MARK: - Constants

    nonisolated static let ratesURL = URL(string: "https://rates.arke.cash/v1/rates.json")!
    nonisolated static let requestTimeout: TimeInterval = 15

    /// Foreground return and pull-to-refresh only re-check after this long
    nonisolated static let minimumCheckInterval: TimeInterval = 60

    /// Repeating refresh while the app is active
    nonisolated static let periodicInterval: TimeInterval = 5 * 60

    /// Diagnostic result of the last attempt, for X-Ray and logs
    nonisolated enum RefreshOutcome: Equatable, Sendable {
        case updated(currencies: Int)
        case notModified
        case rejected(String)
        case decodeFailed
        case httpStatus(Int)
        case networkError(String)
    }

    // MARK: - State

    /// The merged, persisted cache. Replaced wholesale on every accepted file.
    private(set) var cache: RatesCache

    private(set) var lastOutcome: RefreshOutcome?
    private(set) var lastOutcomeAt: Date?

    /// Any attempt, including failures — gates repeat checks so an outage
    /// can't be hammered by repeated pulls. Not persisted.
    private var lastAttempt: Date?

    private var periodicTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let taskManager: TaskDeduplicationManager
    private let fetch: RatesFetcher
    private let storeURL: URL
    private let now: @Sendable () -> Date

    // MARK: - Initialization

    /// - Parameters:
    ///   - taskManager: Shared deduplication manager
    ///   - fetch: Transport; defaults to a dedicated cookie-less, cache-less session
    ///   - storeURL: Cache file location; defaults to Application Support
    ///   - now: Clock, injectable for deterministic staleness tests
    init(
        taskManager: TaskDeduplicationManager,
        fetch: RatesFetcher? = nil,
        storeURL: URL = RatesService.defaultStoreURL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.taskManager = taskManager
        self.storeURL = storeURL
        self.now = now
        if let fetch {
            self.fetch = fetch
        } else {
            let session = URLSession(configuration: Self.makeSessionConfiguration())
            self.fetch = { request in try await session.data(for: request) }
        }
        self.cache = Self.loadCache(from: storeURL)
        if !cache.rates.isEmpty {
            Self.logger.info("Loaded rates cache: \(self.cache.rates.count) currencies, newest file \(self.cache.newestUpdatedAt?.timeIntervalSince1970 ?? 0, privacy: .public)")
        }
    }

    // MARK: - Access

    /// When the last check completed (200 or 304)
    var lastChecked: Date? {
        cache.lastChecked
    }

    /// Codes present in the cache, sorted
    var availableCurrencies: [String] {
        cache.availableCurrencies
    }

    /// The cached snapshot for a code, or nil when it has never been seen
    func rate(for currency: String) -> RateSnapshot? {
        cache.rates[currency]
    }

    /// Display trust for a code, based on its file timestamp
    func freshness(for currency: String) -> RateFreshness {
        RateFreshness(snapshot: rate(for: currency), now: now())
    }

    // MARK: - Refresh

    /// Fetch, validate, merge and persist. Deduplicated; never throws.
    func refresh() async {
        await taskManager.execute(key: "fiatRates") {
            await self.fetchAndStore()
        }
    }

    /// `refresh()` unless a check or attempt happened within `minimumInterval`
    func refreshIfDue(minimumInterval: TimeInterval = RatesService.minimumCheckInterval) async {
        let latest = [lastAttempt, cache.lastChecked].compactMap { $0 }.max()
        if let latest, now().timeIntervalSince(latest) < minimumInterval {
            return
        }
        await refresh()
    }

    /// Start the repeating refresh loop (no-op if already running)
    func startPeriodicRefresh(interval: TimeInterval = RatesService.periodicInterval) {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.refreshIfDue()
            }
        }
    }

    /// Stop the repeating loop — call when the scene goes to the background
    func stopPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    // MARK: - Fetching

    private func fetchAndStore() async {
        lastAttempt = now()
        let request = Self.makeRequest(etag: cache.etag)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            record(.networkError(error.localizedDescription))
            Self.logger.warning("Rates fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let http = response as? HTTPURLResponse else {
            record(.networkError("non-HTTP response"))
            return
        }

        let checkedAt = now()

        switch http.statusCode {
        case 304:
            // Unchanged on the server: only "last checked" moves
            cache.lastChecked = checkedAt
            persist()
            record(.notModified)
            Self.logger.info("Rates not modified (etag \(self.cache.etag ?? "-", privacy: .public))")

        case 200:
            let file: RatesFileV1
            do {
                file = try JSONDecoder().decode(RatesFileV1.self, from: data)
            } catch {
                record(.decodeFailed)
                Self.logger.warning("Rates file did not decode: \(error.localizedDescription, privacy: .public)")
                return
            }

            do {
                let snapshots = try RatesFileProcessor.validate(file, against: cache, now: checkedAt)
                let etag = http.value(forHTTPHeaderField: "ETag")
                cache = RatesFileProcessor.merge(snapshots, etag: etag, checkedAt: checkedAt, into: cache)
                persist()
                record(.updated(currencies: snapshots.count))
                Self.logger.info("Rates updated: \(snapshots.count) currencies, file \(file.updatedAt.timeIntervalSince1970, privacy: .public), etag \(etag ?? "-", privacy: .public)")
            } catch let rejection as RatesFileRejection {
                record(.rejected(rejection.description))
                Self.logger.warning("Rates file rejected: \(rejection.description, privacy: .public)")
            } catch {
                record(.rejected(error.localizedDescription))
                Self.logger.warning("Rates file rejected: \(error.localizedDescription, privacy: .public)")
            }

        default:
            record(.httpStatus(http.statusCode))
            Self.logger.warning("Rates request returned HTTP \(http.statusCode)")
        }
    }

    private func record(_ outcome: RefreshOutcome) {
        lastOutcome = outcome
        lastOutcomeAt = now()
    }

    // MARK: - Request construction

    /// The one request every client makes. Only If-None-Match is ever added.
    nonisolated static func makeRequest(etag: String?) -> URLRequest {
        var request = URLRequest(
            url: ratesURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    /// Ephemeral, no cookies, no URL cache: revalidation is done by hand
    /// with the stored ETag so the cache write is tied to validation.
    nonisolated static func makeSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = requestTimeout
        config.httpAdditionalHeaders = nil
        return config
    }

    // MARK: - Persistence

    /// Application Support/Rates/rates-cache.json — not secret, not wallet data
    nonisolated static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rates", isDirectory: true)
            .appendingPathComponent("rates-cache.json")
    }

    private func persist() {
        do {
            try Self.writeCache(cache, to: storeURL)
        } catch {
            Self.logger.error("Rates cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Missing or undecodable file (torn write, future schema) → empty cache, never fatal
    nonisolated static func loadCache(from url: URL) -> RatesCache {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        do {
            return try makeDecoder().decode(RatesCache.self, from: data)
        } catch {
            logger.warning("Rates cache unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    nonisolated static func writeCache(_ cache: RatesCache, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try makeEncoder().encode(cache)
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
