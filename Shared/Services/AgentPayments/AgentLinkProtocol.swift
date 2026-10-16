//
//  AgentLinkProtocol.swift
//  Arké
//
//  Agent payments (Docs/Features/Agent_Payments.md): an agent asks the Mac
//  to pay an invoice, the Mac forwards it over a local link to the phone,
//  the phone pays after approval. This file holds what both ends share:
//  constants, the wire format, the seed-derived link key and the
//  TLS-PSK connection parameters.
//

import Foundation
import CryptoKit
import Network
import Security
import BIP39

nonisolated enum AgentPayments {
    /// UserDefaults key for the "Agent payments (experimental)" toggle. Off by default.
    static let enabledKey = "agentPaymentsEnabled"

    /// Bonjour service type the Mac advertises and the phone browses for.
    /// Must also be listed under NSBonjourServices in the phone's Info.plist.
    static let serviceType = "_arkeagent._tcp"

    /// Hard demo cap: the phone refuses anything above this before showing the sheet.
    static let demoCapSats: UInt64 = 15_000

    /// Port of the Mac's loopback API (127.0.0.1 only), used by Tools/agent-mcp.
    static let loopbackPort: UInt16 = 48_211

    /// The Mac gives up on a request the phone hasn't finished after this long.
    static let requestTimeout: TimeInterval = 5 * 60

    static let protocolVersion = 1
}

// MARK: - States and errors

nonisolated enum AgentPaymentState: String, Codable, Sendable {
    case received
    case awaitingApproval = "awaiting_approval"
    case paying
    case paid
    /// The person said no on the phone
    case declined
    /// An automatic check on the phone failed; `error` says which
    case refused
    case failed
    case expired

    var isTerminal: Bool {
        switch self {
        case .paid, .declined, .refused, .failed, .expired: return true
        case .received, .awaitingApproval, .paying: return false
        }
    }
}

/// Machine-readable error codes. They travel in `pay_status.error` and in
/// loopback API responses, so the MCP script can hand Claude a plain reason.
nonisolated enum AgentPaymentError: String, Codable, Sendable, Error {
    case phoneNotConnected = "phone_not_connected"
    case linkUnavailable = "link_unavailable"
    case mainnetRefused = "mainnet_refused"
    case invalidInvoice = "invalid_invoice"
    case noAmount = "no_amount"
    case invoiceExpired = "invoice_expired"
    case networkMismatch = "network_mismatch"
    case overCap = "over_cap"
    case notPrimary = "not_primary"
    case walletNotReady = "wallet_not_ready"
    case notFound = "not_found"

    /// Plain explanation for the agent (and for the Mac's card)
    var message: String {
        switch self {
        case .phoneNotConnected: return "The phone isn't connected. Open Arké on the phone with Agent payments turned on."
        case .linkUnavailable: return "This Mac doesn't have the wallet's recovery phrase yet, so it can't connect to the phone."
        case .mainnetRefused: return "Agent payments only work on signet; mainnet is refused."
        case .invalidInvoice: return "That isn't a valid BOLT11 Lightning invoice."
        case .noAmount: return "The invoice has no amount; zero-amount invoices aren't accepted."
        case .invoiceExpired: return "The invoice has expired. Ask the merchant for a new one."
        case .networkMismatch: return "The invoice is for a different network than the wallet."
        case .overCap: return "The amount is over the \(AgentPayments.demoCapSats)-sat limit set on the phone."
        case .notPrimary: return "The phone isn't the wallet's primary device, so it can't pay."
        case .walletNotReady: return "The phone's wallet isn't open yet. Try again in a moment."
        case .notFound: return "No payment request with that id."
        }
    }
}

// MARK: - Wire format

/// One newline-delimited JSON message on the link. A single flat shape keeps
/// the coding trivial; each `type` uses a subset of the optional fields
/// (see the table in Agent_Payments.md §5).
nonisolated struct AgentLinkMessage: Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case hello
        case payRequest = "pay_request"
        case payStatus = "pay_status"
        case cancel
    }

    var type: Kind
    var v: Int = AgentPayments.protocolVersion

    // hello
    var deviceId: String?
    var deviceName: String?
    var role: String?
    var network: String?
    var appVersion: String?

    // pay_request / pay_status / cancel
    var id: UUID?
    var invoice: String?
    var reason: String?
    var agent: String?
    var createdAt: Date?
    var state: AgentPaymentState?
    var preimage: String?
    var paymentHash: String?
    var feeSats: UInt64?
    var error: String?

    static func hello(deviceId: String, deviceName: String, role: String, network: String) -> AgentLinkMessage {
        var message = AgentLinkMessage(type: .hello)
        message.deviceId = deviceId
        message.deviceName = deviceName
        message.role = role
        message.network = network
        message.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return message
    }

    static func status(_ id: UUID, _ state: AgentPaymentState, error: AgentPaymentError? = nil, errorText: String? = nil) -> AgentLinkMessage {
        var message = AgentLinkMessage(type: .payStatus)
        message.id = id
        message.state = state
        message.error = error?.rawValue ?? errorText
        return message
    }
}

nonisolated enum AgentLinkCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

// MARK: - Link key

/// Key material both devices derive independently from the seed they already
/// share through iCloud Keychain, so no pairing step is needed.
///
/// Seed-touching (read-only): callers pass the mnemonic in and drop it right
/// after. The derived values live in memory only; never log or persist them.
nonisolated struct AgentLinkKey: Sendable {
    /// TLS pre-shared key
    let psk: SymmetricKey
    /// Bonjour instance name, so the phone only sees Macs on the same wallet.
    /// Derived with a separate HKDF label; reveals nothing about the PSK.
    let serviceName: String

    init(mnemonic: String) {
        // Normalize spacing and case so both devices hash identical bytes
        let normalized = mnemonic
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let seed = SeedDerivator().seed(mnemonic: normalized)
        let inputKey = SymmetricKey(data: seed)

        psk = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            info: Data("arke-agent-link-v1".utf8),
            outputByteCount: 32
        )

        let discovery = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            info: Data("arke-agent-discovery-v1".utf8),
            outputByteCount: 4
        )
        let tag = discovery.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
        serviceName = "arke-\(tag)"
    }
}

// MARK: - Connection parameters

extension NWParameters {
    /// TCP + TLS with the seed-derived PSK, over peer-to-peer Wi-Fi as well as
    /// infrastructure networks. Same setup as Apple's "Building a custom
    /// peer-to-peer protocol" sample. A device with a different seed fails
    /// the handshake.
    nonisolated static func agentLink(key: AgentLinkKey) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        let pskData = key.psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data("arke-agent-link".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            pskData as __DispatchData,
            identityData as __DispatchData
        )
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions, suite)
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        return parameters
    }
}

// MARK: - Message connection

/// Wraps an NWConnection carrying newline-delimited `AgentLinkMessage`s.
/// All callbacks run on the main queue.
final class AgentLinkConnection {
    let connection: NWConnection
    var onMessage: ((AgentLinkMessage) -> Void)?
    var onStateChange: ((NWConnection.State) -> Void)?

    private var buffer = Data()
    private static let maxBufferedBytes = 1_000_000

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.onStateChange?(state)
            }
        }
        connection.start(queue: .main)
        receiveNext()
    }

    func send(_ message: AgentLinkMessage) {
        guard var data = try? AgentLinkCoding.encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let content {
                    self.consume(content)
                }
                if isComplete || error != nil {
                    self.connection.cancel()
                    return
                }
                self.receiveNext()
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let message = try? AgentLinkCoding.decode(AgentLinkMessage.self, from: line) {
                onMessage?(message)
            }
        }
        if buffer.count > Self.maxBufferedBytes {
            connection.cancel()
        }
    }
}
