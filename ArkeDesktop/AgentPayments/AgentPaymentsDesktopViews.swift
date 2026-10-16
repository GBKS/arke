//
//  AgentPaymentsDesktopViews.swift
//  ArkeDesktop
//
//  Desktop UI for agent payments: the host modifier that starts the service
//  when the toggle is on, the request card, and the settings toggle row.
//

import SwiftUI
import ArkeUI

// MARK: - Host

/// Starts and stops the Mac service with the toggle and shows the request card.
/// Attach inside the environment chain that provides WalletManager.
struct AgentPaymentsDesktopHost: ViewModifier {
    @Environment(WalletManager.self) private var walletManager
    @AppStorage(AgentPayments.enabledKey) private var isEnabled = false

    private var service: AgentPaymentsMacService { .shared }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if isEnabled, let record = service.visibleRecord {
                    AgentPaymentCard(record: record, phoneName: service.phoneName) {
                        service.dismiss(record.id)
                    }
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: service.visibleRecord?.id)
            .task(id: isEnabled) {
                if isEnabled {
                    service.start(walletManager: walletManager)
                } else {
                    service.stop()
                }
            }
    }
}

extension View {
    func agentPaymentsDesktopHost() -> some View {
        modifier(AgentPaymentsDesktopHost())
    }
}

// MARK: - Request card

struct AgentPaymentCard: View {
    let record: AgentPaymentRecord
    let phoneName: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    String(localized: "agent_payments_card_title", defaultValue: "Payment request from \(record.agent)"),
                    systemImage: "sparkles"
                )
                .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "agent_payments_card_close", defaultValue: "Close"))
            }

            if let amount = record.amountSats {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BitcoinFormatter.shared.formatAmount(Int(amount)))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    FiatAmountText(sats: Int(amount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let description = record.invoiceDescription, !description.isEmpty {
                Text(description)
                    .font(.body)
            }

            if !record.reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "agent_payments_agent_says", defaultValue: "The agent says (unverified)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.reason)
                        .font(.callout)
                        .italic()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            statusRow
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch record.state {
        case .received, .awaitingApproval:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "agent_payments_waiting", defaultValue: "Waiting for approval on \(phoneName ?? "your phone")"))
            }
        case .paying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "agent_payments_paying", defaultValue: "Paying…"))
            }
        case .paid:
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "agent_payments_paid", defaultValue: "Paid"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let preimage = record.preimage {
                    Text(String(localized: "agent_payments_proof", defaultValue: "Proof: \(String(preimage.prefix(16)))…"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        case .declined:
            Label(String(localized: "agent_payments_declined", defaultValue: "Declined on the phone"), systemImage: "hand.raised.fill")
                .foregroundStyle(.orange)
        case .refused:
            Label(errorText, systemImage: "nosign")
                .foregroundStyle(.orange)
        case .failed:
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .expired:
            Label(String(localized: "agent_payments_expired", defaultValue: "Request expired"), systemImage: "clock.badge.xmark")
                .foregroundStyle(.secondary)
        }
    }

    private var errorText: String {
        guard let error = record.error else {
            return String(localized: "agent_payments_failed", defaultValue: "Payment failed")
        }
        return AgentPaymentError(rawValue: error)?.message ?? error
    }
}

// MARK: - Settings row

/// "Agent payments (experimental)" toggle for the Experimental settings section
struct AgentPaymentsSettingsToggle: View {
    @AppStorage(AgentPayments.enabledKey) private var isEnabled = false

    private var service: AgentPaymentsMacService { .shared }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.Arke.purple)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "agent_payments_setting", defaultValue: "Agent payments"))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        guard isEnabled else {
            return String(localized: "agent_payments_setting_hint", defaultValue: "Let AI agents request payments you approve on your phone")
        }
        switch service.linkStatus {
        case .off:
            return String(localized: "agent_payments_status_starting", defaultValue: "Starting…")
        case .noSeed:
            return String(localized: "agent_payments_status_no_seed", defaultValue: "This Mac doesn't have the recovery phrase yet")
        case .waitingForPhone:
            return String(localized: "agent_payments_status_waiting", defaultValue: "Waiting for your phone — open Arké there")
        case .connected(let name, _):
            return String(localized: "agent_payments_status_connected", defaultValue: "Connected: \(name)")
        case .failed(let reason):
            return reason
        }
    }
}
