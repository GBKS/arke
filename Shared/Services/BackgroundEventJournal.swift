//
//  BackgroundEventJournal.swift
//  Arké
//
//  On-device event journal for background execution diagnostics
//  (Background_Activity_Journal.md). OSLogStore can't read past sessions
//  in-app, so background wakes — short-lived cold launches — are invisible
//  to the app unless it persists its own record. Append-only JSONL, ring-
//  buffered, no secrets by construction: fixed event kinds, no amounts,
//  addresses, mailbox ids, or tokens.
//

import Foundation
import OSLog

/// One journaled diagnostic event. `detail` is a short bounded string
/// (a requested date, a push type name) — never user data.
nonisolated struct BackgroundEvent: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        /// A `cash.arke.refresh` BGAppRefreshTask ran
        case bgTaskWake = "bg_task_wake"
        /// A `mailbox_auth_refresh` silent push was handled
        case wakePush = "wake_push"
        /// A generic mailbox push was routed to refresh()
        case mailboxPush = "mailbox_push"
        /// A `/v1/register` attempt finished
        case relayRegistration = "relay_registration"
        /// A BGAppRefreshTask request was submitted (detail = requested date)
        case bgTaskScheduled = "bg_task_scheduled"
        /// The in-process auth refresh timer fired
        case foregroundTimerFired = "foreground_timer_fired"
        /// Cold launch → wallet ready (elapsedMs is the launch timing)
        case coldLaunch = "cold_launch"
    }

    /// Schema version, for forward-compatible readers
    var v: Int = 1
    /// UNIX seconds
    let ts: TimeInterval
    let kind: Kind
    var outcome: String?
    var trigger: String?
    var elapsedMs: Int?
    var detail: String?
    /// Process id — a run of identical pids is one process session, which is
    /// how cold background launches show up in the history
    let pid: Int32

    var date: Date { Date(timeIntervalSince1970: ts) }

    init(
        kind: Kind,
        outcome: String? = nil,
        trigger: String? = nil,
        elapsedMs: Int? = nil,
        detail: String? = nil,
        ts: TimeInterval = Date().timeIntervalSince1970,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.ts = ts
        self.kind = kind
        self.outcome = outcome
        self.trigger = trigger
        self.elapsedMs = elapsedMs
        self.detail = detail
        self.pid = pid
    }
}

/// Owns the journal file. Append must work from a cold background launch
/// within the ~30s window without wallet init or the model container, and
/// (on iOS) before first unlock — hence a flat file with
/// `FileProtectionType.none` (justified by the no-secrets schema) rather
/// than SwiftData/SQLite. Compaction runs only from foreground launch; the
/// background wake path stays pure-append. Journaling failures are logged
/// and swallowed — they must never fail a background pass.
actor BackgroundEventJournal {

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "EventJournal")

    static let shared = BackgroundEventJournal()

    private let fileURL: URL
    private let maxEvents: Int
    private let maxAge: TimeInterval

    /// Default caps per the plan: ~1,000 events / 30 days.
    init(
        fileURL: URL = BackgroundEventJournal.defaultFileURL,
        maxEvents: Int = 1000,
        maxAge: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.fileURL = fileURL
        self.maxEvents = maxEvents
        self.maxAge = maxAge
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("background-events.jsonl")
    }

    // MARK: - Recording

    /// Fire-and-forget entry point for instrumentation call sites (sync or
    /// async, any isolation). The timestamp is taken here, at the call site,
    /// not when the append lands.
    nonisolated static func record(
        _ kind: BackgroundEvent.Kind,
        outcome: String? = nil,
        trigger: String? = nil,
        elapsedMs: Int? = nil,
        detail: String? = nil
    ) {
        let event = BackgroundEvent(kind: kind, outcome: outcome, trigger: trigger, elapsedMs: elapsedMs, detail: detail)
        Task { await shared.append(event) }
    }

    func append(_ event: BackgroundEvent) {
        do {
            try ensureFileExists()
            var line = try JSONEncoder().encode(event)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            Self.logger.error("Append failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reading

    /// Newest first. Undecodable lines (torn write, future schema) are
    /// skipped, never fatal.
    func recentEvents(limit: Int = 200) -> [BackgroundEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return Self.decodeEvents(from: data).suffix(limit).reversed()
    }

    // MARK: - Maintenance

    /// Trims the journal to the caps. Call from foreground launch only.
    func compactIfNeeded(now: Date = Date()) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let events = Self.decodeEvents(from: data)
        let kept = Self.compact(events, maxEvents: maxEvents, maxAge: maxAge, now: now.timeIntervalSince1970)
        // Also rewrite when decode dropped lines (torn/garbage), so damage
        // doesn't accumulate
        let lineCount = data.split(separator: 0x0A).count
        guard kept.count < events.count || events.count < lineCount else { return }
        do {
            try rewrite(events: kept)
        } catch {
            Self.logger.error("Compaction failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Pure helpers (unit-tested directly)

    nonisolated static func decodeEvents(from data: Data) -> [BackgroundEvent] {
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(BackgroundEvent.self, from: Data(line))
        }
    }

    nonisolated static func compact(
        _ events: [BackgroundEvent],
        maxEvents: Int,
        maxAge: TimeInterval,
        now: TimeInterval
    ) -> [BackgroundEvent] {
        let cutoff = now - maxAge
        return Array(events.filter { $0.ts >= cutoff }.suffix(maxEvents))
    }

    // MARK: - File plumbing

    private func ensureFileExists() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: fileURL.path, contents: nil, attributes: Self.fileAttributes)
    }

    private func rewrite(events: [BackgroundEvent]) throws {
        let encoder = JSONEncoder()
        var data = Data()
        for event in events {
            try data.append(encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: fileURL, options: .atomic)
        // Atomic replace resets file attributes - re-apply the protection class
        if let attributes = Self.fileAttributes {
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: fileURL.path)
        }
    }

    /// `FileProtectionType.none` so a pre-first-unlock wake (the
    /// keychain-unavailable branch) can journal itself — one of the events
    /// this exists to capture. Safe because the schema carries no secrets.
    private nonisolated static var fileAttributes: [FileAttributeKey: Any]? {
        #if os(iOS)
        [.protectionKey: FileProtectionType.none]
        #else
        nil
        #endif
    }
}
