//
//  BackgroundActivityView_iOS.swift
//  Arké
//
//  X-Ray surface for the background event journal
//  (Background_Activity_Journal.md, Phase 2): a status header answering
//  "is background execution working?" at a glance, and the event history
//  behind it. Header state is this session's knowledge plus the live
//  BGTaskScheduler; history comes from the journal.
//

import SwiftUI
import BackgroundTasks
import ArkeUI

// MARK: - Status model (plain, previewable)

struct BackgroundActivityStatus {
    var notificationsEnabled = false
    var hasAPNSToken = false
    var tokenExpiry: Date?
    var nextForegroundRefresh: Date?
    var hasPendingBGTask = false
    var pendingBGTaskDate: Date?
    var lastRegistration: BackgroundEvent?
    var lastBGTaskWake: BackgroundEvent?
    var lastWakePush: BackgroundEvent?
}

// MARK: - X-Ray section

struct BackgroundActivitySectionView_iOS: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @State private var status: BackgroundActivityStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(localized: "data_background_activity", defaultValue: "Background Activity"))
                    .font(.system(size: 24, design: .serif))

                Spacer()
            }

            if let status {
                BackgroundActivityStatusRows(status: status)

                NavigationLink {
                    BackgroundActivityView_iOS()
                } label: {
                    HStack {
                        Text(String(localized: "action_view_background_events", defaultValue: "View events"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, 5)
            } else {
                SkeletonLoader(
                    itemCount: 3,
                    itemHeight: 22,
                    spacing: 10,
                    cornerRadius: 8
                )
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await load()
        }
    }

    private func load() async {
        let events = await BackgroundEventJournal.shared.recentEvents(limit: 500)
        let pending = await BackgroundTaskCoordinator.shared.pendingRefreshRequest()

        status = BackgroundActivityStatus(
            notificationsEnabled: UserDefaults.standard.bool(forKey: "notifications_enabled"),
            hasAPNSToken: UserDefaults.standard.string(forKey: "apns_device_token")?.isEmpty == false,
            tokenExpiry: walletManager.relayAuthExpiry,
            nextForegroundRefresh: walletManager.relayAuthNextForegroundRefresh,
            hasPendingBGTask: pending.isPending,
            pendingBGTaskDate: pending.earliest,
            lastRegistration: events.first { $0.kind == .relayRegistration && $0.outcome == "success" },
            lastBGTaskWake: events.first { $0.kind == .bgTaskWake },
            lastWakePush: events.first { $0.kind == .wakePush }
        )
    }
}

// MARK: - Status rows

struct BackgroundActivityStatusRows: View {
    let status: BackgroundActivityStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledValueRow(
                String(localized: "data_bg_notifications_label", defaultValue: "Notifications"),
                value: status.notificationsEnabled
                    ? String(localized: "data_bg_value_on", defaultValue: "On")
                    : String(localized: "data_bg_value_off", defaultValue: "Off"),
                valueColor: status.notificationsEnabled ? nil : .orange
            )

            LabeledValueRow(
                String(localized: "data_bg_push_token_label", defaultValue: "Push token"),
                value: status.hasAPNSToken
                    ? String(localized: "data_bg_value_present", defaultValue: "Present")
                    : String(localized: "data_bg_value_missing", defaultValue: "Missing"),
                valueColor: status.hasAPNSToken ? nil : .orange
            )

            LabeledValueRow(
                String(localized: "data_bg_auth_expires_label", defaultValue: "Relay auth expires"),
                value: Self.formatted(status.tokenExpiry)
            )

            LabeledValueRow(
                String(localized: "data_bg_next_timer_label", defaultValue: "Next timer refresh"),
                value: Self.formatted(status.nextForegroundRefresh)
            )

            LabeledValueRow(
                String(localized: "data_bg_next_bgtask_label", defaultValue: "Next background task"),
                value: nextBGTaskValue,
                valueColor: status.hasPendingBGTask ? nil : .orange
            )

            LabeledValueRow(
                String(localized: "data_bg_last_registration_label", defaultValue: "Last registration"),
                value: Self.eventSummary(status.lastRegistration)
            )

            LabeledValueRow(
                String(localized: "data_bg_last_bg_wake_label", defaultValue: "Last background wake"),
                value: Self.eventSummary(status.lastBGTaskWake)
            )

            LabeledValueRow(
                String(localized: "data_bg_last_wake_push_label", defaultValue: "Last wake push"),
                value: Self.eventSummary(status.lastWakePush)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextBGTaskValue: String {
        guard status.hasPendingBGTask else {
            return String(localized: "data_bg_value_none_scheduled", defaultValue: "None scheduled")
        }
        guard let date = status.pendingBGTaskDate else {
            return String(localized: "data_bg_value_system_discretion", defaultValue: "At system discretion")
        }
        return Self.formatted(date)
    }

    private static func formatted(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "data_bg_value_none", defaultValue: "—")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "5 min ago (wake_push)" — relative time plus the raw trigger when present.
    private static func eventSummary(_ event: BackgroundEvent?) -> String {
        guard let event else {
            return String(localized: "data_bg_value_never", defaultValue: "Never")
        }
        let when = event.date.formatted(.relative(presentation: .named))
        if let trigger = event.trigger {
            return "\(when) (\(trigger))"
        }
        return when
    }
}

// MARK: - Events screen

struct BackgroundActivityView_iOS: View {
    @State private var events: [BackgroundEvent]
    @State private var isLoading: Bool
    @State private var showClearConfirmation = false
    private let isPreview: Bool

    init(previewEvents: [BackgroundEvent]? = nil) {
        _events = State(initialValue: previewEvents ?? [])
        _isLoading = State(initialValue: previewEvents == nil)
        isPreview = previewEvents != nil
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_bg_no_events", defaultValue: "No background events yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(events.enumerated()), id: \.offset) { _, event in
                    BackgroundEventRow(event: event)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "data_background_events_title", defaultValue: "Background Events"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "action_clear_background_events", defaultValue: "Clear events"))
                .disabled(events.isEmpty)
            }
        }
        .confirmationDialog(
            String(localized: "data_bg_clear_confirm_title", defaultValue: "Clear all background events?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "action_clear_background_events", defaultValue: "Clear events"), role: .destructive) {
                Task {
                    await BackgroundEventJournal.shared.clear()
                    events = []
                }
            }
        }
        .task {
            guard !isPreview else { return }
            events = await BackgroundEventJournal.shared.recentEvents()
            isLoading = false
        }
    }
}

// MARK: - Event row

struct BackgroundEventRow: View {
    let event: BackgroundEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(outcomeColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.body)
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !detailLine.isEmpty {
                    // Raw journal fields, deliberately unlocalized (X-Ray ethos)
                    Text(detailLine)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        var parts: [String] = []
        if let outcome = event.outcome { parts.append(outcome) }
        if let trigger = event.trigger { parts.append(trigger) }
        if let elapsedMs = event.elapsedMs { parts.append("\(elapsedMs)ms") }
        if let detail = event.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private var title: String {
        switch event.kind {
        case .bgTaskWake:
            String(localized: "data_bg_event_bgtask_wake", defaultValue: "Background task ran")
        case .wakePush:
            String(localized: "data_bg_event_wake_push", defaultValue: "Auth wake push")
        case .mailboxPush:
            String(localized: "data_bg_event_mailbox_push", defaultValue: "Mailbox push")
        case .relayRegistration:
            String(localized: "data_bg_event_registration", defaultValue: "Relay registration")
        case .bgTaskScheduled:
            String(localized: "data_bg_event_bgtask_scheduled", defaultValue: "Background task requested")
        case .foregroundTimerFired:
            String(localized: "data_bg_event_timer", defaultValue: "Refresh timer fired")
        case .coldLaunch:
            String(localized: "data_bg_event_cold_launch", defaultValue: "App launched")
        }
    }

    private var icon: String {
        switch event.kind {
        case .bgTaskWake: "alarm"
        case .wakePush: "antenna.radiowaves.left.and.right"
        case .mailboxPush: "tray.and.arrow.down"
        case .relayRegistration: "checkmark.seal"
        case .bgTaskScheduled: "calendar.badge.clock"
        case .foregroundTimerFired: "timer"
        case .coldLaunch: "power"
        }
    }

    private var outcomeColor: Color {
        switch event.outcome {
        case "success", "refreshed": .green
        case "failure", "failed": .red
        default: .secondary
        }
    }
}

// MARK: - Previews

#Preview("Status rows") {
    BackgroundActivityStatusRows(status: BackgroundActivityStatus(
        notificationsEnabled: true,
        hasAPNSToken: true,
        tokenExpiry: Date().addingTimeInterval(20 * 3600),
        nextForegroundRefresh: Date().addingTimeInterval(19 * 3600),
        hasPendingBGTask: true,
        pendingBGTaskDate: Date().addingTimeInterval(10 * 3600),
        lastRegistration: BackgroundEvent(kind: .relayRegistration, outcome: "success", trigger: "wake_push", ts: Date().timeIntervalSince1970 - 300, pid: 1),
        lastBGTaskWake: BackgroundEvent(kind: .bgTaskWake, outcome: "refreshed", elapsedMs: 640, ts: Date().timeIntervalSince1970 - 7200, pid: 1),
        lastWakePush: BackgroundEvent(kind: .wakePush, outcome: "refreshed", elapsedMs: 410, ts: Date().timeIntervalSince1970 - 300, pid: 1)
    ))
    .padding()
}

#Preview("Events") {
    NavigationStack {
        BackgroundActivityView_iOS(previewEvents: [
            BackgroundEvent(kind: .wakePush, outcome: "refreshed", elapsedMs: 410, ts: Date().timeIntervalSince1970 - 300, pid: 3),
            BackgroundEvent(kind: .relayRegistration, outcome: "success", trigger: "wake_push", ts: Date().timeIntervalSince1970 - 301, pid: 3),
            BackgroundEvent(kind: .bgTaskScheduled, detail: "2026-09-18T21:00:00Z", ts: Date().timeIntervalSince1970 - 302, pid: 3),
            BackgroundEvent(kind: .bgTaskWake, outcome: "failed", elapsedMs: 25000, ts: Date().timeIntervalSince1970 - 86400, pid: 2),
            BackgroundEvent(kind: .coldLaunch, outcome: "success", elapsedMs: 2840, ts: Date().timeIntervalSince1970 - 90000, pid: 2),
            BackgroundEvent(kind: .mailboxPush, detail: "mailbox_arkoor", ts: Date().timeIntervalSince1970 - 100000, pid: 1),
        ])
    }
}

#Preview("Events - empty") {
    NavigationStack {
        BackgroundActivityView_iOS(previewEvents: [])
    }
}
