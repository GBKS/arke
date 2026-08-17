//
//  ActivityView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct ActivityView_iOS: View {
    @Environment(WalletManager.self) private var manager
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTransaction: TransactionModel?
    let filterTag: PersistentTag?
    let filterContact: PersistentContact?
    let onClearFilter: (() -> Void)?
    let onNavigate: ((ActivityDestination) -> Void)?
    let onNavigateToReceive: (() -> Void)?
    
    // State for scroll tracking
    @State private var scrollOffset: CGFloat = 0
    
    // State for faucet modal
    @State private var showFaucetModal = false
    
    // State for connection info sheet
    @State private var showConnectionInfoSheet = false

    // State for recovery phrase entry (offered when read-only because the seed
    // hasn't synced to this device yet)
    @State private var showImportWalletSheet = false
    
    // State for balance privacy mode (persistent across app launches)
    @AppStorage(UserDefaults.balancePrivacyKey) private var isBalanceHidden = false
    
    // Grace period to avoid showing connection status during initial app startup
    @State private var hasPassedStartupGracePeriod = false
    
    // Constants for layout
    private let balanceCardHeight: CGFloat = 120 // Approximate height, adjust as needed
    private let scrollThreshold: CGFloat = 60 // When to show condensed balance
    private let connectionStatusGracePeriod: TimeInterval = 4.0 // Seconds to wait before showing connection status
    
    init(selectedTransaction: Binding<TransactionModel?>, filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onClearFilter: (() -> Void)? = nil, onNavigate: ((ActivityDestination) -> Void)? = nil, onNavigateToReceive: (() -> Void)? = nil) {
        self._selectedTransaction = selectedTransaction
        self.filterTag = filterTag
        self.filterContact = filterContact
        self.onClearFilter = onClearFilter
        self.onNavigate = onNavigate
        self.onNavigateToReceive = onNavigateToReceive
    }
    
    // Calculate opacity for condensed balance (fade in when scrolled)
    private var condensedBalanceOpacity: Double {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        return progress
    }
    
    // Calculate opacity for full balance card (fade out when scrolling)
    private var balanceCardOpacity: Double {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        return 1 - progress
    }
    
    // Connection status helpers
    private var hasArkConnection: Bool {
        manager.connectionStatus.isConnected
    }
    
    private var hasGoodConnection: Bool {
        manager.connectionStatus.quality == .excellent || manager.connectionStatus.quality == .good
    }
    
    private var shouldShowConnectionStatus: Bool {
        // Show read-only mode indicator immediately
        if manager.connectionStatus.isReadOnlyMode {
            return true
        }
        
        // Hybrid approach: Show status after wallet loads OR grace period expires
        // This ensures quick response when data loads, with a safety timeout for slow connections
        let shouldConsiderShowingStatus = manager.hasLoadedOnce || hasPassedStartupGracePeriod
        guard shouldConsiderShowingStatus else { return false }
        
        return !hasArkConnection || !hasGoodConnection
    }
    
    private var connectionStatusIcon: String {
        if manager.connectionStatus.isReadOnlyMode {
            return "cloud.fill"
        } else if !hasArkConnection {
            return "antenna.radiowaves.left.and.right.slash"
        } else if !hasGoodConnection {
            return "wifi.exclamationmark"
        }
        return "wifi.exclamationmark"
    }
    
    private var connectionStatusColor: Color {
        if manager.connectionStatus.isReadOnlyMode {
            return Color.Arke.gold
        } else if !hasArkConnection {
            return Color.Arke.orange
        } else if !hasGoodConnection {
            return Color.Arke.orange
        }
        return Color.Arke.orange
    }
    
    private var connectionStatusDescription: String {
        if manager.connectionStatus.isReadOnlyMode {
            return String(localized: "accessibility_connection_readonly", defaultValue: "Read-only mode")
        } else if !hasArkConnection {
            return String(localized: "accessibility_connection_none", defaultValue: "No connection")
        } else if !hasGoodConnection {
            return String(localized: "accessibility_connection_poor", defaultValue: "Poor connection quality")
        }
        return String(localized: "accessibility_connection_issue", defaultValue: "Connection issue")
    }
    
    var body: some View {
        scrollContent
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Balance Card - inside scroll view, not fixed
                BalanceCard(totalBalance: manager.totalBalance, isHidden: $isBalanceHidden)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        withAnimation(.snappy) {
                            isBalanceHidden.toggle()
                        }
                    }
                    .onTapGesture {
                        onNavigate?(.balance)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(String(localized: "accessibility_balance_label", defaultValue: "Balance"))
                    .accessibilityValue(isBalanceHidden ? String(localized: "accessibility_balance_hidden", defaultValue: "Hidden") : (manager.totalBalance.map { BitcoinFormatter.shared.formatAmount($0.grandTotalSat) } ?? String(localized: "accessibility_balance_loading", defaultValue: "Loading")))
                    .accessibilityHint(String(localized: "accessibility_balance_hint", defaultValue: "Tap to view balance details. Long press to toggle balance visibility."))
                    .accessibilityAddTraits(.isButton)
                
                // Filter chip (if active)
                if let tag = filterTag {
                    FilterChipView(tag: tag, onClear: clearFilter)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                } else if let contact = filterContact {
                    FilterChipView(contact: contact, onClear: clearFilter)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                
                // Transaction List
                if let transactionService = manager.transactionServiceInstance {
                    // Error Display - Transaction-specific errors
                    if let error = transactionService.error {
                        ErrorBox(errorMessage: error)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                    
                    TransactionList_iOS(
                        selectedTransaction: $selectedTransaction,
                        filterTag: filterTag,
                        filterContact: filterContact,
                        onShowFaucet: manager.isMainnet ? nil : {
                            showFaucetModal = true
                        },
                        onNavigateToReceive: onNavigateToReceive
                    )
                        .environment(transactionService)
                        .onAppear {
                            // Double-check ModelContext is set (defensive programming)
                            transactionService.setModelContext(modelContext)
                        }
                        .id("\(filterTag?.id.uuidString ?? "none")_\(filterContact?.id.uuidString ?? "none")")
                } else {
                    ContentUnavailableView {
                        VStack(spacing: 15) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityLabel(String(localized: "accessibility_loading_label", defaultValue: "Loading"))
                            Text(String(localized: "progress_loading_transactions", defaultValue: "Loading transactions..."))
                                .font(.system(size: 19, design: .serif))
                        }
                    }
                }
            }
            .background {
                // GeometryReader to track scroll offset
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geometry.frame(in: .named("scroll")).minY
                        )
                }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .frame(maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
        .refreshable {
            // Only allow refresh in primary mode (requires wallet/ASP connection)
            if !manager.isReadOnlyMode {
                // Progress any pending rounds (handled by RoundProgressionService)
                try? await manager.progressPendingRounds()
                
                // Refresh wallet data
                await manager.refresh()
            }
        }
        .toolbar {
            /*
            ToolbarItem(placement: .principal) {
                // Condensed balance indicator
                Text(manager.totalBalance.map { BitcoinFormatter.shared.formatAmount($0.grandTotalSat) } ?? "—")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            */
            
            // Faucet button (only on testnet/signet and not in read-only mode)
            if !manager.isMainnet && !manager.isReadOnlyMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFaucetModal = true
                    } label: {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(String(localized: "accessibility_faucet_label", defaultValue: "Test Faucet"))
                    .accessibilityHint(String(localized: "accessibility_faucet_hint", defaultValue: "Get test bitcoin from faucet"))
                }
            }
            
            // Connection status indicator (signet, no ark connection, or no internet)
            if shouldShowConnectionStatus {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showConnectionInfoSheet = true
                    } label: {
                        Image(systemName: connectionStatusIcon)
                            .font(.system(size: 15))
                            .foregroundStyle(connectionStatusColor)
                    }
                    .accessibilityLabel(String(localized: "accessibility_connection_status_label", defaultValue: "Connection Status"))
                    .accessibilityValue(connectionStatusDescription)
                    .accessibilityHint(String(localized: "accessibility_connection_status_hint", defaultValue: "View connection details"))
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNavigate?(.tags)
                } label: {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(String(localized: "accessibility_tags_label", defaultValue: "Tags"))
                .accessibilityHint(String(localized: "accessibility_tags_hint", defaultValue: "View and manage transaction tags"))
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNavigate?(.settings)
                } label: {
                    Image(systemName: "xmark.triangle.circle.square.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(String(localized: "accessibility_settings_label", defaultValue: "Settings"))
                .accessibilityHint(String(localized: "accessibility_settings_hint", defaultValue: "Open settings and preferences"))
            }
        }
        .onChange(of: selectedTransaction) { oldValue, newValue in
            if let transaction = newValue {
                onNavigate?(.transaction(transaction))
                // Reset after navigation
                selectedTransaction = nil
            }
        }
        .sheet(isPresented: $showFaucetModal) {
            FaucetModalView_iOS(onNavigateToContact: { contact in
                showFaucetModal = false
                onNavigate?(.contact(contact))
            })
                .environment(manager)
        }
        .sheet(isPresented: $showConnectionInfoSheet) {
            ConnectionInfoSheet(
                isOnSignet: manager.networkConfig?.networkType.lowercased() == "signet",
                networkName: manager.currentNetworkName,
                connectionStatus: manager.connectionStatus,
                onEnterRecoveryPhrase: manager.connectionStatus.readOnlyReason == .seedNotSynced ? {
                    showImportWalletSheet = true
                } : nil
            )
        }
        .sheet(isPresented: $showImportWalletSheet) {
            ImportWalletView_iOS(
                isMainnet: manager.networkConfig?.networkType.lowercased() != "signet",
                onBack: {
                    showImportWalletSheet = false
                },
                onWalletImported: {
                    showImportWalletSheet = false
                    Task {
                        // This device now holds the seed - record it in the registry and
                        // re-derive the wallet mode (stays read-only unless primary)
                        try? await ServiceContainer.shared.deviceRegistrationService.updateCurrentDeviceHasSeed(true)
                        await manager.initialize()
                    }
                }
            )
            .environment(manager)
        }
        .task {
            // Grace period fallback for connection status indicator
            // The indicator shows after wallet loads (hasLoadedOnce) OR this timeout expires
            // This provides immediate feedback on fast connections while handling slow/failed connections
            try? await Task.sleep(for: .seconds(connectionStatusGracePeriod))
            hasPassedStartupGracePeriod = true
        }
    }
    
    // Helper function to clear the active filter
    private func clearFilter() {
        onClearFilter?()
    }
}

// MARK: - Preference Key for Scroll Offset
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
