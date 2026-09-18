//
//  BackgroundEventJournalTests.swift
//  Arke
//
//  Pins the journal contract from Background_Activity_Journal.md: append/
//  read round-trip, newest-first ordering, ring-buffer compaction (count and
//  age caps), and torn-line tolerance — a corrupted trailing line must never
//  poison reads or survive compaction.
//

import Foundation
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Background Event Journal Tests")
struct BackgroundEventJournalTests {

    /// Fresh journal on a unique temp file per test.
    private func makeJournal(maxEvents: Int = 1000, maxAge: TimeInterval = 30 * 24 * 3600) -> (BackgroundEventJournal, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("events.jsonl")
        return (BackgroundEventJournal(fileURL: url, maxEvents: maxEvents, maxAge: maxAge), url)
    }

    private func event(kind: BackgroundEvent.Kind = .bgTaskWake, ts: TimeInterval, detail: String? = nil) -> BackgroundEvent {
        BackgroundEvent(kind: kind, detail: detail, ts: ts, pid: 1)
    }

    // MARK: - Round trip

    @Test("Appended events read back newest-first with all fields")
    func appendReadRoundTrip() async throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = BackgroundEvent(kind: .relayRegistration, outcome: "success", trigger: "wake_push", elapsedMs: 420, detail: nil, ts: 100, pid: 7)
        let second = BackgroundEvent(kind: .wakePush, outcome: "refreshed", ts: 200, pid: 7)
        await journal.append(first)
        await journal.append(second)

        let events = await journal.recentEvents()
        #expect(events == [second, first])
        #expect(events[1].trigger == "wake_push")
        #expect(events[1].elapsedMs == 420)
    }

    @Test("recentEvents honors its limit, keeping the newest")
    func recentEventsLimit() async throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        for i in 0..<10 {
            await journal.append(event(ts: TimeInterval(i)))
        }
        let events = await journal.recentEvents(limit: 3)
        #expect(events.map(\.ts) == [9, 8, 7])
    }

    @Test("Empty or missing file reads as no events")
    func missingFileIsEmpty() async {
        let (journal, _) = makeJournal()
        let events = await journal.recentEvents()
        #expect(events.isEmpty)
    }

    // MARK: - Torn-line tolerance

    @Test("A torn or garbage line is skipped, not fatal")
    func tornLineSkipped() async throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await journal.append(event(ts: 1))
        await journal.append(event(ts: 2))
        // Simulate a torn write: a partial JSON line at the end of the file
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"v\":1,\"ts\":3,\"ki".utf8))
        try handle.close()

        let events = await journal.recentEvents()
        #expect(events.map(\.ts) == [2, 1])
    }

    // MARK: - Compaction

    @Test("Compaction trims to the event cap, keeping the newest")
    func compactionCountCap() async throws {
        let (journal, url) = makeJournal(maxEvents: 3)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        for i in 0..<5 {
            await journal.append(event(ts: TimeInterval(i)))
        }
        await journal.compactIfNeeded(now: Date(timeIntervalSince1970: 10))

        let events = await journal.recentEvents()
        #expect(events.map(\.ts) == [4, 3, 2])
    }

    @Test("Compaction drops events older than the age cap")
    func compactionAgeCap() async throws {
        let (journal, url) = makeJournal(maxAge: 100)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await journal.append(event(ts: 50))   // stale at now=200
        await journal.append(event(ts: 150))  // fresh
        await journal.compactIfNeeded(now: Date(timeIntervalSince1970: 200))

        let events = await journal.recentEvents()
        #expect(events.map(\.ts) == [150])
    }

    @Test("Compaction rewrites away garbage lines")
    func compactionRemovesGarbage() async throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await journal.append(event(ts: 1))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json at all\n".utf8))
        try handle.close()
        await journal.append(event(ts: 2))

        await journal.compactIfNeeded(now: Date(timeIntervalSince1970: 10))

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(!contents.contains("not json"))
        let events = await journal.recentEvents()
        #expect(events.map(\.ts) == [2, 1])
    }

    @Test("Within caps and undamaged, compaction leaves the file alone")
    func compactionNoOpWithinCaps() async throws {
        let (journal, url) = makeJournal(maxEvents: 10)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await journal.append(event(ts: 1))
        let before = try Data(contentsOf: url)
        await journal.compactIfNeeded(now: Date(timeIntervalSince1970: 2))
        let after = try Data(contentsOf: url)
        #expect(before == after)
    }

    // MARK: - Clear

    @Test("Clear removes the journal; appends still work afterwards")
    func clearThenAppend() async throws {
        let (journal, url) = makeJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await journal.append(event(ts: 1))
        await journal.clear()
        #expect(await journal.recentEvents().isEmpty)

        await journal.append(event(ts: 2))
        #expect(await journal.recentEvents().map(\.ts) == [2])
    }

    // MARK: - Pure helpers

    @Test("compact() applies age filter before the count cap")
    func compactPureLogic() {
        let events = [
            BackgroundEvent(kind: .bgTaskWake, ts: 10, pid: 1),   // stale
            BackgroundEvent(kind: .bgTaskWake, ts: 100, pid: 1),
            BackgroundEvent(kind: .bgTaskWake, ts: 110, pid: 1),
            BackgroundEvent(kind: .bgTaskWake, ts: 120, pid: 1),
        ]
        let kept = BackgroundEventJournal.compact(events, maxEvents: 2, maxAge: 100, now: 150)
        #expect(kept.map(\.ts) == [110, 120])
    }

    @Test("Unknown event kind in a future schema line is skipped")
    func unknownKindSkipped() {
        let data = Data("""
        {"v":1,"ts":1,"kind":"bg_task_wake","pid":1}
        {"v":2,"ts":2,"kind":"quantum_wake","pid":1}
        """.utf8)
        let events = BackgroundEventJournal.decodeEvents(from: data)
        #expect(events.count == 1)
        #expect(events[0].kind == .bgTaskWake)
    }
}
