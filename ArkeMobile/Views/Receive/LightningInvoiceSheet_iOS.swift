//
//  LightningInvoiceSheet_iOS.swift
//  Arké
//
//  Created by Assistant on 5/27/26.
//

import SwiftUI
import SwiftData
import ArkeUI
import Bark
import OSLog

/// Full-screen Lightning invoice QR sheet with tilt-based owner/recipient views
struct LightningInvoiceSheet_iOS: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "LightningInvoiceSheet")
    
    let invoice: String?
    let amount: String
    let note: String?
    let arkAddress: String
    let onchainAddress: String
    let isDeviceUpsideDown: Bool
    let onClose: () -> Void
    let walletManager: WalletManager
    
    @Query private var profiles: [UserProfile]
    @State private var qrImage: UIImage?
    @State private var qrImageSimple: UIImage?
    @State private var showCopySuccess = false
    @State private var showingStyledVersion = true
    @State private var screenWidth: CGFloat = 0
    
    // Payment monitoring
    @State private var subscriptionId: UUID?
    @State private var paymentHash: String?
    @State private var paymentReceived = false
    @State private var successVideoName: String = ReactionVideoPair.random().thumbsUp
    
    // Notification state
    @AppStorage(UserDefaults.notificationsEnabledKey)
    private var notificationsEnabled: Bool = false

    @AppStorage(UserDefaults.appThemeKey) private var theme: AppTheme = .defaultTheme
    @State private var notificationsJustEnabled = false
    
    private var userProfile: UserProfile? {
        profiles.first
    }
    
    private var formattedAmount: String {
        guard let sats = Int(amount) else { return amount }
        return BitcoinFormatter.shared.formatAmount(sats)
    }
    
    var body: some View {
        ZStack {
            // Background image
            Image(theme.images.qrBackground)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            
            // Dark overlay (darker when upside down)
            Color.black.opacity(isDeviceUpsideDown ? 0.6 : 0.3)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: isDeviceUpsideDown)
            
            // Content — this layer now keeps a real bottom safe-area inset
            GeometryReader { geo in
                ZStack {
                    ownerView(screenWidth: screenWidth)
                        .opacity(isDeviceUpsideDown ? 0 : 1)
                        .offset(y: isDeviceUpsideDown ? -50 : 0)
                        .accessibilityHidden(isDeviceUpsideDown)

                    recipientView(screenWidth: screenWidth)
                        .rotationEffect(.degrees(180))
                        .opacity(isDeviceUpsideDown ? 1 : 0)
                        .offset(y: isDeviceUpsideDown ? 0 : 50)
                        .accessibilityHidden(!isDeviceUpsideDown)
                }
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .animation(.easeInOut(duration: 0.25), value: isDeviceUpsideDown)
            }
        }
        .background {
            // Read width without becoming the safe-area boundary
            GeometryReader { geo in
                Color.clear
                    .onAppear { screenWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        screenWidth = newValue
                    }
            }
        }
        .task {
            generateQRCode()
            generateSimpleQRCode()
            setupPaymentListener()
            await checkAndPromptForNotifications()
        }
        .onDisappear {
            cleanupSubscription()
        }
    }
    
    // MARK: - Owner View (Normal Orientation)
    
    private func ownerView(screenWidth: CGFloat) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            // QR Code
            Text(paymentReceived ?
                L10n.statusPaymentReceived :
                String(localized: "receive_share_request_title", defaultValue: "Share your Request"))
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            
            ZStack {
                Group {
                    if showingStyledVersion {
                        if let qrImage = qrImage {
                            ZStack {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: qrCodeSize(for: screenWidth),
                                           height: qrCodeSize(for: screenWidth))
                                
                                NetworkIcons(showBitcoin: true, showArk: true, showLightning: invoice != nil, color: .primary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                    .padding(.bottom, invoice == nil ? 6 : 3)
                            }
                            .frame(width: qrCodeSize(for: screenWidth),
                                   height: qrCodeSize(for: screenWidth))
                        } else {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                                .frame(width: qrCodeSize(for: screenWidth),
                                       height: qrCodeSize(for: screenWidth))
                        }
                    } else {
                        if let qrImageSimple = qrImageSimple {
                            ZStack {
                                Image(uiImage: qrImageSimple)
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: qrCodeSize(for: screenWidth),
                                           height: qrCodeSize(for: screenWidth))
                                
                                NetworkIcons(showBitcoin: invoice == nil, showArk: invoice == nil, showLightning: invoice != nil, color: .primary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                    .padding(.bottom, 5)
                            }
                            .frame(width: qrCodeSize(for: screenWidth),
                                   height: qrCodeSize(for: screenWidth))
                        } else {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                                .frame(width: qrCodeSize(for: screenWidth),
                                       height: qrCodeSize(for: screenWidth))
                        }
                    }
                }
                .background(.white)
                .cornerRadius(20)
                .shadow(radius: 10, x: 0, y: 5)
                .transition(.scale.combined(with: .opacity))
                .onTapGesture {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()

                    withAnimation(.spring(response: 0.5, dampingFraction: 0.95)) {
                        showingStyledVersion.toggle()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(invoice != nil ?
                    String(localized: "accessibility_lightning_invoice_qr", defaultValue: "Lightning invoice QR code") :
                    L10n.accessibilityPaymentQr)
                .accessibilityHint(String(localized: "accessibility_hint_toggle_qr_style", defaultValue: "Switches between styled and plain QR code"))
                .accessibilityAddTraits(.isButton)
                
                // Video overlay (only shown when payment received)
                if paymentReceived {
                    LoopingVideoPlayer_iOS
                        .aspectFill(videoName: successVideoName, videoExtension: "mp4")
                        .frame(width: qrCodeSize(for: screenWidth),
                               height: qrCodeSize(for: screenWidth))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: qrCodeSize(for: screenWidth), height: qrCodeSize(for: screenWidth))
            
            if !amount.isEmpty || (note != nil && !note!.isEmpty) {
                VStack(spacing: 10) {
                    // Amount
                    if !amount.isEmpty {
                        Text(formattedAmount)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    // Note
                    if let note = note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 20) {
                // Share button
                HStack(spacing: 12) {
                    ShareLink(item: createBIP21URI()) {
                        Text(L10n.buttonShare)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.Arke.gold)
                    .controlSize(.large)
                    .accessibilityLabel(String(localized: "accessibility_share_payment_request", defaultValue: "Share payment request"))
                    .accessibilityHint(String(localized: "accessibility_share_payment_hint", defaultValue: "Opens share sheet to send address to others"))

                    // Enable notifications (only in primary mode - requires ASP connection)
                    if (!notificationsEnabled || notificationsJustEnabled) && !walletManager.isReadOnlyMode {
                        Button {
                            Task {
                                await enableNotifications()
                            }
                        } label: {
                            Image(systemName: notificationsJustEnabled ? "checkmark" : "bell.fill")
                                .font(.system(size: 21, weight: .semibold))
                                //.foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
                        .environment(\.colorScheme, .dark)
                        .disabled(notificationsJustEnabled)
                        .accessibilityLabel(notificationsJustEnabled ?
                            String(localized: "status_notifications_enabled", defaultValue: "Notifications enabled") :
                            String(localized: "action_enable_notifications", defaultValue: "Enable notifications"))
                        .accessibilityHint(String(localized: "accessibility_hint_enable_notifications", defaultValue: "Asks for permission to notify you when funds arrive"))
                    }
                }
                .disabled(paymentReceived)
                .opacity(paymentReceived ? 0 : 1)
                
                Button {
                    onClose()
                } label: {
                    Text(L10n.buttonDone)
                        .font(.system(size: 21, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(Color.Arke.gold)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - Recipient View (180° Rotated)
    
    private func recipientView(screenWidth: CGFloat) -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            // QR Code (larger for scanning)
            VStack(spacing: 24) {
                // Scan to Pay message
                Text(paymentReceived ?
                    L10n.statusPaymentReceived :
                    L10n.receiveScanToPayTitle)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                
                ZStack {
                    Group {
                        if showingStyledVersion {
                            if let qrImage = qrImage {
                                ZStack {
                                    Image(uiImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: qrCodeSize(for: screenWidth),
                                               height: qrCodeSize(for: screenWidth))
                                    
                                    NetworkIcons(showBitcoin: true, showArk: true, showLightning: invoice != nil, color: .primary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .padding(.bottom, invoice == nil ? 6 : 3)
                                }
                                .frame(width: qrCodeSize(for: screenWidth),
                                       height: qrCodeSize(for: screenWidth))
                            } else {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                    .frame(width: qrCodeSize(for: screenWidth),
                                           height: qrCodeSize(for: screenWidth))
                            }
                        } else {
                            if let qrImageSimple = qrImageSimple {
                                ZStack {
                                    Image(uiImage: qrImageSimple)
                                        .interpolation(.none)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: qrCodeSize(for: screenWidth),
                                               height: qrCodeSize(for: screenWidth))
                                    
                                    NetworkIcons(showBitcoin: invoice == nil, showArk: invoice == nil, showLightning: invoice != nil, color: .primary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .padding(.bottom, 5)
                                }
                                .frame(width: qrCodeSize(for: screenWidth),
                                       height: qrCodeSize(for: screenWidth))
                            } else {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                    .frame(width: qrCodeSize(for: screenWidth),
                                           height: qrCodeSize(for: screenWidth))
                            }
                        }
                    }
                    .background(.white)
                    .cornerRadius(20)
                    .shadow(radius: 10, x: 0, y: 5)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        withAnimation(.spring(response: 0.5, dampingFraction: 0.95)) {
                            showingStyledVersion.toggle()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(invoice != nil ?
                        String(localized: "accessibility_lightning_invoice_qr", defaultValue: "Lightning invoice QR code") :
                        L10n.accessibilityPaymentQr)
                    .accessibilityHint(String(localized: "accessibility_hint_toggle_qr_style", defaultValue: "Switches between styled and plain QR code"))
                    .accessibilityAddTraits(.isButton)
                    
                    // Video overlay (only shown when payment received)
                    if paymentReceived {
                        LoopingVideoPlayer_iOS
                            .aspectFill(videoName: successVideoName, videoExtension: "mp4")
                            .frame(width: qrCodeSize(for: screenWidth),
                                   height: qrCodeSize(for: screenWidth))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: qrCodeSize(for: screenWidth), height: qrCodeSize(for: screenWidth))
                
                if !amount.isEmpty || (note != nil && !note!.isEmpty) {
                    VStack(spacing: 8) {
                        // Amount
                        if !amount.isEmpty {
                            Text(formattedAmount)
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        
                        // Note
                        if let note = note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                }
                
                if let name = userProfile?.name, !name.isEmpty {
                    HStack(spacing: 8) {
                        // Profile image if available
                        if let avatarData = userProfile?.avatarData,
                           let uiImage = UIImage(data: avatarData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                                .accessibilityHidden(true)
                        }
                        
                        Text(name)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Helper Methods
    
    private func qrCodeSize(for screenWidth: CGFloat) -> CGFloat {
        let width = screenWidth > 0 ? screenWidth : 320  // fallback for first frame
        return min(width * 0.8, 400)  // Cap at 400pt for larger screens
    }
    
    private func generateQRCode() {
        let bip21URI = createBIP21URI()
        do {
            qrImage = try QRCodeGenerator.shared.generateStyledQRCode(from: bip21URI)
        } catch {
            Self.logger.error("Failed to generate styled QR code: \(error.localizedDescription)")
            // Fallback to simple QR generation if styled version fails
            qrImage = QRCodeGenerator.shared.generateSimpleQRCode(from: bip21URI)
        }
    }
    
    private func generateSimpleQRCode() {
        // Use lightning: URI for maximum interoperability with wallets that don't support BIP-21
        // If no invoice, use BIP-21 URI instead
        guard invoice != nil else {
            let bip21URI = createBIP21URI()
            qrImageSimple = QRCodeGenerator.shared.generateSimpleQRCode(from: bip21URI, padding: 30, cornerRadius: 50)
            return
        }
        
        let invoiceString = extractInvoiceString()
        let lightningURI = "lightning:\(invoiceString)"
        qrImageSimple = QRCodeGenerator.shared.generateSimpleQRCode(from: lightningURI, padding: 30, cornerRadius: 50)
    }
    
    private func extractInvoiceString() -> String {
        guard let invoice = invoice else { return "" }
        
        // Parse JSON if needed (invoice might be wrapped in JSON)
        if let data = invoice.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let invoiceStr = json["invoice"] as? String {
            return invoiceStr
        }
        return invoice
    }
    
    private func createBIP21URI() -> String {
        let invoiceString = invoice != nil ? extractInvoiceString() : nil
        let amountValue = amount.isEmpty ? nil : amount
        let noteValue = note?.isEmpty == false ? note : nil
        
        return BIP21URIHelper.createBIP21URI(
            arkAddress: arkAddress,
            onchainAddress: onchainAddress,
            lightningInvoice: invoiceString,
            amountSats: amountValue,
            message: noteValue
        )
    }
    
    private func copyInvoice() {
        let bip21URI = createBIP21URI()
        UIPasteboard.general.string = bip21URI
        
        // Show success feedback
        withAnimation {
            showCopySuccess = true
        }
        
        // Haptic feedback
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }
    
    // MARK: - Notification Prompt
    
    private func checkAndPromptForNotifications() async {
        // Check if this is the first payment request (no prior transactions)
        guard walletManager.transactions.isEmpty else { return }
        
        // Check if notifications are already enabled
        guard !notificationsEnabled else { return }
        
        // Check iOS notification permission status
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        // Only prompt if user has never been asked before
        guard settings.authorizationStatus == .notDetermined else { return }
        
        // Request permission directly
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        notificationsJustEnabled = true
                        notificationsEnabled = true
                    }
                }
                
                // Wait for token to be received
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                // Register with relay
                await walletManager.registerForPushNotifications()
                
                Self.logger.info("Successfully registered for notifications on first payment request")
            }
        } catch {
            Self.logger.error("Failed to request notifications: \(error.localizedDescription)")
        }
    }
    
    private func enableNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Permission previously denied - the system prompt won't show again, so send the user to Settings
        if settings.authorizationStatus == .denied {
            await MainActor.run {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            return
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
                // Set the local flag first: the AppStorage write can commit in a separate
                // transaction, and the button must never see (enabled, !justEnabled) or it
                // gets removed and re-inserted, making the share button jump.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    notificationsJustEnabled = true
                    notificationsEnabled = true
                }
            }

            // Wait for token to be received
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // Register with relay
            await walletManager.registerForPushNotifications()

            Self.logger.info("Successfully registered for notifications from invoice sheet")
        } catch {
            Self.logger.error("Failed to request notifications: \(error.localizedDescription)")
        }
    }

    // MARK: - Payment Monitoring
    
    private func setupPaymentListener() {
        // Only setup payment listener if we have an invoice
        guard let invoice = invoice else { return }
        
        // Extract payment hash from Lightning invoice (if present)
        paymentHash = LightningInvoiceParser.extractPaymentHash(fromInvoice: invoice)
        
        // Subscribe to movement notifications
        guard let service = walletManager.walletNotificationService else { return }
        
        subscriptionId = service.onMovementCreated { [arkAddress, paymentHash] movement in
            // Check if this movement is for our payment request
            if self.isPaymentForUs(movement, arkAddress: arkAddress, paymentHash: paymentHash) {
                self.handlePaymentReceived()
            }
        }
    }
    
    private func isPaymentForUs(_ movement: Movement, arkAddress: String, paymentHash: String?) -> Bool {
        // Check if we already received payment (prevent duplicate triggers)
        guard !paymentReceived else { return false }
        
        // Check if this is an incoming payment (positive effective balance)
        guard movement.effectiveBalanceSats > 0 else { return false }
        
        // Option 1: Check if payment was received on our Ark address
        if movement.receivedOnAddresses.contains(arkAddress) {
            return true
        }
        
        // Option 2: Check metadata for Lightning payment hash match
        if let hash = paymentHash, !hash.isEmpty {
            // The metadata_json field may contain Lightning payment information
            // Parse it to check for payment hash match
            if movement.metadataJson.contains(hash) {
                return true
            }
        }
        
        return false
    }
    
    private func handlePaymentReceived() {
        guard !paymentReceived else { return }
        
        // Haptic feedback
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        
        // Update UI with animation
        withAnimation(.easeInOut(duration: 0.4)) {
            paymentReceived = true
        }

        // Announce to VoiceOver users, who can't see the video overlay
        UIAccessibility.post(notification: .announcement, argument: L10n.statusPaymentReceived)
    }
    
    private func cleanupSubscription() {
        if let id = subscriptionId {
            walletManager.walletNotificationService?.removeSubscriber(id)
            subscriptionId = nil
        }
    }
}

