//
//  RelayRegistrationService.swift
//  Arké
//
//  Service for registering devices with the APNs mailbox relay
//

import Foundation
import CryptoKit
import OSLog

// MARK: - Request/Response Types

struct RelayRegisterRequest: Codable {
    let mailbox_id: String
    let authorization_hex: String
    let ark_addr: String
    let device_token: String
    let apns_topic: String
    let trigger: String?
}

/// What prompted a registration. Sent to the relay (optional `trigger` field
/// on POST /v1/register) so refresh-path frequencies can be counted
/// server-side instead of from device logs (SWIFT_AUTH_WAKE_SPEC.md).
enum RelayRegistrationTrigger: String, Sendable {
    /// App launch / foreground refresh
    case foreground
    /// The in-process expiry timer (`onNeedsRefresh`)
    case timer
    /// `BGAppRefreshTask` handler
    case backgroundTask = "background_task"
    /// Handling a `mailbox_auth_refresh` wake push
    case wakePush = "wake_push"
    /// APNs device token changed
    case tokenChange = "token_change"
}

struct RelayUnregisterRequest: Codable {
    let mailbox_id: String
    let device_token: String
}

struct RelayRegisterResponse: Codable {
    let status: String
    /// Expiry of the registered authorization (UNIX seconds), read out of the
    /// token by the relay; null/absent on older relay versions. Double so a
    /// fractional-seconds value can't fail the decode of a successful
    /// registration.
    let authorization_expires_at: Double?
}

struct RelayUnregisterResponse: Codable {
    let status: String
}

struct RelayErrorResponse: Codable {
    let error: String
    let retry_after_seconds: Int?
}

// MARK: - Service

@MainActor
class RelayRegistrationService {
    // MARK: - Logging

    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "RelayRegistration")

    // MARK: - Configuration
    
    private let relayBaseURL: String
    private let relayAPIToken: String?
    
    // MARK: - State
    
    /// Last authorization hash sent to relay (to avoid redundant re-registrations)
    private var lastAuthHash: String?
    
    /// Timestamp when authorization expires
    private var authExpiresAt: Date?

    /// When the last successful registration happened, and with which APNs
    /// device token - drives the launch-time freshness dedupe (see
    /// `isRegistrationFresh(currentDeviceToken:)`)
    private var lastRegisteredAt: Date?
    private var lastRegisteredDeviceToken: String?

    /// A registration younger than this is "fresh": re-minting would be pure
    /// churn (each mint produces a new token, so the hash dedupe can't catch
    /// launch double-fires)
    private let freshRegistrationWindow: TimeInterval = 60 * 60

    /// TTL for authorization token. Matches the expiry `bark-ffi`'s
    /// `mailbox_authorization()` bakes in (see bark-ffi/src/core/wallet.rs)
    /// so our local bookkeeping doesn't drift from the real token lifetime.
    private let authTTL: TimeInterval = 24 * 60 * 60

    /// Refresh authorization this many seconds before expiry (default 1 hour)
    private let authRefreshBuffer: TimeInterval = 60 * 60

    /// Timer for scheduled authorization refresh
    private var refreshTimer: Task<Void, Never>?

    /// Expiry of the authorization the relay currently holds, as far as this
    /// session knows; nil until a successful registration. Read-only exposure
    /// for the X-Ray background activity header.
    var authorizationExpiresAt: Date? {
        authExpiresAt
    }

    /// Whether the current registration is fresh enough that re-minting would
    /// be pure churn. The launch flow and the APNs token observer both
    /// register within seconds at every launch (journal finding, 2026-09-18);
    /// each mints a brand-new token, so the hash dedupe never catches it.
    /// A changed device token always defeats freshness - the relay must learn
    /// new tokens immediately. `forceRefresh()` clears freshness, so the
    /// timer, BGTask, and wake-push paths always re-register.
    func isRegistrationFresh(currentDeviceToken: String?) -> Bool {
        Self.isRegistrationFresh(
            registeredAt: lastRegisteredAt,
            expiresAt: authExpiresAt,
            registeredDeviceToken: lastRegisteredDeviceToken,
            currentDeviceToken: currentDeviceToken,
            now: Date(),
            window: freshRegistrationWindow
        )
    }

    /// Pure freshness decision, extracted for unit tests.
    nonisolated static func isRegistrationFresh(
        registeredAt: Date?,
        expiresAt: Date?,
        registeredDeviceToken: String?,
        currentDeviceToken: String?,
        now: Date,
        window: TimeInterval
    ) -> Bool {
        guard let registeredAt, let expiresAt,
              let currentDeviceToken, currentDeviceToken == registeredDeviceToken else {
            return false
        }
        return now.timeIntervalSince(registeredAt) < window && now < expiresAt
    }

    /// When the next in-process (foreground) auth refresh should run (expiry
    /// minus buffer); nil until a successful registration. This and the BGTask
    /// date (`backgroundRefreshDate`) both derive from the same
    /// `authExpiresAt`, so the paths can't drift if the TTL policy changes.
    var nextRefreshDate: Date? {
        authExpiresAt?.addingTimeInterval(-authRefreshBuffer)
    }

    /// When the BGTask fallback should ask to run: the midpoint of the token's
    /// remaining life, not expiry minus the tight foreground buffer.
    /// `earliestBeginDate` is advisory — iOS routinely runs the task hours
    /// late, and field data (SWIFT_AUTH_WAKE_SPEC.md) showed it usually misses
    /// a 1h window before a 24h expiry. Costs about one extra registration per
    /// day; the foreground timer keeps the tight buffer.
    var backgroundRefreshDate: Date? {
        guard let authExpiresAt else { return nil }
        return Date().addingTimeInterval(authExpiresAt.timeIntervalSinceNow / 2)
    }

    /// Called shortly before the current authorization expires so the caller
    /// can mint a fresh one (via the wallet) and re-register. Without this,
    /// a registered mailbox goes silently stale once its token expires and
    /// is never renewed until something else happens to re-register it.
    var onNeedsRefresh: (() async -> Void)?

    // MARK: - Initialization

    init(relayBaseURL: String = "https://relay.arke.cash", relayAPIToken: String? = nil) {
        self.relayBaseURL = relayBaseURL
        self.relayAPIToken = relayAPIToken
    }
    
    deinit {
        refreshTimer?.cancel()
    }
    
    // MARK: - Public API
    
    /// Registers device with the relay
    /// - Parameters:
    ///   - mailboxId: Hex-encoded mailbox identifier
    ///   - authorizationHex: Mailbox authorization token (24h expiry, see bark-ffi)
    ///   - arkAddr: Ark server URL
    ///   - deviceToken: APNs device token (64-char hex)
    ///   - apnsTopic: App bundle identifier
    ///   - trigger: What prompted this registration (relay-side counting)
    func registerDevice(
        mailboxId: String,
        authorizationHex: String,
        arkAddr: String,
        deviceToken: String,
        apnsTopic: String,
        trigger: RelayRegistrationTrigger
    ) async throws {
        // Check if we need to re-register based on auth hash
        let authHash = hashAuthorization(authorizationHex)
        if authHash == lastAuthHash, let expiresAt = authExpiresAt, Date() < expiresAt {
            Self.logger.info("ℹ️ Skipping registration - auth unchanged and not expired")
            return
        }
        
        let request = RelayRegisterRequest(
            mailbox_id: mailboxId,
            authorization_hex: authorizationHex,
            ark_addr: arkAddr,
            device_token: deviceToken,
            apns_topic: apnsTopic,
            trigger: trigger.rawValue
        )
        
        // Note: don't log the full request payload here - authorization_hex and
        // device_token are credentials. Redacted params are logged by the caller
        // in WalletManager+Notifications.
        do {
            let response: RelayRegisterResponse = try await makeRequest(
                path: "/v1/register",
                method: "POST",
                body: request
            )
            
            Self.logger.notice("✅ Device registered: \(response.status, privacy: .public)")
            
            // Update state. Prefer the relay-reported expiry (read out of the
            // token itself) over the local authTTL assumption, so a TTL change
            // in bark-ffi needs no app change. A non-future expiry on a token
            // the relay just accepted is contradictory (clock skew or relay
            // bug) - fall back to the local TTL rather than let it drive an
            // immediate re-refresh loop.
            lastAuthHash = authHash
            lastRegisteredAt = Date()
            lastRegisteredDeviceToken = deviceToken
            let reportedExpiry = response.authorization_expires_at.map { Date(timeIntervalSince1970: $0) }
            if let reportedExpiry, reportedExpiry > Date() {
                authExpiresAt = reportedExpiry
            } else {
                authExpiresAt = Date().addingTimeInterval(authTTL)
            }

            // Schedule refresh
            scheduleAuthRefresh()

            // Mirror the in-process timer with a BGTask request — the fallback
            // for when the process is suspended or killed before the timer can
            // fire, asked for early (mid-life) because iOS grants it late
            #if os(iOS)
            BackgroundTaskCoordinator.shared.scheduleRefresh(earliestBeginDate: backgroundRefreshDate)
            #endif
        } catch let error as RelayError {
            Self.logger.error("❌ Registration failed: \(error.localizedDescription, privacy: .public)")
            
            // On auth error, clear cached state to force fresh registration next time
            if case .unauthorized = error {
                lastAuthHash = nil
                authExpiresAt = nil
                lastRegisteredAt = nil
            }
            
            throw error
        }
    }
    
    /// Unregisters device from the relay
    func unregisterDevice(mailboxId: String, deviceToken: String) async throws {
        let request = RelayUnregisterRequest(
            mailbox_id: mailboxId,
            device_token: deviceToken
        )
        
        do {
            let response: RelayUnregisterResponse = try await makeRequest(
                path: "/v1/register",
                method: "DELETE",
                body: request
            )
            
            Self.logger.notice("✅ Device unregistered: \(response.status, privacy: .public)")

            // Clear state
            lastAuthHash = nil
            authExpiresAt = nil
            lastRegisteredAt = nil
            refreshTimer?.cancel()

            // No registration left to keep fresh
            #if os(iOS)
            BackgroundTaskCoordinator.shared.cancelRefresh()
            #endif
        } catch let error as RelayError {
            Self.logger.error("❌ Unregistration failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Lists registrations for a mailbox
    func listRegistrations(mailboxId: String) async throws -> String {
        let url = URL(string: "\(relayBaseURL)/v1/registrations?mailbox_id=\(mailboxId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw try parseErrorResponse(data: data, statusCode: httpResponse.statusCode, response: httpResponse)
        }

        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - Authorization Refresh
    
    /// Schedules automatic refresh before authorization expires
    private func scheduleAuthRefresh() {
        // Cancel existing timer
        refreshTimer?.cancel()

        // Sleep until expiry minus buffer, from the real (possibly
        // relay-reported) expiry rather than the fixed TTL constant; the
        // floor keeps a short-lived token from spinning a refresh loop
        guard let refreshDate = nextRefreshDate else { return }
        let refreshDelay = max(refreshDate.timeIntervalSinceNow, 60)

        refreshTimer = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000))
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }

            Self.logger.notice("🔄 Auto-refreshing authorization (foreground timer fired)")
            BackgroundEventJournal.record(.foregroundTimerFired)

            // Clear cached state so the upcoming registerDevice() call (made
            // by the handler with access to the wallet) isn't skipped as a
            // no-op duplicate, then mint + send a fresh authorization.
            self.lastAuthHash = nil
            self.authExpiresAt = nil
            await self.onNeedsRefresh?()
        }
    }
    
    /// Forces immediate re-registration (call this after auth errors)
    func forceRefresh() {
        lastAuthHash = nil
        authExpiresAt = nil
        lastRegisteredAt = nil
        refreshTimer?.cancel()
    }
    
    // MARK: - HTTP Request Handling
    
    private func makeRequest<T: Encodable, R: Decodable>(
        path: String,
        method: String,
        body: T
    ) async throws -> R {
        let url = URL(string: "\(relayBaseURL)\(path)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        
        return try await performRequestWithRetry(request: request)
    }
    
    private func performRequestWithRetry<R: Decodable>(
        request: URLRequest,
        retryCount: Int = 0
    ) async throws -> R {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.invalidResponse
        }
        
        // Handle success
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            let decoder = JSONDecoder()
            return try decoder.decode(R.self, from: data)
        }
        
        // Parse error response
        let error = try parseErrorResponse(data: data, statusCode: httpResponse.statusCode, response: httpResponse)
        
        // Handle retryable errors
        if case .rateLimited(let retryAfter) = error {
            if retryCount < 1 {
                Self.logger.warning("⏳ Rate limited, retrying after \(retryAfter)s")
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return try await performRequestWithRetry(request: request, retryCount: retryCount + 1)
            }
        }
        
        if case .serverError = error {
            if retryCount < 2 {
                let backoffDelay = min(pow(2.0, Double(retryCount)) * 1.0, 10.0)
                Self.logger.warning("⏳ Server error, retrying after \(backoffDelay)s")
                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                return try await performRequestWithRetry(request: request, retryCount: retryCount + 1)
            }
        }
        
        throw error
    }
    
    private func parseErrorResponse(data: Data, statusCode: Int, response: HTTPURLResponse) throws -> RelayError {
        // Debug: Log raw error response for 400 errors
        if statusCode == 400, let rawError = String(data: data, encoding: .utf8) {
            Self.logger.debug("📥 Raw 400 error response: \(rawError)")
        }
        
        // Try to decode structured error response
        if let errorResponse = try? JSONDecoder().decode(RelayErrorResponse.self, from: data) {
            switch statusCode {
            case 400:
                return .badRequest(errorResponse.error)
            case 401:
                return .unauthorized(errorResponse.error)
            case 429:
                let retryAfter = errorResponse.retry_after_seconds
                    ?? Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60")
                    ?? 60
                return .rateLimited(retryAfter: retryAfter)
            case 500...599:
                return .serverError(errorResponse.error)
            default:
                return .httpError(statusCode, errorResponse.error)
            }
        }
        
        // Fallback for non-JSON errors
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        switch statusCode {
        case 400:
            return .badRequest(errorMessage)
        case 401:
            return .unauthorized(errorMessage)
        case 429:
            let retryAfter = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serverError(errorMessage)
        default:
            return .httpError(statusCode, errorMessage)
        }
    }
    
    private func addAuthHeader(to request: inout URLRequest) {
        guard let token = relayAPIToken, !token.isEmpty else { return }
        
        // Use x-relay-token header (could also use Authorization: Bearer)
        request.setValue(token, forHTTPHeaderField: "x-relay-token")
    }
    
    // MARK: - Utilities
    
    private func hashAuthorization(_ auth: String) -> String {
        let data = Data(auth.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum RelayError: LocalizedError {
    case badRequest(String)
    case unauthorized(String)
    case rateLimited(retryAfter: Int)
    case serverError(String)
    case httpError(Int, String)
    case invalidResponse
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .unauthorized(let message):
            return "Unauthorized: \(message). Check relay API token."
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter) seconds."
        case .serverError(let message):
            return "Server error: \(message)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .invalidResponse:
            return "Invalid response from relay"
        case .encodingError:
            return "Failed to encode request"
        }
    }
}
