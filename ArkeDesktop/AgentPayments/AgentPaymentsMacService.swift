//
//  AgentPaymentsMacService.swift
//  ArkeDesktop
//
//  The Mac side of agent payments (Docs/Features/Agent_Payments.md):
//  advertises the seed-keyed link the phone connects to, takes payment
//  requests from the loopback API, forwards them to the phone and tracks
//  their state until the phone reports an outcome.
//

import Foundation
import Network
import OSLog

/// One agent payment request as the Mac sees it
struct AgentPaymentRecord: Identifiable, Equatable {
    let id: UUID
    let invoice: String
    let reason: String
    let agent: String
    let amountSats: UInt64?
    let invoiceDescription: String?
    let createdAt: Date
    var state: AgentPaymentState
    var preimage: String?
    var paymentHash: String?
    var feeSats: UInt64?
    var error: String?
    var finishedAt: Date?
}

@MainActor
@Observable
final class AgentPaymentsMacService {
    static let shared = AgentPaymentsMacService()

    enum LinkStatus: Equatable {
        case off
        /// This Mac has no recovery phrase yet, so it can't derive the link key
        case noSeed
        case waitingForPhone
        case connected(name: String, role: String)
        case failed(String)
    }

    private(set) var linkStatus: LinkStatus = .off
    /// Oldest first
    private(set) var records: [AgentPaymentRecord] = []
    /// Records whose card the person closed (or that auto-hid after finishing)
    private(set) var dismissedIDs: Set<UUID> = []

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var link: AgentLinkConnection?
    @ObservationIgnored private var phoneHello: AgentLinkMessage?
    @ObservationIgnored private var loopback: AgentLoopbackServer?
    @ObservationIgnored private weak var walletManager: WalletManager?
    /// Long-poll waiters per request, keyed by a per-wait token so each
    /// continuation is resumed exactly once (by the outcome or its timeout)
    @ObservationIgnored private var waiters: [UUID: [UUID: CheckedContinuation<Void, Never>]] = [:]

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "AgentPayments")

    private init() {}

    /// The card to show: the newest request the person hasn't dismissed
    var visibleRecord: AgentPaymentRecord? {
        records.last { !dismissedIDs.contains($0.id) }
    }

    var phoneName: String? {
        if case .connected(let name, _) = linkStatus { return name }
        return nil
    }

    // MARK: - Lifecycle

    func start(walletManager: WalletManager) {
        guard !isRunning else { return }
        isRunning = true
        self.walletManager = walletManager

        startLoopback()

        // Seed-touching (read-only): derive the link key and drop the phrase
        let mnemonic = (try? ServiceContainer.shared.securityService.loadMnemonic()) ?? nil
        guard let mnemonic, !mnemonic.isEmpty else {
            Self.logger.warning("Agent payments: no recovery phrase on this Mac, link unavailable")
            linkStatus = .noSeed
            return
        }
        startListener(key: AgentLinkKey(mnemonic: mnemonic))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        listener?.cancel()
        listener = nil
        link?.cancel()
        link = nil
        phoneHello = nil
        loopback?.stop()
        loopback = nil
        linkStatus = .off

        // Nothing will report on open requests anymore
        for index in records.indices where !records[index].state.isTerminal {
            records[index].state = .expired
            records[index].error = AgentPaymentError.phoneNotConnected.rawValue
            records[index].finishedAt = Date()
        }
        for id in Array(waiters.keys) {
            resumeAllWaiters(for: id)
        }
    }

    func dismiss(_ id: UUID) {
        dismissedIDs.insert(id)
    }

    private func startLoopback() {
        let server = AgentLoopbackServer(service: self)
        do {
            try server.start()
            loopback = server
        } catch {
            Self.logger.error("Agent payments: loopback API failed to start: \(error.localizedDescription)")
        }
    }

    private func startListener(key: AgentLinkKey) {
        do {
            let listener = try NWListener(using: .agentLink(key: key))
            listener.service = NWListener.Service(name: key.serviceName, type: AgentPayments.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    self?.listenerStateChanged(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            linkStatus = .waitingForPhone
        } catch {
            Self.logger.error("Agent payments: link listener failed: \(error.localizedDescription)")
            linkStatus = .failed(error.localizedDescription)
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            Self.logger.info("Agent payments: advertising link")
        case .failed(let error):
            Self.logger.error("Agent payments: link listener failed: \(error.localizedDescription)")
            linkStatus = .failed(error.localizedDescription)
        default:
            break
        }
    }

    // MARK: - Link

    private func accept(_ connection: NWConnection) {
        // One phone at a time: a new connection replaces the old one
        link?.cancel()
        phoneHello = nil

        let link = AgentLinkConnection(connection: connection)
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
            link.send(ownHello())
        case .failed(let error):
            Self.logger.info("Agent payments: phone link failed: \(error.localizedDescription)")
            linkDropped()
        case .cancelled:
            linkDropped()
        default:
            break
        }
    }

    private func linkDropped() {
        link = nil
        phoneHello = nil
        if isRunning, listener != nil {
            linkStatus = .waitingForPhone
        }
    }

    private func ownHello() -> AgentLinkMessage {
        let deviceId = (try? ServiceContainer.shared.deviceRegistrationService.getOrCreateDeviceId()) ?? "unknown"
        return .hello(
            deviceId: deviceId,
            deviceName: Host.current().localizedName ?? "Mac",
            role: walletManager?.isReadOnlyMode == false ? "primary" : "secondary",
            network: walletManager?.networkConfig?.networkType ?? "unknown"
        )
    }

    private func handle(_ message: AgentLinkMessage) {
        switch message.type {
        case .hello:
            receivedHello(message)
        case .payStatus:
            receivedStatus(message)
        case .payRequest, .cancel:
            // Only the Mac sends these
            break
        }
    }

    private func receivedHello(_ hello: AgentLinkMessage) {
        let ownNetwork = walletManager?.networkConfig?.networkType
        if hello.network == "mainnet" ||
            (ownNetwork != nil && hello.network != nil && hello.network != "unknown" && ownNetwork != hello.network) {
            Self.logger.warning("Agent payments: dropping link, network mismatch or mainnet")
            link?.cancel()
            linkDropped()
            return
        }

        phoneHello = hello
        linkStatus = .connected(name: hello.deviceName ?? "iPhone", role: hello.role ?? "unknown")

        // Re-send whatever is still open; the phone answers duplicates from
        // its stored outcome instead of asking again (at-most-once rule)
        for record in records where !record.state.isTerminal {
            link?.send(payRequestMessage(for: record))
        }
    }

    private func receivedStatus(_ status: AgentLinkMessage) {
        guard let id = status.id,
              let state = status.state,
              let index = records.firstIndex(where: { $0.id == id }) else { return }
        // A finished request stays finished
        guard !records[index].state.isTerminal else { return }

        records[index].state = state
        records[index].preimage = status.preimage ?? records[index].preimage
        records[index].paymentHash = status.paymentHash ?? records[index].paymentHash
        records[index].feeSats = status.feeSats ?? records[index].feeSats
        records[index].error = status.error

        if state.isTerminal {
            finish(index: index)
        }
    }

    private func finish(index: Int) {
        let id = records[index].id
        records[index].finishedAt = Date()
        resumeAllWaiters(for: id)

        // Leave the outcome on screen for a moment, then hide the card
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.dismissedIDs.insert(id)
        }
    }

    private func payRequestMessage(for record: AgentPaymentRecord) -> AgentLinkMessage {
        var message = AgentLinkMessage(type: .payRequest)
        message.id = record.id
        message.invoice = record.invoice
        message.reason = record.reason
        message.agent = record.agent
        message.createdAt = record.createdAt
        return message
    }

    // MARK: - Requests (called by the loopback API)

    func submit(invoice: String, reason: String, agent: String) -> Result<AgentPaymentRecord, AgentPaymentError> {
        if linkStatus == .noSeed {
            return .failure(.linkUnavailable)
        }
        guard let decoded = AgentInvoice.decode(invoice) else {
            return .failure(.invalidInvoice)
        }
        if decoded.network == .mainnet {
            return .failure(.mainnetRefused)
        }
        guard let link, phoneHello != nil else {
            return .failure(.phoneNotConnected)
        }

        let record = AgentPaymentRecord(
            id: UUID(),
            invoice: invoice.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: reason,
            agent: agent,
            amountSats: decoded.amountSats,
            invoiceDescription: decoded.description,
            createdAt: Date(),
            state: .received
        )
        records.append(record)
        link.send(payRequestMessage(for: record))
        Self.logger.info("Agent payments: forwarded request \(record.id.uuidString) to the phone")

        // Give up eventually so the agent isn't left waiting forever
        let id = record.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(AgentPayments.requestTimeout))
            self?.expireIfOpen(id)
        }
        return .success(record)
    }

    func record(_ id: UUID) -> AgentPaymentRecord? {
        records.first { $0.id == id }
    }

    /// Returns once the request is finished, or after `timeout` seconds
    func waitUntilFinished(_ id: UUID, timeout: TimeInterval) async {
        guard let record = record(id), !record.state.isTerminal else { return }
        let token = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[id, default: [:]][token] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resumeWaiter(for: id, token: token)
            }
        }
    }

    private func expireIfOpen(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              !records[index].state.isTerminal else { return }
        var cancel = AgentLinkMessage(type: .cancel)
        cancel.id = id
        link?.send(cancel)
        records[index].state = .expired
        records[index].error = "timed_out"
        finish(index: index)
    }

    private func resumeWaiter(for id: UUID, token: UUID) {
        waiters[id]?.removeValue(forKey: token)?.resume()
    }

    private func resumeAllWaiters(for id: UUID) {
        guard let pending = waiters.removeValue(forKey: id) else { return }
        for continuation in pending.values {
            continuation.resume()
        }
    }
}
