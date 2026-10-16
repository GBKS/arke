//
//  AgentLoopbackServer.swift
//  ArkeDesktop
//
//  A tiny JSON-over-HTTP API on 127.0.0.1 for Tools/agent-mcp
//  (Agent_Payments.md §6.2). Loopback only, and every request must carry
//  the `X-Arke-Agent` header: a custom header forces a CORS preflight, which
//  this server never answers, so web pages in a browser can't submit requests.
//
//    GET  /agent/status
//    POST /agent/payments            {"invoice": "...", "reason": "...", "agent": "..."}
//    GET  /agent/payments/{id}?wait=45
//

import Foundation
import Network
import OSLog

final class AgentLoopbackServer {
    private let service: AgentPaymentsMacService
    private var listener: NWListener?

    private static let maxRequestBytes = 256_000
    private static let maxWaitSeconds: TimeInterval = 120
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "AgentPayments")

    init(service: AgentPaymentsMacService) {
        self.service = service
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: AgentPayments.loopbackPort) else { return }
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Self.logger.error("Agent payments: loopback API failed: \(error.localizedDescription)")
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let content {
                    buffer.append(content)
                }
                if let request = HTTPRequest(parsing: buffer) {
                    Task { await self.respond(to: request, on: connection) }
                    return
                }
                if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
                    connection.cancel()
                    return
                }
                self.read(connection, buffer: buffer)
            }
        }
    }

    // MARK: - Routing

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        guard request.headers["x-arke-agent"] != nil else {
            send(connection, status: 403, json: ["error": "forbidden", "message": "Missing X-Arke-Agent header."])
            return
        }

        let parts = request.path.split(separator: "/").map(String.init)

        switch (request.method, parts) {
        case ("GET", ["agent", "status"]):
            send(connection, status: 200, json: statusJSON())

        case ("POST", ["agent", "payments"]):
            submit(request, on: connection)

        case ("GET", let parts) where parts.count == 3 && parts[0] == "agent" && parts[1] == "payments":
            guard let id = UUID(uuidString: parts[2]) else {
                sendError(connection, .notFound)
                return
            }
            let wait = min(TimeInterval(request.query["wait"] ?? "") ?? 0, Self.maxWaitSeconds)
            if wait > 0 {
                await service.waitUntilFinished(id, timeout: wait)
            }
            guard let record = service.record(id) else {
                sendError(connection, .notFound)
                return
            }
            send(connection, status: 200, json: Self.json(for: record))

        default:
            send(connection, status: 404, json: ["error": "not_found", "message": "Unknown endpoint."])
        }
    }

    private func submit(_ request: HTTPRequest, on connection: NWConnection) {
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let invoice = object["invoice"] as? String else {
            sendError(connection, .invalidInvoice)
            return
        }
        let reason = (object["reason"] as? String) ?? ""
        let agent = (object["agent"] as? String) ?? "Agent"

        switch service.submit(invoice: invoice, reason: String(reason.prefix(500)), agent: String(agent.prefix(60))) {
        case .success(let record):
            send(connection, status: 200, json: Self.json(for: record))
        case .failure(let error):
            sendError(connection, error)
        }
    }

    private func statusJSON() -> [String: Any] {
        switch service.linkStatus {
        case .off:
            return ["link": "off"]
        case .noSeed:
            return ["link": "unavailable", "message": AgentPaymentError.linkUnavailable.message]
        case .waitingForPhone:
            return ["link": "waiting_for_phone", "message": AgentPaymentError.phoneNotConnected.message]
        case .connected(let name, let role):
            return ["link": "connected", "phone": name, "role": role]
        case .failed(let reason):
            return ["link": "failed", "message": reason]
        }
    }

    static func json(for record: AgentPaymentRecord) -> [String: Any] {
        var json: [String: Any] = [
            "id": record.id.uuidString,
            "state": record.state.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: record.createdAt),
        ]
        if let amount = record.amountSats { json["amountSats"] = amount }
        if let description = record.invoiceDescription { json["description"] = description }
        if let preimage = record.preimage { json["preimage"] = preimage }
        if let hash = record.paymentHash { json["paymentHash"] = hash }
        if let fee = record.feeSats { json["feeSats"] = fee }
        if let error = record.error {
            json["error"] = error
            json["message"] = AgentPaymentError(rawValue: error)?.message ?? error
        }
        return json
    }

    // MARK: - Responses

    private func sendError(_ connection: NWConnection, _ error: AgentPaymentError) {
        let status: Int
        switch error {
        case .phoneNotConnected, .linkUnavailable: status = 503
        case .notFound: status = 404
        default: status = 400
        }
        send(connection, status: status, json: ["error": error.rawValue, "message": error.message])
    }

    private func send(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - HTTP parsing

/// Just enough HTTP/1.1 for a local JSON API: request line, headers, and a
/// Content-Length body. Returns nil until the whole request has arrived.
private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    init?(parsing data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }

        let target = URLComponents(string: requestLine[1])
        var query: [String: String] = [:]
        for item in target?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        self.method = requestLine[0].uppercased()
        self.path = target?.path ?? requestLine[1]
        self.query = query
        self.headers = headers
        self.body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])
    }
}
