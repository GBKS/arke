//
//  RatesServiceTests.swift
//  ArkéTests
//
//  The spec's test cases for the fiat-rates client
//  (Docs/Features/Fiat_Rates.md): file validation, per-currency merge,
//  ETag handling, staleness, conversion and request hygiene. The
//  transport is a scripted stub, the clock is injected, and the cache
//  lives in a scratch directory per test.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// MARK: - Test doubles

/// Scripted transport: returns queued results in order and records every request
private final class FetchStub: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<(Data, URLResponse), Error>] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock(); defer { lock.unlock() }
        queue.append(result)
    }

    var fetcher: RatesFetcher {
        { request in
            self.lock.lock()
            self.requests.append(request)
            let next = self.queue.isEmpty ? nil : self.queue.removeFirst()
            self.lock.unlock()
            guard let next else { throw URLError(.notConnectedToInternet) }
            return try next.get()
        }
    }
}

/// Settable clock so staleness and the 60s gate are deterministic
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

// MARK: - Fixtures

private enum Fixture {
    /// 2026-09-28 13:00:00 UTC, the "server produced the file" instant
    static let fileTime = Date(timeIntervalSince1970: 1_790_600_400)

    /// Device clock a minute after the file was produced
    static let now = fileTime.addingTimeInterval(60)

    static let usd = Decimal(string: "85841.88")!
    static let eur = Decimal(string: "74863.91")!
    static let jpy = Decimal(string: "13480254.5")!

    static func fileJSON(
        version: Int = 1,
        updatedAt: Date = fileTime,
        base: String = "BTC",
        rates: [String: Any] = ["USD": 85841.88, "EUR": 74863.91, "JPY": 13480254.5],
        extra: [String: Any] = [:]
    ) -> Data {
        var object: [String: Any] = [
            "version": version,
            "updated_at": Int64(updatedAt.timeIntervalSince1970),
            "base": base,
            "rates": rates,
            "sources": ["mempool", "kraken"]
        ]
        for (key, value) in extra { object[key] = value }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func ok(_ body: Data, etag: String? = "\"etag-1\"") -> Result<(Data, URLResponse), Error> {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: RatesService.ratesURL, statusCode: 200, httpVersion: "HTTP/2", headerFields: headers)!
        return .success((body, response))
    }

    static func notModified() -> Result<(Data, URLResponse), Error> {
        let response = HTTPURLResponse(url: RatesService.ratesURL, statusCode: 304, httpVersion: "HTTP/2", headerFields: nil)!
        return .success((Data(), response))
    }

    static func scratchStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("rates-cache.json")
    }
}

// MARK: - Service tests

@Suite("Fiat Rates Service")
@MainActor
struct RatesServiceTests {

    private func makeService(
        stub: FetchStub,
        clock: TestClock,
        storeURL: URL = Fixture.scratchStoreURL()
    ) -> RatesService {
        RatesService(
            taskManager: TaskDeduplicationManager(),
            fetch: stub.fetcher,
            storeURL: storeURL,
            now: { clock.now }
        )
    }

    @Test("Fresh valid file → values shown, cache written, ETag stored")
    func freshFileIsStored() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        let storeURL = Fixture.scratchStoreURL()
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let service = makeService(stub: stub, clock: clock, storeURL: storeURL)

        await service.refresh()

        #expect(service.rate(for: "USD")?.value == Fixture.usd)
        #expect(service.rate(for: "USD")?.updatedAt == Fixture.fileTime)
        #expect(service.availableCurrencies == ["EUR", "JPY", "USD"])
        #expect(service.cache.etag == "\"etag-1\"")
        #expect(service.lastChecked == Fixture.now)
        #expect(service.lastOutcome == .updated(currencies: 3))
        #expect(FileManager.default.fileExists(atPath: storeURL.path))

        // A second instance over the same file starts from the persisted cache
        let reloaded = makeService(stub: FetchStub(), clock: clock, storeURL: storeURL)
        #expect(reloaded.cache == service.cache)
    }

    @Test("304 → cache unchanged, lastChecked updated, If-None-Match sent")
    func notModifiedKeepsCache() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        stub.enqueue(Fixture.notModified())
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        let before = service.cache
        clock.advance(by: 120)
        await service.refresh()

        #expect(service.cache.rates == before.rates)
        #expect(service.cache.etag == before.etag)
        #expect(service.lastChecked == Fixture.now.addingTimeInterval(120))
        #expect(service.lastOutcome == .notModified)
        #expect(stub.requests.count == 2)
        #expect(stub.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(stub.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"etag-1\"")
    }

    @Test("version 2, base ETH or malformed JSON → rejected, previous values kept")
    func invalidFilesAreRejected() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let later = Fixture.fileTime.addingTimeInterval(300)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(version: 2, updatedAt: later, rates: ["USD": 1.0]), etag: "\"v2\""))
        stub.enqueue(Fixture.ok(Fixture.fileJSON(updatedAt: later, base: "ETH", rates: ["USD": 1.0]), etag: "\"eth\""))
        stub.enqueue(Fixture.ok(Data("{not json".utf8), etag: "\"garbage\""))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        let good = service.cache
        clock.advance(by: 400)

        await service.refresh()
        #expect(service.lastOutcome == .rejected(RatesFileRejection.unsupportedVersion(2).description))
        await service.refresh()
        #expect(service.lastOutcome == .rejected(RatesFileRejection.unsupportedBase("ETH").description))
        await service.refresh()
        #expect(service.lastOutcome == .decodeFailed)

        #expect(service.cache.rates == good.rates)
        #expect(service.cache.etag == "\"etag-1\"", "ETag only moves with a file that passed validation")
        #expect(service.rate(for: "USD")?.value == Fixture.usd)
    }

    @Test("File older than the cache → ignored")
    func olderFileIsIgnored() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let earlier = Fixture.fileTime.addingTimeInterval(-600)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(updatedAt: earlier, rates: ["USD": 1.0]), etag: "\"old\""))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        await service.refresh()

        #expect(service.lastOutcome == .rejected(RatesFileRejection.olderThanCache(file: earlier, cache: Fixture.fileTime).description))
        #expect(service.rate(for: "USD")?.value == Fixture.usd)
        #expect(service.cache.etag == "\"etag-1\"")
    }

    @Test("Same updated_at as the cache is accepted (never go backwards, equal is fine)")
    func equalTimestampIsAccepted() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        stub.enqueue(Fixture.ok(Fixture.fileJSON(rates: ["USD": 90000.0]), etag: "\"same-time\""))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        await service.refresh()

        #expect(service.rate(for: "USD")?.value == Decimal(90000))
        #expect(service.cache.etag == "\"same-time\"")
    }

    @Test("File missing EUR while the cache has EUR → EUR keeps old value and timestamp, others update")
    func missingCurrencyKeepsPrevious() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let later = Fixture.fileTime.addingTimeInterval(300)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(updatedAt: later, rates: ["USD": 86000.0, "JPY": 13500000.0]), etag: "\"etag-2\""))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        clock.advance(by: 300)
        await service.refresh()

        #expect(service.rate(for: "EUR")?.value == Fixture.eur)
        #expect(service.rate(for: "EUR")?.updatedAt == Fixture.fileTime)
        #expect(service.rate(for: "USD")?.value == Decimal(86000))
        #expect(service.rate(for: "USD")?.updatedAt == later)
        #expect(service.rate(for: "JPY")?.updatedAt == later)
        #expect(service.cache.etag == "\"etag-2\"")
        #expect(service.lastOutcome == .updated(currencies: 2))
    }

    @Test("Unknown top-level field and unknown currency XYZ → accepted, ignored")
    func unknownFieldsAreIgnored() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(
            rates: ["USD": 85841.88, "XYZ": 42.0],
            extra: ["signature": "deadbeef", "future_field": ["nested": true]]
        )))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()

        #expect(service.lastOutcome == .updated(currencies: 1))
        #expect(service.rate(for: "USD")?.value == Fixture.usd)
        #expect(service.rate(for: "XYZ") == nil)
    }

    @Test("Individual bad entries are dropped, the rest kept")
    func badEntriesAreDropped() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(
            rates: ["USD": 85841.88, "EUR": 0, "GBP": -5.0, "JPY": "not a number", "CHF": NSNull()]
        )))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()

        #expect(service.lastOutcome == .updated(currencies: 1))
        #expect(service.availableCurrencies == ["USD"])
    }

    @Test("updated_at more than 10 minutes in the future → rejected; within skew → accepted")
    func futureTimestamps() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON(updatedAt: Fixture.now.addingTimeInterval(11 * 60))))
        stub.enqueue(Fixture.ok(Fixture.fileJSON(updatedAt: Fixture.now.addingTimeInterval(9 * 60))))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        #expect(service.cache.rates.isEmpty)
        if case .rejected = service.lastOutcome {} else {
            Issue.record("expected rejection, got \(String(describing: service.lastOutcome))")
        }

        await service.refresh()
        #expect(service.lastOutcome == .updated(currencies: 3))
    }

    @Test("Offline at launch with a 3h-old cache → stale values shown, no error")
    func offlineWithOldCache() async throws {
        let storeURL = Fixture.scratchStoreURL()
        let oldFileTime = Fixture.now.addingTimeInterval(-3 * 60 * 60)
        let seeded = RatesCache(
            etag: "\"seeded\"",
            lastChecked: oldFileTime.addingTimeInterval(30),
            rates: ["USD": RateSnapshot(value: Fixture.usd, updatedAt: oldFileTime)]
        )
        try RatesService.writeCache(seeded, to: storeURL)

        let stub = FetchStub()  // nothing queued → every fetch throws "not connected"
        let clock = TestClock(Fixture.now)
        let service = makeService(stub: stub, clock: clock, storeURL: storeURL)

        #expect(service.rate(for: "USD")?.value == Fixture.usd)
        await service.refresh()

        #expect(service.rate(for: "USD")?.value == Fixture.usd)
        #expect(service.freshness(for: "USD") == .stale)
        #expect(service.cache.etag == "\"seeded\"")
        #expect(service.lastChecked == seeded.lastChecked, "a failed attempt is not a completed check")
        if case .networkError = service.lastOutcome {} else {
            Issue.record("expected networkError, got \(String(describing: service.lastOutcome))")
        }
    }

    @Test("refreshIfDue makes one request per 60s, including after a failure")
    func refreshIfDueIsRateLimited() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        stub.enqueue(Fixture.notModified())
        let service = makeService(stub: stub, clock: clock)

        await service.refreshIfDue()
        await service.refreshIfDue()
        #expect(stub.requests.count == 1)

        clock.advance(by: 61)
        await service.refreshIfDue()
        #expect(stub.requests.count == 2)

        // Queue exhausted → network error; still gated afterwards
        clock.advance(by: 61)
        await service.refreshIfDue()
        #expect(stub.requests.count == 3)
        await service.refreshIfDue()
        #expect(stub.requests.count == 3)
    }

    @Test("Non-2xx status keeps the cache")
    func serverErrorKeepsCache() async throws {
        let stub = FetchStub()
        let clock = TestClock(Fixture.now)
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let response = HTTPURLResponse(url: RatesService.ratesURL, statusCode: 503, httpVersion: "HTTP/2", headerFields: nil)!
        stub.enqueue(.success((Data(), response)))
        let service = makeService(stub: stub, clock: clock)

        await service.refresh()
        await service.refresh()

        #expect(service.lastOutcome == .httpStatus(503))
        #expect(service.rate(for: "USD")?.value == Fixture.usd)
    }

    // MARK: Request hygiene

    @Test("No query string, no cookies, no header except If-None-Match")
    func requestHygiene() async throws {
        let bare = RatesService.makeRequest(etag: nil)
        #expect(bare.url == RatesService.ratesURL)
        #expect(bare.url?.query == nil)
        #expect(bare.httpMethod == "GET")
        #expect(bare.httpShouldHandleCookies == false)
        #expect(bare.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(bare.timeoutInterval == 15)
        #expect((bare.allHTTPHeaderFields ?? [:]).isEmpty)

        let revalidating = RatesService.makeRequest(etag: "\"abc\"")
        #expect(revalidating.allHTTPHeaderFields == ["If-None-Match": "\"abc\""])

        // The request actually sent by the service is the same one
        let stub = FetchStub()
        stub.enqueue(Fixture.ok(Fixture.fileJSON()))
        let service = makeService(stub: stub, clock: TestClock(Fixture.now))
        await service.refresh()
        let sent = try #require(stub.requests.first)
        #expect(sent.url == RatesService.ratesURL)
        #expect((sent.allHTTPHeaderFields ?? [:]).isEmpty)
        #expect(sent.httpShouldHandleCookies == false)
    }

    @Test("Session configuration has no cookie storage, no URL cache, no extra headers")
    func sessionConfigurationHygiene() {
        let config = RatesService.makeSessionConfiguration()
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(config.timeoutIntervalForRequest == 15)
        #expect((config.httpAdditionalHeaders ?? [:]).isEmpty)
    }
}

// MARK: - Pure logic tests

@Suite("Fiat Rates Logic")
struct FiatRatesLogicTests {

    @Test("Age 10 min / 2 h / 25 h → fresh / stale / unavailable")
    func freshnessBands() {
        let now = Fixture.now
        func snapshot(ageMinutes: Double) -> RateSnapshot {
            RateSnapshot(value: 1, updatedAt: now.addingTimeInterval(-ageMinutes * 60))
        }
        #expect(RateFreshness(snapshot: snapshot(ageMinutes: 10), now: now) == .fresh)
        #expect(RateFreshness(snapshot: snapshot(ageMinutes: 120), now: now) == .stale)
        #expect(RateFreshness(snapshot: snapshot(ageMinutes: 25 * 60), now: now) == .unavailable)
        #expect(RateFreshness(snapshot: nil, now: now) == .unavailable)
        // Boundaries: 15 min is stale, 24 h is unavailable
        #expect(RateFreshness(snapshot: snapshot(ageMinutes: 15), now: now) == .stale)
        #expect(RateFreshness(snapshot: snapshot(ageMinutes: 24 * 60), now: now) == .unavailable)
    }

    @Test("100_000 sats at USD 85841.88 → $85.84; at JPY 13480254.5 → ¥13,480")
    func conversionToFiat() {
        let enUS = Locale(identifier: "en_US")
        #expect(FiatConversion.fiatAmount(sats: 100_000, rate: Fixture.usd) == Decimal(string: "85.84188"))
        #expect(FiatConversion.formattedFiat(sats: 100_000, rate: Fixture.usd, currency: "USD", locale: enUS) == "$85.84")
        #expect(FiatConversion.formattedFiat(sats: 100_000, rate: Fixture.jpy, currency: "JPY", locale: enUS) == "¥13,480")
    }

    @Test("Typing $10 at 85841.88 gives 11_649 sats, and a new rate does not move it")
    func conversionFromFiat() {
        let sats = FiatConversion.sats(fiatAmount: 10, rate: Fixture.usd)
        #expect(sats == 11_649)

        // The sats value is the source of truth from here on; a refreshed
        // rate would give a different number, which is exactly why callers
        // must not recompute it
        let afterRefresh = FiatConversion.sats(fiatAmount: 10, rate: Decimal(90000))
        #expect(afterRefresh != sats)
        #expect(sats == 11_649)

        #expect(FiatConversion.sats(fiatAmount: 10, rate: 0) == nil)
        #expect(FiatConversion.sats(fiatAmount: -1, rate: Fixture.usd) == nil)
    }

    @Test("Rates decode through the published digits, not the binary Double")
    func decimalDecoding() throws {
        let file = try JSONDecoder().decode(RatesFileV1.self, from: Fixture.fileJSON())
        #expect(file.rates["USD"] == Fixture.usd)
        #expect(file.rates["JPY"] == Fixture.jpy)
        #expect(file.updatedAt == Fixture.fileTime)
        #expect(file.sources == ["mempool", "kraken"])
        #expect(RatesFileV1.decimal(from: 1497376656.58) == Decimal(string: "1497376656.58"))
    }

    @Test("Cache round-trips through the on-disk JSON exactly")
    func cacheRoundTrip() throws {
        let url = Fixture.scratchStoreURL()
        let cache = RatesCache(
            etag: "\"x\"",
            lastChecked: Fixture.now,
            rates: [
                "USD": RateSnapshot(value: Fixture.usd, updatedAt: Fixture.fileTime),
                "JPY": RateSnapshot(value: Fixture.jpy, updatedAt: Fixture.fileTime)
            ]
        )
        try RatesService.writeCache(cache, to: url)
        #expect(RatesService.loadCache(from: url) == cache)
        #expect(RatesService.loadCache(from: url.appendingPathExtension("missing")) == .empty)
    }
}
