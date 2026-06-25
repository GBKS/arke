//
//  ProximityExchangeManager.swift
//  Arké
//
//  Manages proximity-based payment info exchange using MultipeerConnectivity and NearbyInteraction
//

import Foundation
@preconcurrency import MultipeerConnectivity
import NearbyInteraction
import Combine
import Network
import OSLog

/// Represents the current state of the proximity exchange session
enum ProximityExchangeState: Equatable, CustomStringConvertible {
    case idle
    case awaitingPermission
    case discovering
    case peerFound(peerName: String)
    case proximityMet
    case exchanging
    case complete(bip21URI: String, peerName: String)
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .awaitingPermission:
            return "awaitingPermission"
        case .discovering:
            return "discovering"
        case .peerFound(let peerName):
            return "peerFound(\(peerName))"
        case .proximityMet:
            return "proximityMet"
        case .exchanging:
            return "exchanging"
        case .complete(let bip21URI, let peerName):
            return "complete(bip21URI: \(bip21URI), peerName: \(peerName))"
        case .error(let message):
            return "error(\(message))"
        }
    }
}

/// Manages peer-to-peer proximity exchange of payment information
@MainActor
class ProximityExchangeManager: NSObject, ObservableObject {
    
    // MARK: - Logger
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ProximityExchange")
    
    // MARK: - Published Properties
    
    @Published private(set) var state: ProximityExchangeState = .idle
    @Published var receivedPaymentInfo: ReceivedPaymentInfo?
    @Published private(set) var discoveredPeers: Set<String> = []
    @Published private(set) var isAdvertising: Bool = false
    @Published private(set) var isBrowsing: Bool = false

    /// Non-blocking hint shown while discovering when the radio environment is likely to
    /// prevent peer-to-peer Wi-Fi (AWDL) discovery — e.g. Wi-Fi off or Low Power Mode.
    @Published private(set) var environmentWarning: String?
    
    // MARK: - Private Properties
    
    private let serviceType = "arkepayment"
    private let myPeerID: MCPeerID
    nonisolated(unsafe) private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    // NearbyInteraction (iPhone 11+)
    private var niSession: NISession?
    private var niDiscoveryToken: NIDiscoveryToken?
    private var connectedPeer: MCPeerID?
    
    // Exchange tracking
    private var hasExchangedInCurrentSession = false
    private var proximityTimer: Timer?
    private var myBIP21URI: String?
    private var myAvatarData: Data?
    
    // Timeout tracking
    private var connectionTimeoutTimer: Timer?
    private let connectionTimeoutDuration: TimeInterval = 30.0
    
    // Retry tracking
    private var lastFoundPeers: Set<MCPeerID> = []
    private var invitationRetryTimer: Timer?
    
    // Distance threshold for proximity detection (in meters)
    private let proximityThreshold: Float = 1.5

    // Radio environment monitoring. MultipeerConnectivity relies on peer-to-peer Wi-Fi
    // (AWDL), which collapses when Wi-Fi is off or Low Power Mode throttles the radio —
    // the common reason discovery works on a desk but fails out in the wild.
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.arke.proximity.path")
    private var isWiFiAvailable = true
    
    // MARK: - Initialization
    
    override init() {
        // Reuse a persisted peer ID across launches. Minting a fresh one each launch
        // causes ghost peers and failed sessions on the remote device.
        self.myPeerID = Self.loadOrCreatePeerID()
        super.init()
    }
    
    /// Loads the archived `MCPeerID` from `UserDefaults`, or creates and persists a new
    /// one. Regenerates if the device's display name has changed since it was stored.
    private static func loadOrCreatePeerID() -> MCPeerID {
        let defaults = UserDefaults.standard
        let displayName = UIDevice.current.name
        
        if let data = defaults.data(forKey: UserDefaults.proximityPeerIDKey),
           defaults.string(forKey: UserDefaults.proximityPeerIDNameKey) == displayName,
           let peerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            return peerID
        }
        
        let peerID = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            defaults.set(data, forKey: UserDefaults.proximityPeerIDKey)
            defaults.set(displayName, forKey: UserDefaults.proximityPeerIDNameKey)
        }
        return peerID
    }
    
    // MARK: - Public Methods
    
    /// Show permission prompt
    func showPermissionPrompt(bip21URI: String, avatarData: Data? = nil) {
        guard state == .idle else { return }
        
        myBIP21URI = bip21URI
        myAvatarData = avatarData
        state = .awaitingPermission
    }
    
    /// Start advertising and browsing for peers with the given payment info
    func startExchange(bip21URI: String, avatarData: Data? = nil) {
        guard state == .awaitingPermission || state == .idle else { return }
        
        myBIP21URI = bip21URI
        myAvatarData = avatarData
        hasExchangedInCurrentSession = false
        receivedPaymentInfo = nil
        
        startRadioMonitoring()
        setupSession()
        startAdvertising()
        startBrowsing()
        startNearbyInteraction()
        
        state = .discovering
        triggerSearchingHaptic()
        
        // Start connection timeout timer
        startConnectionTimeout()
    }
    
    /// Stop all exchange activities and clean up
    func stopExchange() {
        proximityTimer?.invalidate()
        proximityTimer = nil
        
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        
        invitationRetryTimer?.invalidate()
        invitationRetryTimer = nil
        
        stopRadioMonitoring()
        
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
        
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        
        niSession?.invalidate()
        niSession = nil
        niDiscoveryToken = nil
        
        session?.disconnect()
        session = nil
        
        connectedPeer = nil
        myBIP21URI = nil
        myAvatarData = nil
        hasExchangedInCurrentSession = false
        discoveredPeers.removeAll()
        lastFoundPeers.removeAll()
        
        state = .idle
        
        Self.logger.info("Stopped exchange and cleaned up")
    }
    
    /// Clear received payment info (after user handles it)
    func clearReceivedPaymentInfo() {
        receivedPaymentInfo = nil
    }
    
    /// Opens the app's settings page so the user can grant Local Network / Bluetooth
    /// access. There is no public API to read Local Network authorization status, so we
    /// surface this route from the failure path rather than detecting denial directly.
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    // MARK: - Private Setup Methods
    
    private func setupSession() {
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }
    
    private func startConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeoutDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Only timeout if we're still in discovering state
                if case .discovering = self.state {
                    Self.logger.warning("Connection timeout - no peers found or connected")
                    
                    // Tailor the guidance to whatever we actually detected, rather than a
                    // generic message. Low Power Mode and Wi-Fi being off are the usual
                    // culprits for discovery failing away from a known network.
                    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                    let detail: String
                    if !self.isWiFiAvailable {
                        detail = "Wi-Fi appears to be off. Enable Wi-Fi on both devices — you don't need to be on a network."
                    } else if lowPower {
                        detail = "Low Power Mode can block nearby discovery. Turn it off on both devices and try again."
                    } else {
                        // Radio looks fine — denied Local Network permission is the most
                        // likely remaining cause, and it fails silently with no callback.
                        detail = "Check that Local Network access is enabled for Arké in Settings, and that both devices have Bluetooth on and are unlocked."
                    }
                    self.state = .error("No nearby devices found. \(detail)")
                    self.triggerErrorHaptic()
                }
            }
        }
    }
    
    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }
    
    // MARK: - Radio Environment Monitoring
    
    private func startRadioMonitoring() {
        // Optimistic until the first path update arrives.
        isWiFiAvailable = true
        
        pathMonitor.pathUpdateHandler = { [weak self] path in
            // `availableInterfaces` lists a Wi-Fi interface when the radio is on, even
            // when not joined to a network. There is no public API to read the Wi-Fi
            // toggle directly, so this is a best-effort proxy, not a hard gate.
            let wifi = path.availableInterfaces.contains { $0.type == .wifi }
            guard let self = self else { return }
            Task { @MainActor in
                self.isWiFiAvailable = wifi
                self.updateEnvironmentWarning()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.updateEnvironmentWarning() }
        }
        
        updateEnvironmentWarning()
    }
    
    private func stopRadioMonitoring() {
        pathMonitor.cancel()
        pathMonitor.pathUpdateHandler = nil
        NotificationCenter.default.removeObserver(self, name: .NSProcessInfoPowerStateDidChange, object: nil)
        environmentWarning = nil
    }
    
    /// Recomputes the non-blocking discovery hint from the current radio state.
    private func updateEnvironmentWarning() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        var issues: [String] = []
        if !isWiFiAvailable { issues.append("turn on Wi-Fi (you don't need to join a network)") }
        if lowPower { issues.append("turn off Low Power Mode") }
        
        if issues.isEmpty {
            environmentWarning = nil
        } else {
            environmentWarning = "For best results, both devices should " + issues.joined(separator: " and ") + "."
            Self.logger.warning("Radio environment suboptimal: wifi=\(self.isWiFiAvailable), lowPower=\(lowPower)")
        }
    }
    
    private func scheduleRetryIfNeeded() {
        // Only retry if we have peers but no connection yet
        guard connectedPeer == nil, !lastFoundPeers.isEmpty else { return }
        
        // Cancel existing retry timer
        invitationRetryTimer?.invalidate()
        
        // Schedule retry in 5 seconds
        invitationRetryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.retryConnectionToPeers()
            }
        }
    }
    
    private func retryConnectionToPeers() {
        guard let session = session, let browser = browser else { return }
        guard connectedPeer == nil else { return }
        
        Self.logger.info("Retrying connection to \(self.lastFoundPeers.count) known peer(s)")
        
        for peerID in self.lastFoundPeers {
            let peerHash = peerID.hash
            let myHash = myPeerID.hash
            
            // Use same logic as initial invitation
            let shouldInvite: Bool
            if myHash > peerHash {
                shouldInvite = true
            } else if myHash == peerHash {
                shouldInvite = myPeerID.displayName > peerID.displayName
            } else {
                shouldInvite = false
            }
            
            if shouldInvite {
                Self.logger.info("Retrying invitation to peer: \(peerID.displayName)")
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
            }
        }
    }
    
    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        Self.logger.info("Started advertising as '\(self.myPeerID.displayName)' with service type '\(self.serviceType)'")
    }
    
    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        Self.logger.info("Started browsing for peers with service type '\(self.serviceType)'")
    }
    
    private func startNearbyInteraction() {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            Self.logger.info("NearbyInteraction not supported on this device")
            return
        }
        
        niSession = NISession()
        niSession?.delegate = self
        niDiscoveryToken = niSession?.discoveryToken
        Self.logger.info("Started NearbyInteraction session with token: \(self.niDiscoveryToken != nil)")
    }
    
    // MARK: - Exchange Logic
    
    private func checkAndInitiateExchange() {
        // Only exchange once per session and only if we haven't already
        guard !hasExchangedInCurrentSession,
              let peer = connectedPeer,
              let uri = myBIP21URI else { return }
        
        // Mark as exchanged immediately to prevent duplicate sends
        hasExchangedInCurrentSession = true
        state = .exchanging
        triggerExchangingHaptic()
        
        sendPaymentInfo(uri: uri, to: peer)
    }
    
    private func sendPaymentInfo(uri: String, to peer: MCPeerID) {
        guard let session = session else {
            Self.logger.error("Cannot send payment info - no active session")
            state = .error("Connection lost")
            triggerErrorHaptic()
            return
        }
        
        // Verify session is in connected state
        guard session.connectedPeers.contains(peer) else {
            Self.logger.error("Cannot send payment info - peer not connected")
            state = .error("Connection lost")
            triggerErrorHaptic()
            return
        }
        
        let payload = PaymentInfoPayload(bip21URI: uri, avatarData: myAvatarData)
        
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: [peer], with: .reliable)
            Self.logger.info("Successfully sent payment info to peer: \(peer.displayName)")
        } catch {
            Self.logger.error("Failed to send payment info: \(error.localizedDescription)")
            state = .error("Failed to send payment info: \(error.localizedDescription)")
            triggerErrorHaptic()
        }
    }
    
    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(PaymentInfoPayload.self, from: data)
            
            // Store received payment info
            receivedPaymentInfo = ReceivedPaymentInfo(
                bip21URI: payload.bip21URI,
                avatarData: payload.avatarData
            )
            
            state = .complete(bip21URI: payload.bip21URI, peerName: peer.displayName)
            
            // Trigger haptic feedback
            triggerSuccessHaptic()
            
        } catch {
            state = .error("Failed to decode payment info: \(error.localizedDescription)")
            triggerErrorHaptic()
        }
    }
    
    // MARK: - Haptic Feedback
    
    /// Very light tap when searching starts
    private func triggerSearchingHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    /// Light-medium tap when peer is discovered
    private func triggerPeerDiscoveredHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impact2 = UIImpactFeedbackGenerator(style: .medium)
            impact2.impactOccurred()
        }
    }
    
    /// Medium tap when connection is established
    private func triggerConnectionHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    /// Medium-heavy tap when proximity is detected
    private func triggerProximityMetHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impact2 = UIImpactFeedbackGenerator(style: .heavy)
            impact2.impactOccurred()
        }
    }
    
    /// Heavy tap when exchange starts
    private func triggerExchangingHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
    }
    
    /// Success pattern - three quick taps
    private func triggerSuccessHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            impact.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            impact.impactOccurred()
        }
    }
    
    /// Error notification
    private func triggerErrorHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.error)
    }
}

// MARK: - MCSessionDelegate

extension ProximityExchangeManager: MCSessionDelegate {
    
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange newState: MCSessionState) {
        Task { @MainActor in
            switch newState {
            case .connected:
                Self.logger.info("Session connected to peer: \(peerID.displayName)")
                connectedPeer = peerID
                state = .peerFound(peerName: peerID.displayName)
                triggerConnectionHaptic()
                
                // Cancel connection timeout since we've connected
                cancelConnectionTimeout()
                
                // Share NI discovery token if available
                if let token = niDiscoveryToken {
                    Self.logger.info("Sharing NI discovery token with peer")
                    // Small delay to ensure session channels are fully ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.shareNIDiscoveryToken(token, with: peerID)
                        }
                    }
                } else {
                    // NearbyInteraction not supported - exchange immediately
                    Self.logger.info("NI not available, exchanging immediately after connection")
                    checkAndInitiateExchange()
                }
                
            case .notConnected:
                Self.logger.info("Session disconnected from peer: \(peerID.displayName)")
                if connectedPeer == peerID {
                    connectedPeer = nil
                    // Check if we're in a completed state
                    if case .complete = state {
                        // Already completed, don't change state
                    } else {
                        // Not completed yet, go back to discovering
                        state = .discovering
                        // Restart connection timeout
                        startConnectionTimeout()
                    }
                }
                
            case .connecting:
                Self.logger.info("Session connecting to peer: \(peerID.displayName)")
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            // Check if this is NI token data or payment info
            if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                handleReceivedNIToken(token, from: peerID)
            } else {
                handleReceivedData(data, from: peerID)
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
    
    // MARK: - NI Token Sharing
    
    private func shareNIDiscoveryToken(_ token: NIDiscoveryToken, with peer: MCPeerID) {
        guard let session = session else {
            Self.logger.error("Cannot share NI token - no active session")
            return
        }
        
        // Verify peer is still connected
        guard session.connectedPeers.contains(peer) else {
            Self.logger.error("Cannot share NI token - peer not connected")
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try session.send(data, toPeers: [peer], with: .reliable)
            Self.logger.info("Sent NI token to peer: \(peer.displayName)")
        } catch {
            Self.logger.error("Failed to share NI token: \(error)")
            // Don't set error state here - we can fall back to immediate exchange
            // NearbyInteraction not supported - exchange immediately
            Self.logger.info("NI token sharing failed, exchanging immediately")
            checkAndInitiateExchange()
        }
    }
    
    private func handleReceivedNIToken(_ token: NIDiscoveryToken, from peer: MCPeerID) {
        guard let niSession = niSession else {
            Self.logger.warning("Received NI token but niSession is nil")
            return
        }
        
        Self.logger.info("Received NI token from peer: \(peer.displayName), starting NI session")
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession.run(config)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ProximityExchangeManager: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let peerDisplayName = peerID.displayName
        
        // CRITICAL: invitationHandler must be called synchronously on the calling thread
        // Calling it from async Task can cause connection failures
        
        // Access session property - it's marked nonisolated(unsafe) for this reason
        let currentSession = self.session
        let accepted = currentSession != nil
        
        // Call handler synchronously
        invitationHandler(accepted, currentSession)
        
        // Log asynchronously after handler is called
        Task { @MainActor in
            if accepted {
                Self.logger.info("Accepted invitation from peer: \(peerDisplayName)")
            } else {
                Self.logger.warning("Rejected invitation from peer: \(peerDisplayName) - no active session")
            }
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            Self.logger.error("Advertiser failed to start: \(error.localizedDescription)")
            
            // Provide more helpful error messages
            let errorMessage: String
            if let nsError = error as NSError? {
                switch nsError.code {
                case 0: // Bluetooth off
                    errorMessage = "Bluetooth is turned off. Please enable it in Settings."
                case 1: // Bluetooth unauthorized
                    errorMessage = "Bluetooth access denied. Please enable it in Settings."
                default:
                    errorMessage = "Failed to start advertising. Make sure Bluetooth and Wi-Fi are enabled."
                }
            } else {
                errorMessage = "Failed to start advertising: \(error.localizedDescription)"
            }
            
            state = .error(errorMessage)
            isAdvertising = false
            triggerErrorHaptic()
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ProximityExchangeManager: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peerDisplayName = peerID.displayName
        let peerHash = peerID.hash
        
        Task { @MainActor in
            Self.logger.info("Browser found peer: \(peerDisplayName)")
            
            // Track this peer for potential retry
            self.lastFoundPeers.insert(peerID)
            
            // Only invite if our peer ID hash is greater to prevent simultaneous connections
            // This ensures only one device initiates the connection, even with same display names
            let currentSession = self.session
            let myHash = self.myPeerID.hash
            
            // If hashes are equal (rare but possible), use string comparison as tiebreaker
            let shouldInvite: Bool
            if myHash > peerHash {
                shouldInvite = true
            } else if myHash == peerHash {
                shouldInvite = self.myPeerID.displayName > peerID.displayName
            } else {
                shouldInvite = false
            }
            
            if let currentSession = currentSession, shouldInvite {
                Self.logger.info("Inviting peer: \(peerDisplayName) (our hash: \(myHash), their hash: \(peerHash))")
                browser.invitePeer(peerID, to: currentSession, withContext: nil, timeout: 10)
            } else {
                Self.logger.info("Not inviting peer: \(peerDisplayName) (waiting for them to invite us)")
            }
            
            // Update UI state
            self.discoveredPeers.insert(peerDisplayName)
            self.triggerPeerDiscoveredHaptic()
            
            // Start retry timer if not connected yet
            self.scheduleRetryIfNeeded()
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            Self.logger.info("Browser lost peer: \(peerID.displayName)")
            discoveredPeers.remove(peerID.displayName)
            lastFoundPeers.remove(peerID)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            Self.logger.error("Browser failed to start: \(error.localizedDescription)")
            
            // Provide more helpful error messages
            let errorMessage: String
            if let nsError = error as NSError? {
                switch nsError.code {
                case 0: // Bluetooth off
                    errorMessage = "Bluetooth is turned off. Please enable it in Settings."
                case 1: // Bluetooth unauthorized
                    errorMessage = "Bluetooth access denied. Please enable it in Settings."
                default:
                    errorMessage = "Failed to start browsing. Make sure Bluetooth and Wi-Fi are enabled."
                }
            } else {
                errorMessage = "Failed to start browsing: \(error.localizedDescription)"
            }
            
            state = .error(errorMessage)
            isBrowsing = false
            triggerErrorHaptic()
        }
    }
}

// MARK: - NISessionDelegate

extension ProximityExchangeManager: NISessionDelegate {
    
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            guard let object = nearbyObjects.first else {
                Self.logger.debug("NI update with no objects")
                return
            }
            
            Self.logger.debug("NI update - distance: \(object.distance?.description ?? "nil"), direction: \(object.direction?.description ?? "nil")")
            
            // Check if peer is within proximity threshold
            if let distance = object.distance, distance <= self.proximityThreshold {
                Self.logger.info("Peer within proximity threshold (\(distance)m <= \(self.proximityThreshold)m)")
                
                // Peer is close enough - check direction too if available
                let isProximityMet = checkProximityConditions(object)
                
                // Check if we're in peerFound state (any peer name)
                if case .peerFound = state, isProximityMet {
                    Self.logger.info("Proximity conditions met, setting state to proximityMet")
                    state = .proximityMet
                    triggerProximityMetHaptic()
                    
                    // Debounce: wait a moment to ensure stable proximity before exchanging
                    proximityTimer?.invalidate()
                    proximityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.checkAndInitiateExchange()
                        }
                    }
                } else {
                    Self.logger.debug("Current state: \(self.state), isProximityMet: \(isProximityMet)")
                }
            }
        }
    }
    
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            let reasonDescription: String
            switch reason {
            case .timeout:
                reasonDescription = "timeout"
            case .peerEnded:
                reasonDescription = "peerEnded"
            @unknown default:
                reasonDescription = "unknown"
            }
            Self.logger.info("NI removed objects, reason: \(reasonDescription)")
        }
    }
    
    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            Self.logger.info("NI session suspended")
        }
    }
    
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            Self.logger.info("NI session resumed")
        }
    }
    
    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            let errorDescription = error.localizedDescription
            Self.logger.error("NI session invalidated with error: \(errorDescription)")
            
            // If NI session fails but we're still connected, fall back to immediate exchange
            if self.connectedPeer != nil, case .peerFound = self.state {
                Self.logger.info("NI session failed but peer connected - exchanging immediately")
                self.checkAndInitiateExchange()
            }
        }
    }
    
    private func checkProximityConditions(_ object: NINearbyObject) -> Bool {
        // For now, just check distance
        // In the future, could add direction checks (azimuth/elevation) to ensure devices are facing each other
        guard let distance = object.distance else { return false }
        
        return distance <= proximityThreshold
    }
}

// MARK: - Supporting Types

struct PaymentInfoPayload: Codable {
    let bip21URI: String
    let avatarData: Data?
}

struct ReceivedPaymentInfo: Equatable {
    let bip21URI: String
    let avatarData: Data?
}
