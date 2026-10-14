//
//  DebugLogExporter.swift
//  Arké
//
//  Generates a shareable debug log file from the app's unified log so users
//  can send diagnostics to the dev team. Reads back the current process's
//  OSLog/Logger entries (app subsystem + bark's bridged Rust logs) via
//  OSLogStore — no changes to existing log call sites are required.
//

import Foundation
import OSLog

/// Produces a debug log file from the app's own log entries.
///
/// Privacy: log messages may contain transaction metadata (amounts, addresses)
/// but never the wallet mnemonic. The metadata header below intentionally adds
/// no secrets.
///
/// Marked `nonisolated` so its pure helpers can run on the detached background
/// task (this module defaults to main-actor isolation).
nonisolated enum DebugLogExporter {

    enum ExportError: LocalizedError {
        case storeUnavailable(Error)

        var errorDescription: String? {
            switch self {
            case .storeUnavailable(let error):
                return "Could not read the device logs: \(error.localizedDescription)"
            }
        }
    }

    /// The subsystems included in the export:
    /// - the app's own logs (`Logger` convention: `Bundle.main.bundleIdentifier ?? "com.arke"`)
    /// - bark's internal Rust logs, bridged via `barkAttachOSLogger()` in BarkWalletFFI
    private static var subsystems: [String] {
        [Bundle.main.bundleIdentifier ?? "com.arke", "tech.second.bark"]
    }

    /// Generates a `.log` file in the temporary directory and returns its URL.
    ///
    /// - Parameters:
    ///   - hours: How far back to collect log entries. Defaults to 24 hours.
    ///   - contextLines: Optional caller-supplied lines (e.g. network, wallet
    ///     mode) appended to the metadata header.
    /// - Returns: The URL of the written log file (ready to hand to a share sheet).
    static func generateLogFile(hours: Int = 24, contextLines: [String] = []) async throws -> URL {
        // The background event journal persists across sessions where
        // OSLogStore can't (current-process scope) - append it so background
        // history shows up in user-submitted diagnostics.
        let journalEvents = await BackgroundEventJournal.shared.recentEvents(limit: 200)

        // Reading the unified log can be slow; keep it off the main thread.
        return try await Task.detached(priority: .userInitiated) {
            let body = try collectLogBody(hours: hours)
            let header = makeHeader(contextLines: contextLines, entryCount: body.entryCount, levelCounts: body.levelCounts)
            let contents = header + "\n" + body.text + "\n" + makeJournalSection(events: journalEvents)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("arke-debug-\(fileTimestamp()).log")
            try contents.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        }.value
    }

    // MARK: - Log collection

    private struct LogBody {
        let text: String
        let entryCount: Int
        /// Entry count per level label, for the header: on device, info-level
        /// entries are memory-only and the oldest are purged as the buffer
        /// fills, so a reader needs to know how much of the session survived
        /// at each level before trusting a gap (exports of 2026-10-14).
        let levelCounts: [String: Int]
    }

    private static func collectLogBody(hours: Int) throws -> LogBody {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            throw ExportError.storeUnavailable(error)
        }

        let since = store.position(date: Date().addingTimeInterval(-Double(hours) * 3600))
        let predicate = NSPredicate(format: "subsystem IN %@", subsystems)
        let entries = try store.getEntries(at: since, matching: predicate)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        var levelCounts: [String: Int] = [:]
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            let timestamp = formatter.string(from: log.date)
            let level = levelLabel(log.level)
            levelCounts[level, default: 0] += 1
            let category = log.category.isEmpty ? "-" : log.category
            lines.append("\(timestamp)  [\(level)]  [\(category)]  \(log.composedMessage)")
        }

        if lines.isEmpty {
            return LogBody(text: "(no log entries found for this session)\n", entryCount: 0, levelCounts: [:])
        }
        return LogBody(text: lines.joined(separator: "\n") + "\n", entryCount: lines.count, levelCounts: levelCounts)
    }

    private static func levelLabel(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "UNDEF"
        case .debug:     return "DEBUG"
        case .info:      return "INFO"
        case .notice:    return "NOTICE"
        case .error:     return "ERROR"
        case .fault:     return "FAULT"
        @unknown default: return "?"
        }
    }

    // MARK: - Background event journal section

    /// One line per journal event, newest first, local-time ISO timestamps.
    /// The events carry no secrets by construction (Background_Activity_Journal.md).
    private static func makeJournalSection(events: [BackgroundEvent]) -> String {
        var lines = ["===== Background event journal (newest first, \(events.count) events) ====="]

        if events.isEmpty {
            lines.append("(no journal events)")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            for event in events {
                var parts = [formatter.string(from: event.date), event.kind.rawValue]
                if let outcome = event.outcome { parts.append(outcome) }
                if let trigger = event.trigger { parts.append("trigger=\(trigger)") }
                if let elapsedMs = event.elapsedMs { parts.append("\(elapsedMs)ms") }
                if let detail = event.detail { parts.append(detail) }
                parts.append("pid=\(event.pid)")
                lines.append(parts.joined(separator: "  "))
            }
        }

        lines.append("==========================")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Header

    private static func makeHeader(contextLines: [String], entryCount: Int, levelCounts: [String: Int]) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        let os = ProcessInfo.processInfo.operatingSystemVersion

        let levelSummary = levelCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key.lowercased()) \($0.value)" }
            .joined(separator: ", ")

        var lines: [String] = [
            "===== Arké debug log =====",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            // OSLogStore current-process scope only exposes this app session.
            "Scope: current session  •  Entries: \(entryCount)" + (levelSummary.isEmpty ? "" : " (\(levelSummary))"),
            // Info entries are memory-only on device and the oldest are purged
            // as the buffer fills; notice and above reach the data store. The
            // launch markers log at notice for that reason.
            "Levels: notice+ persisted; info is best-effort and may be missing from the start of the session",
            "App version: \(version) (\(build))",
            "OS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        ]

        #if os(iOS)
        lines.append("Device: \(deviceModelIdentifier())")
        #endif

        lines.append(contentsOf: contextLines)
        lines.append("==========================")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Raw machine identifier (e.g. "iPhone16,1") — more useful for diagnostics
    /// than a mapped marketing name.
    private static func deviceModelIdentifier() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "unknown" : identifier
        #else
        return "unknown"
        #endif
    }

    // MARK: - Filename timestamp

    /// `yyyyMMdd-HHmmss` for the filename, without relying on a locale-sensitive
    /// DateFormatter.
    private static func fileTimestamp() -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        func pad(_ v: Int?, _ width: Int = 2) -> String {
            String(format: "%0\(width)d", v ?? 0)
        }
        return "\(pad(c.year, 4))\(pad(c.month))\(pad(c.day))-\(pad(c.hour))\(pad(c.minute))\(pad(c.second))"
    }
}
