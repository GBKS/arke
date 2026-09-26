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

/// GET /v1/registrations response - what the relay currently holds for a
/// mailbox. Device tokens arrive pre-truncated (`device_token_suffix` is the
/// last 8 chars); `updated_at` is the relay's sqlite CURRENT_TIMESTAMP
/// ("YYYY-MM-DD HH:MM:SS", UTC).
struct RelayRegistrationsResponse: Codable {
    struct Registration: Codable {
        let apns_topic: String
        let device_token_suffix: String
        let updated_at: String?
    }

    let mailbox_id: String
    let count: Int
    let registrations: [Registration]
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
    
    /// Registration bookkeeping that must survive a cold launch. Tokens live
    /// `mailboxAuthorizationExpirySecs` (30 days); kept in memory only, every
    /// launch would re-mint and re-register — the churn the long lifetime
    /// exists to remove. Written through to UserDefaults on every change
    /// (`UserDefaults.relay*Key`). The authorization hex itself is never
    /// stored, only its hash. `nonisolated` so the pure load/persist helpers
    /// and their tests can compare values off the main actor.
    nonisolated struct PersistedRegistration: Equatable {
        /// SHA-256 of the last authorization sent (dedupe; never the token)
        var authHash: String?
        /// Expiry of the authorization the relay holds (relay-reported when available)
        var expiresAt: Date?
        /// When the last successful registration happened
        var registeredAt: Date?
        /// APNs device token that registration was made with
        var deviceToken: String?
        /// Mailbox that registration was for — a replaced wallet must not
        /// inherit the old wallet's "no renewal needed"
        var mailboxId: String?

        static let empty = PersistedRegistration()
    }

    private var registration: PersistedRegistration {
        didSet { Self.persist(registration, to: defaults) }
    }
    private let defaults: UserDefaults

    /// Lifetime requested for each mailbox authorization we mint
    /// (`mailboxAuthorization(expirySecs:)`, bark-ffi 0.25+). 30 days: the
    /// old fixed 24h left 124 of 151 relay mailboxes with expired tokens
    /// because iOS rarely granted the background refresh in time
    /// (SWIFT_AUTH_WAKE_SPEC.md). A token cannot be revoked early, so this is
    /// also how long a leaked token can read the mailbox — a deliberate
    /// trade-off (Migrations/Bark-0.24.0-to-0.25.0). The only place the
    /// number lives; `authTTL` derives from it.
    static let mailboxAuthorizationExpirySecs: UInt32 = 30 * 86_400

    /// Local assumption of the token lifetime when the relay doesn't report
    /// one (older relay versions); derived so it can't drift from the mint.
    private let authTTL: TimeInterval = TimeInterval(RelayRegistrationService.mailboxAuthorizationExpirySecs)

    /// Timer for scheduled authorization refresh
    private var refreshTimer: Task<Void, Never>?

    /// Expiry of the authorization the relay currently holds; nil until a
    /// successful registration. Read-only exposure for the X-Ray background
    /// activity header.
    var authorizationExpiresAt: Date? {
        registration.expiresAt
    }

    /// The one date every renewal path shares — the launch/foreground check,
    /// the in-process timer, the BGTask request and X-Ray: the midpoint of
    /// the token's actual life. One derived date, so the paths can't drift
    /// (the old BGTask date was "now + remaining/2", re-read on every
    /// backgrounding, so it crept toward expiry). nil until a successful
    /// registration.
    var renewalDate: Date? {
        guard let registeredAt = registration.registeredAt,
              let expiresAt = registration.expiresAt else { return nil }
        return Self.renewalDate(registeredAt: registeredAt, expiresAt: expiresAt)
    }

    /// Whether the unsolicited paths (launch, foreground) should mint and
    /// re-register now. The solicited paths (timer, BGTask, wake push) call
    /// `forceRefresh()` first and never consult this — they only run when
    /// the relay or the scheduler asked for a refresh.
    func needsRenewal(currentDeviceToken: String?, currentMailboxId: String) -> Bool {
        Self.needsRenewal(
            registeredAt: registration.registeredAt,
            expiresAt: registration.expiresAt,
            registeredDeviceToken: registration.deviceToken,
            currentDeviceToken: currentDeviceToken,
            registeredMailboxId: registration.mailboxId,
            currentMailboxId: currentMailboxId,
            now: Date()
        )
    }

    /// Midpoint of the authorization's *actual* life as the relay reported
    /// it. Deliberately not "expiresAt − lifetime/2" from the constant: if
    /// the relay ever capped a token to a shorter window, that would read as
    /// "less than half remains" on every launch and re-mint each time.
    nonisolated static func renewalDate(registeredAt: Date, expiresAt: Date) -> Date {
        registeredAt.addingTimeInterval(expiresAt.timeIntervalSince(registeredAt) / 2)
    }

    /// Pure renewal decision, extracted for unit tests. Renew when no
    /// registration is known, the APNs device token changed (the relay must
    /// learn new tokens immediately), the registration was for another
    /// mailbox (wallet replaced), or the token is past the midpoint of its
    /// life. Mailbox ids compare case-insensitively (bark-ffi has returned
    /// mixed case; the relay lowercases).
    nonisolated static func needsRenewal(
        registeredAt: Date?,
        expiresAt: Date?,
        registeredDeviceToken: String?,
        currentDeviceToken: String?,
        registeredMailboxId: String?,
        currentMailboxId: String,
        now: Date
    ) -> Bool {
        guard let registeredAt, let expiresAt,
              let currentDeviceToken, currentDeviceToken == registeredDeviceToken,
              let registeredMailboxId,
              registeredMailboxId.caseInsensitiveCompare(currentMailboxId) == .orderedSame else {
            return true
        }
        return now >= renewalDate(registeredAt: registeredAt, expiresAt: expiresAt)
    }

    /// Pure wake-targeting decision for `mailbox_auth_refresh` pushes,
    /// extracted for unit tests: the wake is for the current wallet when the
    /// payload's mailbox id matches case-insensitively (the relay lowercases
    /// ids; bark-ffi has returned mixed case). A mismatch means the wallet on
    /// this device was replaced and the wake names an orphaned registration.
    nonisolated static func isWakeForCurrentMailbox(
        payloadMailboxId: String,
        currentMailboxId: String
    ) -> Bool {
        currentMailboxId.caseInsensitiveCompare(payloadMailboxId) == .orderedSame
    }

    /// Called when the in-process timer reaches `renewalDate` so the caller
    /// can mint a fresh authorization (via the wallet) and re-register.
    /// Without this, a registered mailbox goes silently stale once its token
    /// expires and is never renewed until something else happens to
    /// re-register it.
    var onNeedsRefresh: (() async -> Void)?

    // MARK: - Initialization

    init(
        relayBaseURL: String = "https://relay.arke.cash",
        relayAPIToken: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.relayBaseURL = relayBaseURL
        self.relayAPIToken = relayAPIToken
        self.defaults = defaults
        // WalletManager recreates this service on every wallet init and nils
        // it on close, so the instance can't be the memory - the defaults are
        self.registration = Self.load(from: defaults)
    }

    deinit {
        refreshTimer?.cancel()
    }

    // MARK: - Persistence

    /// Reads the persisted registration; missing keys read as nil, so a
    /// first launch after the update (or after a wipe) yields `.empty` and
    /// `needsRenewal` says mint.
    nonisolated static func load(from defaults: UserDefaults) -> PersistedRegistration {
        func date(_ key: String) -> Date? {
            let interval = defaults.double(forKey: key)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        return PersistedRegistration(
            authHash: defaults.string(forKey: UserDefaults.relayAuthHashKey),
            expiresAt: date(UserDefaults.relayAuthExpiresAtKey),
            registeredAt: date(UserDefaults.relayRegisteredAtKey),
            deviceToken: defaults.string(forKey: UserDefaults.relayRegisteredDeviceTokenKey),
            mailboxId: defaults.string(forKey: UserDefaults.relayRegisteredMailboxIdKey)
        )
    }

    /// Writes the registration through; nil fields remove their key so
    /// `.empty` and "never registered" are indistinguishable on read.
    nonisolated static func persist(_ registration: PersistedRegistration, to defaults: UserDefaults) {
        func set(_ value: Any?, _ key: String) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        set(registration.authHash, UserDefaults.relayAuthHashKey)
        set(registration.expiresAt?.timeIntervalSince1970, UserDefaults.relayAuthExpiresAtKey)
        set(registration.registeredAt?.timeIntervalSince1970, UserDefaults.relayRegisteredAtKey)
        set(registration.deviceToken, UserDefaults.relayRegisteredDeviceTokenKey)
        set(registration.mailboxId, UserDefaults.relayRegisteredMailboxIdKey)
    }
    
    // MARK: - Public API
    
    /// Registers device with the relay
    /// - Parameters:
    ///   - mailboxId: Hex-encoded mailbox identifier
    ///   - authorizationHex: Mailbox authorization token (`mailboxAuthorizationExpirySecs` lifetime)
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
        if authHash == registration.authHash, let expiresAt = registration.expiresAt, Date() < expiresAt {
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
            
            // Update (and persist) state. Prefer the relay-reported expiry
            // (read out of the token itself) over the local authTTL
            // assumption, so a lifetime change needs no relay coordination. A
            // non-future expiry on a token the relay just accepted is
            // contradictory (clock skew or relay bug) - fall back to the local
            // TTL rather than let it drive an immediate re-refresh loop.
            let now = Date()
            let reportedExpiry = response.authorization_expires_at.map { Date(timeIntervalSince1970: $0) }
            let expiresAt: Date
            if let reportedExpiry, reportedExpiry > now {
                expiresAt = reportedExpiry
            } else {
                expiresAt = now.addingTimeInterval(authTTL)
            }
            registration = PersistedRegistration(
                authHash: authHash,
                expiresAt: expiresAt,
                registeredAt: now,
                deviceToken: deviceToken,
                mailboxId: mailboxId
            )

            // Schedule the in-process renewal timer
            scheduleAuthRefresh()

            // Mirror the timer with a BGTask request at the same renewal
            // date — the fallback for when the process is suspended or killed
            // before the timer can fire
            #if os(iOS)
            BackgroundTaskCoordinator.shared.scheduleRefresh(earliestBeginDate: renewalDate)
            #endif
        } catch let error as RelayError {
            Self.logger.error("❌ Registration failed: \(error.localizedDescription, privacy: .public)")

            // On auth error, clear cached state to force fresh registration next time
            if case .unauthorized = error {
                registration = .empty
            }
            
            throw error
        }
    }
    
    /// Unregisters device from the relay
    func unregisterDevice(mailboxId: String, deviceToken: String) async throws {
        try await sendUnregisterRequest(mailboxId: mailboxId, deviceToken: deviceToken)

        // Clear state (persisted too - the next opt-in must mint afresh)
        registration = .empty
        refreshTimer?.cancel()

        // No registration left to keep fresh
        #if os(iOS)
        BackgroundTaskCoordinator.shared.cancelRefresh()
        #endif
    }

    /// Unregisters a mailbox/device pair this device NO LONGER holds (wallet
    /// was replaced; the wake push named the old mailbox). Same DELETE as
    /// `unregisterDevice`, but touches none of the current wallet's
    /// registration state — clearing the expiry/freshness bookkeeping or
    /// cancelling the timer/BGTask here would break the CURRENT registration's
    /// refresh chain. Idempotent on the relay side (`removed: 0` is a 200).
    func unregisterStaleMailbox(mailboxId: String, deviceToken: String) async throws {
        try await sendUnregisterRequest(mailboxId: mailboxId, deviceToken: deviceToken)
    }

    /// Shared DELETE /v1/register request; callers own any state changes
    private func sendUnregisterRequest(mailboxId: String, deviceToken: String) async throws {
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
        } catch let error as RelayError {
            Self.logger.error("❌ Unregistration failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Fetches what the relay currently holds for a mailbox (X-Ray
    /// cross-check row - the relay's side of the registration story).
    func fetchRegistrations(mailboxId: String) async throws -> RelayRegistrationsResponse {
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

        return try JSONDecoder().decode(RelayRegistrationsResponse.self, from: data)
    }
    
    // MARK: - Authorization Refresh
    
    /// Schedules the in-process renewal at `renewalDate`. In practice the app
    /// is rarely resident for the ~15 days this sleeps; it matters for a
    /// device that stays awake (an iPad on a stand) and otherwise defers to
    /// the launch/foreground check and the BGTask.
    private func scheduleAuthRefresh() {
        // Cancel existing timer
        refreshTimer?.cancel()

        // The floor keeps a short-lived token from spinning a refresh loop
        guard let renewalDate else { return }
        let refreshDelay = max(renewalDate.timeIntervalSinceNow, 60)

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
            // no-op duplicate, then mint + send a fresh authorization. Not
            // forceRefresh(): that cancels this very task, and a cancelled
            // task's URLSession call throws before it reaches the relay.
            self.registration = .empty
            await self.onNeedsRefresh?()
        }
    }

    /// Forces immediate re-registration: the solicited paths (BGTask, wake
    /// push, auth errors) call this so the next mint is never skipped as
    /// fresh or as an unchanged duplicate.
    func forceRefresh() {
        registration = .empty
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
