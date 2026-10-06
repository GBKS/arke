//
//  AgentPaymentsPhoneService.swift
//  ArkeMobile
//
//  The phone side of agent payments (Docs/Features/Agent_Payments.md):
//  finds the Mac on the seed-keyed local link, runs the automatic checks on
//  each request (§7), asks the person to approve, pays, and reports the
//  outcome back. Each request id is paid at most once.
//

import Foundation
import Network
import SwiftData
import LocalAuthentication
import UIKit
import OSLog
import Bark

/// A request waiting on (or shown in) the approval sheet
struct AgentPaymentApproval: Identifiable, Equatable {
    let id: UUID
    let invoice: String
    let decoded: AgentInvoice
    let reason: String
    let agent: String
    let macName: String?
}

@MainActor
@Observable
final class AgentPaymentsPhoneService {
    static let shared = AgentPaymentsPhoneService()

    enum LinkStatus: Equatable {
        case off
        /// No recovery phrase on this device, so it can't derive the link key
        case noSeed
        case searching
        case connected(name: String)
        case failed(String)
    }

    enum Phase: Equatable {
        case review
        case paying
        case done(AgentPaymentState, message: String?)
    }

    private(set) var linkStatus: LinkStatus = .off
    /// Requests waiting for the person, oldest first. The sheet shows the first.
    private(set) var approvals: [AgentPaymentApproval] = []
    private(set) var phases: [UUID: Phase] = [:]

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var key: AgentLinkKey?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var latestResults: Set<NWBrowser.Result> = []
    @ObservationIgnored private var link: AgentLinkConnection?
    @ObservationIgnored private var macName: String?
    @ObservationIgnored private weak var walletManager: WalletManager?
    /// Final pay_status per request, re-sent when the Mac asks again
    @ObservationIgnored private var outcomes: [UUID: AgentLinkMessage] = [:]
    /// Requests currently being checked, so a duplicate can't slip in meanwhile
    @ObservationIgnored private var checking: Set<UUID> = []

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "AgentPayments")

    private init() {}

    var currentApproval: AgentPaymentApproval? { approvals.first }

    // MARK: - Lifecycle

    func start(walletManager: WalletManager) {
        guard !isRunning else { return }
        isRunning = true
        self.walletManager = walletManager

        // Seed-touching (read-only): derive the link key and drop the phrase
        let mnemonic = (try? ServiceContainer.shared.securityService.loadMnemonic()) ?? nil
        guard let mnemonic, !mnemonic.isEmpty else {
            Self.logger.warning("Agent payments: no recovery phrase on this device, link unavailable")
            linkStatus = .noSeed
            return
        }
        key = AgentLinkKey(mnemonic: mnemonic)

        // A locked screen suspends the app and drops the link (§4.4)
        UIApplication.shared.isIdleTimerDisabled = true
        startBrowser()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        browser?.cancel()
        browser = nil
        link?.cancel()
        link = nil
        key = nil
        latestResults = []
        linkStatus = .off

        // Requests nobody approved yet won't be answered anymore
        for approval in approvals where phases[approval.id] == .review {
            phases[approval.id] = .done(.expired, message: nil)
        }
        approvals.removeAll { phases[$0.id] != .paying }
    }

    /// Called when the app comes back to the foreground
    func reconnectIfNeeded() {
        guard isRunning, key != nil, link == nil else { return }
        browser?.cancel()
        browser = nil
        startBrowser()
    }

    // MARK: - Discovery and connection

    private func startBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: AgentPayments.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.latestResults = results
                self?.connectIfPossible()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.browserStateChanged(state)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        linkStatus = .searching
    }

    private func browserStateChanged(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            Self.logger.error("Agent payments: browser failed: \(error.localizedDescription)")
            linkStatus = .failed(error.localizedDescription)
            browser?.cancel()
            browser = nil
            retry(after: 3) { $0.startBrowser() }
        case .waiting(let error):
            // Usually the local network permission hasn't been granted yet
            Self.logger.info("Agent payments: browser waiting: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func connectIfPossible() {
        guard isRunning, link == nil, let key else { return }
        let match = latestResults.first { result in
            if case .service(let name, _, _, _) = result.endpoint {
                return name == key.serviceName
            }
            return false
        }
        guard let match else { return }

        let link = AgentLinkConnection(connection: NWConnection(to: match.endpoint, using: .agentLink(key: key)))
        link.onStateChange = { [weak self, weak link] state in
            guard let self, let link else { return }
            self.linkStateChanged(state, for: link)
        }
        link.onMessage = { [weak self] message in
            self?.handle(message)
        }
        self.link = link
        link.start()
    }

    private func linkStateChanged(_ state: NWConnection.State, for link: AgentLinkConnection) {
        guard link === self.link else { return }
        switch state {
        case .ready:
            Self.logger.info("Agent payments: connected to the Mac")
            Task { await sendHello() }
        case .failed(let error):
            Self.logger.info("Agent payments: link failed: \(error.localizedDescription)")
            linkDropped()
        case .cancelled:
            linkDropped()
        default:
            break
        }
    }

    private func linkDropped() {
        link?.cancel()
        link = nil
        macName = nil
        guard isRunning else { return }
        linkStatus = .searching
        retry(after: 2) { $0.connectIfPossible() }
    }

    private func retry(after seconds: Double, _ action: @escaping (AgentPaymentsPhoneService) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.isRunning else { return }
            action(self)
        }
    }

    private func sendHello() async {
        let device = try? await ServiceContainer.shared.deviceRegistrationService.getCurrentDevice()
        let deviceId = (try? ServiceContainer.shared.deviceRegistrationService.getOrCreateDeviceId()) ?? "unknown"
        let name = device?.deviceName.isEmpty == false ? device?.deviceName : nil
        link?.send(.hello(
            deviceId: deviceId,
            deviceName: name ?? UIDevice.current.name,
            role: await isPrimary() ? "primary" : "secondary",
            network: walletManager?.networkConfig?.networkType ?? "unknown"
        ))
    }

    // MARK: - Messages

    private func handle(_ message: AgentLinkMessage) {
        switch message.type {
        case .hello:
            macName = message.deviceName
            linkStatus = .connected(name: message.deviceName ?? "Mac")
        case .payRequest:
            receivedRequest(message)
        case .cancel:
            if let id = message.id {
                cancelled(id)
            }
        case .payStatus:
            // Only the phone sends these
            break
        }
    }

    private func receivedRequest(_ message: AgentLinkMessage) {
        guard let id = message.id, let invoice = message.invoice else { return }

        // At-most-once: answer duplicates from what already happened
        if let outcome = outcomes[id] {
            link?.send(outcome)
            return
        }
        switch phases[id] {
        case .review:
            link?.send(.status(id, .awaitingApproval))
            return
        case .paying:
            link?.send(.status(id, .paying))
            return
        case .done, nil:
            break
        }
        guard !checking.contains(id) else { return }
        checking.insert(id)
        link?.send(.status(id, .received))

        Task {
            defer { checking.remove(id) }
            switch await check(invoice: invoice) {
            case .failure(let error):
                Self.logger.info("Agent payments: refused request \(id.uuidString): \(error.rawValue)")
                report(.status(id, .refused, error: error))
            case .success(let decoded):
                approvals.append(AgentPaymentApproval(
                    id: id,
                    invoice: invoice,
                    decoded: decoded,
                    reason: message.reason ?? "",
                    agent: message.agent ?? "Agent",
                    macName: macName
                ))
                phases[id] = .review
                link?.send(.status(id, .awaitingApproval))
            }
        }
    }

    private func cancelled(_ id: UUID) {
        guard phases[id] == .review else { return }
        approvals.removeAll { $0.id == id }
        phases[id] = .done(.expired, message: nil)
        report(.status(id, .expired, errorText: "cancelled"))
    }

    /// Sends a status and, if it's final, keeps it for duplicate requests
    private func report(_ status: AgentLinkMessage) {
        if let id = status.id, status.state?.isTerminal == true {
            outcomes[id] = status
        }
        link?.send(status)
    }

    // MARK: - Checks (§7)

    private func isPrimary() async -> Bool {
        guard let walletManager, !walletManager.isReadOnlyMode else { return false }
        if let device = try? await ServiceContainer.shared.deviceRegistrationService.getCurrentDevice() {
            return device.isPrimaryDevice
        }
        return true
    }

    private func check(invoice: String) async -> Result<AgentInvoice, AgentPaymentError> {
        guard let walletManager, walletManager.isInitialized, walletManager.wallet != nil,
              let config = walletManager.networkConfig else {
            return .failure(.walletNotReady)
        }
        guard await isPrimary() else {
            return .failure(.notPrimary)
        }
        // Hard check in code, not a setting
        guard !walletManager.isMainnet, !config.isMainnet, config.networkType != "mainnet" else {
            return .failure(.mainnetRefused)
        }
        guard let decoded = AgentInvoice.decode(invoice) else {
            return .failure(.invalidInvoice)
        }
        if decoded.network == .mainnet {
            return .failure(.mainnetRefused)
        }
        switch config.networkType {
        case "signet" where decoded.network != .signet,
             "testnet" where decoded.network != .testnet:
            return .failure(.networkMismatch)
        default:
            break
        }
        guard let amount = decoded.amountSats, amount > 0 else {
            return .failure(.noAmount)
        }
        if decoded.isExpired() {
            return .failure(.invoiceExpired)
        }
        if amount > AgentPayments.demoCapSats {
            return .failure(.overCap)
        }
        return .success(decoded)
    }

    // MARK: - Approval

    func decline(_ id: UUID) {
        guard phases[id] == .review else { return }
        approvals.removeAll { $0.id == id }
        phases[id] = .done(.declined, message: nil)
        report(.status(id, .declined))
    }

    /// Removes a finished request from the sheet
    func dismissFinished(_ id: UUID) {
        guard case .done = phases[id] else { return }
        approvals.removeAll { $0.id == id }
    }

    func approve(_ id: UUID) async {
        guard phases[id] == .review,
              let approval = approvals.first(where: { $0.id == id }),
              let walletManager else { return }

        guard await authenticate() else { return }
        // The Mac may have cancelled while Face ID was up
        guard phases[id] == .review else { return }

        phases[id] = .paying
        link?.send(.status(id, .paying))

        let pendingMetadata = createPendingMetadata(for: approval)

        let state: AgentPaymentState
        var status: AgentLinkMessage
        do {
            let result = try await walletManager.payLightningInvoice(invoice: approval.invoice, amountSats: nil)
            switch await settle(result, paymentHash: approval.decoded.paymentHash) {
            case .paid(let paymentHash, let preimage):
                state = .paid
                status = .status(id, .paid)
                status.paymentHash = paymentHash
                status.preimage = preimage
                updatePendingMetadata(pendingMetadata, paymentHash: paymentHash)
            case .inProgress:
                state = .failed
                status = .status(id, .failed, errorText: "The payment is still in flight. Check the wallet's activity.")
            case .unknown:
                state = .failed
                status = .status(id, .failed, errorText: "The wallet has no record of this payment.")
            }
        } catch {
            Self.logger.error("Agent payments: payment failed: \(error.localizedDescription)")
            state = .failed
            status = .status(id, .failed, errorText: error.localizedDescription)
        }

        phases[id] = .done(state, message: status.error)
        report(status)
    }

    // MARK: - Activity note

    /// Records the invoice description as the payment's note, the same way the
    /// send screen does (Send_Metadata.md): bark returns no transaction id, so
    /// a PendingPaymentMetadata row waits until the movement sync upserts the
    /// transaction, then TransactionService copies the note over. Unlike the
    /// send screen, the payment hash is known up front from the invoice, so the
    /// exact hash match applies. Rows that never match (a failed payment) are
    /// removed by the existing 24 h cleanup.
    private func createPendingMetadata(for approval: AgentPaymentApproval) -> PendingPaymentMetadata? {
        guard let context = walletManager?.modelContext else { return nil }
        let metadata = PendingPaymentMetadata(
            paymentHash: approval.decoded.paymentHash,
            destinationAddress: approval.invoice,
            amountSats: approval.decoded.amountSats.map { Int($0) },
            paymentType: "lightning"
        )
        if let description = approval.decoded.description, !description.isEmpty {
            metadata.notes = description
        }
        context.insert(metadata)
        do {
            try context.save()
        } catch {
            Self.logger.error("Agent payments: couldn't save pending metadata: \(error.localizedDescription)")
        }
        return metadata
    }

    /// Prefer bark's own hash string for matching, as the send screen does
    private func updatePendingMetadata(_ metadata: PendingPaymentMetadata?, paymentHash: String) {
        guard let metadata, metadata.paymentHash != paymentHash,
              let context = walletManager?.modelContext else { return }
        metadata.paymentHash = paymentHash
        try? context.save()
    }

    /// `payLightningInvoice` waits for settlement but can still come back
    /// in progress; poll the send state for a while before giving up.
    private func settle(_ status: LightningSendStatus, paymentHash: String?) async -> LightningSendStatus {
        guard case .inProgress = status, let paymentHash, let wallet = walletManager?.wallet else { return status }
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(2))
            if let latest = try? await wallet.lightningSendState(paymentHash: paymentHash) {
                if case .inProgress = latest { continue }
                return latest
            }
        }
        return status
    }

    /// Face ID, Touch ID or the passcode. A device with no passcode has
    /// nothing to check, so the tap on Approve is the confirmation.
    private func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "agent_payments_auth_reason", defaultValue: "Approve the agent's payment")
            )
        } catch {
            return false
        }
    }
}
