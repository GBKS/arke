//
//  ForcedMoveProgressView.swift
//  Arké
//
//  Created by Christoph on 7/9/26.
//

import SwiftUI

/// Where an in-flight forced move currently stands, from the user's perspective.
/// Progression and claiming are fully automatic (ExitProgressionService); this
/// view only reassures and tells the user when to check back.
public enum ForcedMovePhase: Equatable {
    /// Exit started, exit transactions not yet confirmed — no ETA available.
    case starting
    /// Exit confirmed, waiting out the challenge period.
    case waiting(hoursRemaining: Int)
    /// Claimable or claim in progress — funds are moving to Savings automatically.
    case finishing
}

/// Whether check-in reminders can fire. Anything but `enabled` renders a
/// prompt row; the host decides what tapping it does (system prompt vs. Settings).
public enum ForcedMoveReminderState: Equatable {
    case enabled
    case canAsk
    case denied
}

public struct ForcedMoveProgressView<Media: View>: View {
    let phase: ForcedMovePhase
    let reminderState: ForcedMoveReminderState
    let onEnableReminders: () -> Void
    let media: Media

    public init(
        phase: ForcedMovePhase,
        reminderState: ForcedMoveReminderState,
        onEnableReminders: @escaping () -> Void,
        @ViewBuilder media: () -> Media
    ) {
        self.phase = phase
        self.reminderState = reminderState
        self.onEnableReminders = onEnableReminders
        self.media = media()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            media
                .frame(maxWidth: .infinity, maxHeight: 300)
                .cornerRadius(25)
                .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.title, design: .serif))

                Text(statusText)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            }

            if reminderState != .enabled {
                reminderPrompt
            }

            VStack(alignment: .leading, spacing: 8) {
                ForcedMoveExpectationRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "forced_move_expect_checkin",
                                 defaultValue: "Check in about once an hour. Opening the app keeps the move going.",
                                 bundle: .module)
                )

                ForcedMoveExpectationRow(
                    icon: "bell",
                    text: String(localized: "forced_move_expect_reminders",
                                 defaultValue: "We'll remind you to check in.",
                                 bundle: .module)
                )

                ForcedMoveExpectationRow(
                    icon: "checkmark.seal",
                    text: String(localized: "forced_move_expect_automatic",
                                 defaultValue: "When it completes, the bitcoin is added to your Savings balance automatically.",
                                 bundle: .module)
                )
            }
            .lineSpacing(6)

            Spacer()
        }
    }

    private var title: String {
        switch phase {
        case .starting, .waiting:
            return String(localized: "forced_move_underway_title",
                          defaultValue: "Forced move underway", bundle: .module)
        case .finishing:
            return String(localized: "forced_move_finishing_title",
                          defaultValue: "Finishing your forced move", bundle: .module)
        }
    }

    private var statusText: String {
        switch phase {
        case .starting:
            return String(
                localized: "forced_move_starting",
                defaultValue: "Getting started. Check back in about an hour.",
                bundle: .module
            )
        case .waiting(let hoursRemaining):
            if hoursRemaining > 1 {
                return String(
                    localized: "forced_move_hours_remaining",
                    defaultValue: "About \(hoursRemaining) hours to go.",
                    bundle: .module
                )
            } else if hoursRemaining == 1 {
                return String(
                    localized: "forced_move_one_hour_remaining",
                    defaultValue: "About 1 hour to go.",
                    bundle: .module
                )
            } else {
                return String(
                    localized: "forced_move_less_than_hour",
                    defaultValue: "Less than 1 hour to go.",
                    bundle: .module
                )
            }
        case .finishing:
            return String(
                localized: "forced_move_finishing",
                defaultValue: "Your bitcoin is on its way to your Savings balance.",
                bundle: .module
            )
        }
    }

    private var reminderPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 24))
                    .foregroundColor(.Arke.orange)

                Text(String(localized: "forced_move_reminders_off", defaultValue: "Reminders are off. Turn on notifications so you don't miss a check-in.", bundle: .module))
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Button {
                onEnableReminders()
            } label: {
                Text(
                    reminderState == .denied
                        ? String(localized: "forced_move_open_settings",
                                 defaultValue: "Open Settings", bundle: .module)
                        : String(localized: "forced_move_turn_on_reminders",
                                 defaultValue: "Turn On Notifications", bundle: .module)
                )
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.Arke.goldLabel)
            }
            .buttonStyle(.bordered)
            .tint(Color.Arke.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
}

struct ForcedMoveExpectationRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .frame(width: 30)

            Text(text)
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Starting") {
    ForcedMoveProgressView(
        phase: .starting,
        reminderState: .enabled,
        onEnableReminders: {}
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}

#Preview("Waiting") {
    ForcedMoveProgressView(
        phase: .waiting(hoursRemaining: 7),
        reminderState: .enabled,
        onEnableReminders: {}
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}

#Preview("Finishing") {
    ForcedMoveProgressView(
        phase: .finishing,
        reminderState: .enabled,
        onEnableReminders: {}
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}

#Preview("Reminders Off") {
    ForcedMoveProgressView(
        phase: .waiting(hoursRemaining: 3),
        reminderState: .denied,
        onEnableReminders: {}
    ) {
        Image("exit")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .padding()
}
