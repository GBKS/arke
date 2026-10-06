//
//  AgentPaymentsPhoneViews.swift
//  ArkeMobile
//
//  Phone UI for agent payments: the host modifier that starts the service
//  when the toggle is on and presents the approval sheet, the sheet itself,
//  and the settings toggle row.
//

import SwiftUI
import ArkeUI

// MARK: - Host

/// Attach inside the environment chain that provides WalletManager.
struct AgentPaymentsPhoneHost: ViewModifier {
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AgentPayments.enabledKey) private var isEnabled = false

    private var service: AgentPaymentsPhoneService { .shared }

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { isEnabled ? service.currentApproval : nil },
                set: { _ in }
            )) { approval in
                AgentPaymentApprovalSheet(approval: approval)
                    .interactiveDismissDisabled()
            }
            .task(id: isEnabled) {
                if isEnabled {
                    service.start(walletManager: walletManager)
                } else {
                    service.stop()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isEnabled {
                    service.reconnectIfNeeded()
                }
            }
    }
}

extension View {
    func agentPaymentsPhoneHost() -> some View {
        modifier(AgentPaymentsPhoneHost())
    }
}

// MARK: - Approval sheet

struct AgentPaymentApprovalSheet: View {
    let approval: AgentPaymentApproval

    private var service: AgentPaymentsPhoneService { .shared }

    private var phase: AgentPaymentsPhoneService.Phase {
        service.phases[approval.id] ?? .review
    }

    /// Picked once per sheet, like the other success screens
    @State private var successVideoName = ReactionVideoPair.random().thumbsUp

    private var amountSats: Int {
        Int(approval.decoded.amountSats ?? 0)
    }

    private var isPaid: Bool {
        if case .done(.paid, _) = phase { return true }
        return false
    }

    var body: some View {
        Group {
            if isPaid {
                successView
                    .transition(.opacity)
            } else {
                requestView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isPaid)
        .sensoryFeedback(.success, trigger: isPaid) { _, paid in paid }
        .presentationDetents([.large])
    }

    /// The request under review, while paying, and after a decline or failure.
    /// Deliberately plain so the attention stays on what's being approved.
    private var requestView: some View {
        VStack(spacing: 24) {
            header

            amountBlock(size: 40)

            details

            Spacer(minLength: 0)

            footer
        }
        .padding(24)
    }

    /// Thumbs-up video, as on the send and receive success screens
    private var successView: some View {
        VStack(spacing: 25) {
            // Top-aligned so the character's head survives the crop
            LoopingVideoPlayer_iOS.aspectFill(videoName: successVideoName, videoExtension: "mp4", alignment: .top)
                .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 340)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 15) {
                Text(String(localized: "status_payment_sent", defaultValue: "Payment Sent"))
                    .font(.system(size: 27, design: .serif))

                amountBlock(size: 32)

                if let description = approval.decoded.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 0)

            Button {
                service.dismissFinished(approval.id)
            } label: {
                Text(L10n.buttonDone)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.Arke.gold4)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.Arke.gold)
        }
        .padding(.bottom, 40)
    }

    private func amountBlock(size: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(BitcoinFormatter.shared.formatAmount(amountSats))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
            FiatAmountText(sats: amountSats)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.Arke.purple)
                .accessibilityHidden(true)
            Text(String(localized: "agent_payments_sheet_title", defaultValue: "\(approval.agent) wants to pay"))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if let macName = approval.macName {
                Text(String(localized: "agent_payments_sheet_via", defaultValue: "Requested on \(macName)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = approval.decoded.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "agent_payments_sheet_invoice_says", defaultValue: "Invoice description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.body)
                }
            }

            if !approval.reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "agent_payments_agent_says", defaultValue: "The agent says (unverified)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(approval.reason)
                        .font(.callout)
                        .italic()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .review:
            VStack(spacing: 12) {
                Button {
                    Task { await service.approve(approval.id) }
                } label: {
                    Label(String(localized: "agent_payments_approve", defaultValue: "Approve and pay"), systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .cancel) {
                    service.decline(approval.id)
                } label: {
                    Text(String(localized: "agent_payments_decline", defaultValue: "Decline"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

        case .paying:
            HStack(spacing: 10) {
                ProgressView()
                Text(String(localized: "agent_payments_paying", defaultValue: "Paying…"))
            }
            .frame(maxWidth: .infinity, minHeight: 50)

        case .done(let state, let message):
            VStack(spacing: 16) {
                outcome(state, message: message)
                Button {
                    service.dismissFinished(approval.id)
                } label: {
                    Text(String(localized: "agent_payments_done", defaultValue: "Done"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func outcome(_ state: AgentPaymentState, message: String?) -> some View {
        // Paid has its own screen (successView)
        switch state {
        case .expired:
            Label(String(localized: "agent_payments_expired", defaultValue: "Request expired"), systemImage: "clock.badge.xmark")
                .foregroundStyle(.secondary)
        default:
            VStack(spacing: 6) {
                Label(String(localized: "agent_payments_failed", defaultValue: "Payment failed"), systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

// MARK: - Settings row

/// "Agent payments" toggle for the Experimental settings section
struct AgentPaymentsSettingsToggle_iOS: View {
    @AppStorage(AgentPayments.enabledKey) private var isEnabled = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    private var service: AgentPaymentsPhoneService { .shared }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundColor(.Arke.purple)
                    .accessibilityHidden(true)
                    .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "agent_payments_setting", defaultValue: "Agent payments"))
                        .font(.body)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        guard isEnabled else {
            return String(localized: "agent_payments_setting_hint_phone", defaultValue: "Approve payments that AI agents request on your Mac")
        }
        switch service.linkStatus {
        case .off:
            return String(localized: "agent_payments_status_starting", defaultValue: "Starting…")
        case .noSeed:
            return String(localized: "agent_payments_status_no_seed_phone", defaultValue: "This device doesn't have the recovery phrase")
        case .searching:
            return String(localized: "agent_payments_status_searching", defaultValue: "Looking for your Mac — keep Arké open")
        case .connected(let name):
            return String(localized: "agent_payments_status_connected", defaultValue: "Connected: \(name)")
        case .failed(let reason):
            return reason
        }
    }
}
