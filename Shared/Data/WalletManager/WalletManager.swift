//
//  WalletManager.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import Foundation
import SwiftUI
import SwiftData
import Bark
import ArkeUI
import OSLog

// MARK: - Export Data Structure
struct WalletExportData: Codable {
    let addresses: AddressData
    let balances: BalanceData
    let transactions: [ExportTransactionData]
    let vtxos: [VTXOModel]
    let utxos: [UTXOModel]
    let configuration: ArkConfigModel
    let arkInfo: ArkInfoModel
    let blockHeight: Int
    let exportTimestamp: Date
    
    struct AddressData: Codable {
        let arkAddress: String
        let onchainAddress: String
    }
    
    struct BalanceData: Codable {
        let arkBalance: ArkBalanceResponse?
        let onchainBalance: OnchainBalanceResponse?
        // Note: TotalBalanceModel is computed from the above, not stored
    }
    
    struct ExportTransactionData: Codable {
        let txid: String
        let movementId: Int?
        let recipientIndex: Int?
        let type: String
        let amount: Int
        let date: Date
        let status: String
        let address: String?
        let notes: String?
        
        init(from transactionModel: TransactionModel) {
            self.txid = transactionModel.txid
            self.movementId = transactionModel.movementId
            self.recipientIndex = transactionModel.recipientIndex
            // Convert enum to string
            self.type = transactionModel.type.displayName.lowercased()
            self.amount = transactionModel.amount
            self.date = transactionModel.date
            // Convert enum to string
            self.status = transactionModel.status.displayName.lowercased()
            self.address = transactionModel.address
            self.notes = transactionModel.notes
        }
    }
}

@MainActor
@Observable
class WalletManager {
    /// Logger for WalletManager operations
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "WalletManager")
    
    // MARK: - Coordinator State
    var isInitialized: Bool = false
    var error: String?
    var isRefreshing: Bool = false
    var hasLoadedOnce: Bool = false

    /// Whether this install has ever completed a refresh that reached the server.
    /// Persisted so app relaunches can trust an empty local cache: if we synced
    /// before and stored no transactions, the wallet is genuinely empty and the
    /// transaction list shows its empty state directly instead of a skeleton.
    var hasEverSyncedSuccessfully: Bool = UserDefaults.standard.bool(forKey: UserDefaults.initialSyncCompletedKey)
    
    /// Whether this device is in read-only mode (not the primary device)
    /// When true, wallet operations like send/receive are unavailable
    var isReadOnlyMode: Bool = false

    /// How the wallet entered the app during onboarding, if it did this session.
    /// Drives the first-sync UI: a freshly created wallet cannot have history, so the
    /// transaction list shows its empty state immediately (no skeleton), while an
    /// imported wallet may have history, so the skeleton shows from the moment the
    /// wallet UI appears until the first sync completes.
    enum FreshWalletOrigin {
        case created
        case imported
    }
    var freshWalletOrigin: FreshWalletOrigin?
    
    /// Counter for active refresh calls (used to track concurrent refresh attempts)
    private var activeRefreshCount: Int = 0
    
    /// Increments whenever persistent relationships change (contacts, tags, etc.)
    /// Views can observe this to refresh when relationship data changes
    var dataVersion: Int = 0
    
    /// Increments whenever transactions are updated
    /// Views can observe this to react to transaction list changes (e.g., refresh status indicators)
    var transactionVersion: Int = 0
    
    // MARK: - Services
    // WARNING: These properties are internal (not private) only to allow access from extension files.
    // DO NOT access these directly from outside WalletManager and its extensions.
    // Always use the public API methods instead.
    var wallet: BarkWalletProtocol?
    let taskManager = TaskDeduplicationManager()
    let cacheManager = WalletCacheManager()
    var modelContext: ModelContext?
    
    var transactionService: TransactionService?
    var balanceService: BalanceService?
    var readOnlyBalanceService: ReadOnlyBalanceService?
    var addressService: AddressService?
    var readOnlyAddressService: ReadOnlyAddressService?
    var walletOperationsService: WalletOperationsService?
    var processStateService: ProcessStateService?
    var exitProgressionService: ExitProgressionService?
    var roundProgressionService: RoundProgressionService?
    var vtxoRefreshService: VTXORefreshService?
    var lightningClaimService: LightningClaimService?
    var onchainTransactionService: OnchainTransactionService?
    var unifiedTransactionService: UnifiedTransactionService?  // Unified ark + onchain transactions
    var transactionLinkingService: TransactionLinkingService?  // Movement-onchain linking
    var relayRegistrationService: RelayRegistrationService?
    var walletNotificationService: WalletNotificationService?
    var feeRateService: FeeRateService?
    
    // Services from ServiceContainer (internal for extension access)
    var securityService: SecurityService { ServiceContainer.shared.securityService }
    var tagService: TagService { ServiceContainer.shared.tagService }
    var contactService: ContactService { ServiceContainer.shared.contactService }
    var contactAddressService: ContactAddressService { ServiceContainer.shared.contactAddressService }
    
    /// Cached exit VTXOs
    var cachedExitVtxos: [ExitVtxo] = []
    var exitVtxosCacheTime: Date?
    let exitCacheTimeout: TimeInterval = 30 // 30 seconds
    
    /// Cached exit statuses for linking
    var cachedExitStatuses: [String: ExitTransactionStatus] = [:]  // vtxoId -> status
    var exitStatusesCacheTime: Date?

    /// Exits currently blocked because fees can't be covered (vtxoId -> info)
    /// In-memory only for now; persistence lands with Exit_Blocked_State Phase 2
    var exitBlockedInfoByVtxoId: [String: ExitBlockedInfo] = [:]
    
    // MARK: - Network Info Properties
    var currentNetworkName: String {
        wallet?.currentNetworkName ?? "Unknown"
    }
    
    var isMainnet: Bool {
        wallet?.isMainnet ?? false
    }
    
    var networkConfig: NetworkConfig? {
        wallet?.networkConfig
    }
    
    // MARK: - Address & Balance Properties
    // Convenience properties that delegate to respective services
    
    var arkAddress: String {
        if isReadOnlyMode {
            return readOnlyAddressService?.arkAddress ?? ""
        } else {
            return addressService?.arkAddress ?? ""
        }
    }
    
    var onchainAddress: String {
        if isReadOnlyMode {
            return readOnlyAddressService?.onchainAddress ?? ""
        } else {
            return addressService?.onchainAddress ?? ""
        }
    }
    
    var arkBalance: ArkBalanceModel? {
        isReadOnlyMode ? readOnlyBalanceService?.arkBalance : balanceService?.arkBalance
    }
    
    var onchainBalance: OnchainBalanceModel? {
        isReadOnlyMode ? readOnlyBalanceService?.onchainBalance : balanceService?.onchainBalance
    }
    
    var totalBalance: TotalBalanceModel? {
        isReadOnlyMode ? readOnlyBalanceService?.totalBalance : balanceService?.totalBalance
    }
    

    
    // Note: Tag properties moved to WalletManager+Tags.swift
    // Note: Contact properties moved to WalletManager+Contacts.swift
    
    // MARK: - Formatted Balance Properties
    var formattedSpendableBalance: String {
        let spendableAmount = totalBalance?.totalSpendableSat ?? 0
        return BitcoinFormatter.shared.formatAmount(spendableAmount)
    }
    
    var formattedTotalBalance: String {
        let totalAmount = totalBalance?.grandTotalSat ?? 0
        return BitcoinFormatter.shared.formatAmount(totalAmount)
    }
    
    var formattedArkSpendableBalance: String {
        let arkSpendable = arkBalance?.spendableSat ?? 0
        return BitcoinFormatter.shared.formatAmount(arkSpendable)
    }
    
    var formattedOnchainSpendableBalance: String {
        let onchainSpendable = onchainBalance?.spendableSat ?? 0
        return BitcoinFormatter.shared.formatAmount(onchainSpendable)
    }
    
    // MARK: - State Check Properties
    var hasPendingBalance: Bool {
        isReadOnlyMode ? (readOnlyBalanceService?.hasPendingBalance ?? false) : (balanceService?.hasPendingBalance ?? false)
    }
    
    var hasSpendableBalance: Bool {
        isReadOnlyMode ? (readOnlyBalanceService?.hasSpendableBalance ?? false) : (balanceService?.hasSpendableBalance ?? false)
    }
    
    var isInitialLoading: Bool {
        guard !hasLoadedOnce && !(transactionService?.hasLoadedTransactions ?? false) else {
            return false
        }
        switch freshWalletOrigin {
        case .created:
            return false
        case .imported:
            return true
        case nil:
            return isRefreshing && !hasEverSyncedSuccessfully
        }
    }
    
    var isRefreshingWithData: Bool {
        isRefreshing && hasLoadedOnce
    }
    
    var arkInfo: ArkInfoModel? {
        balanceService?.arkInfo
    }
    
    var estimatedBlockHeight: Int? {
        balanceService?.estimatedBlockHeight
    }
    
    // MARK: - Initialization
    init(useMock: Bool = false, networkConfig: NetworkConfig? = nil) {
        #if DEBUG
        // Auto-enable mock mode if wallet opening is skipped for debugging
        let skipWalletOpen = ProcessInfo.processInfo.environment["SKIP_WALLET_OPEN"] == "1" ||
                             CommandLine.arguments.contains("-skipWalletOpen")
        let shouldUseMock = useMock || skipWalletOpen
        #else
        let shouldUseMock = useMock
        #endif
        
        // Load network config with priority:
        // 1. Explicit parameter (for testing/overrides)
        // 2. Saved config from iCloud/UserDefaults (via NetworkConfigPersistence)
        // 3. Default to mainnet (handled by NetworkConfigPersistence.load())
        let config: NetworkConfig
        if let explicitConfig = networkConfig {
            config = explicitConfig
            Self.logger.info("Using explicit network config: \(config.name)")
        } else {
            config = NetworkConfigPersistence.load()
            Self.logger.info("Network config loaded: \(config.name)")
        }
        
        setupWallet(useMock: shouldUseMock, networkConfig: config)
        initializeServices()
        
        // Set up notification observer for mailbox updates (iOS only)
        #if os(iOS)
        setupMailboxNotificationObserver()
        #endif
        
        // Observe migration notifications
        observeMigrationNotifications()
        
        #if DEBUG
        if skipWalletOpen && !useMock {
            Self.logger.debug("🎭 [DEBUG] Auto-enabled mock wallet for fast debugging")
        }
        #endif
    }
    
    /// Convenience initializer for different networks
    static func forNetwork(_ networkConfig: NetworkConfig, useMock: Bool = false) -> WalletManager {
        return WalletManager(useMock: useMock, networkConfig: networkConfig)
    }
    
    private func setupWallet(useMock: Bool, networkConfig: NetworkConfig) {
        #if DEBUG
        if useMock {
            wallet = MockBarkWallet()
            return
        }
        #endif
        wallet = BarkWalletFFI(networkConfig: networkConfig, securityService: securityService)
        if wallet == nil {
            Self.logger.error("❌ Failed to initialize BarkWalletFFI with network config: \(networkConfig.name)")
        } else {
            Self.logger.info("✅ Using BarkWalletFFI implementation")
        }
    }
    
    private func initializeServices() {
        guard let wallet = wallet else { return }
        
        // Initialize all services with shared task manager and cache manager
        transactionService = TransactionService(wallet: wallet, taskManager: taskManager)
        balanceService = BalanceService(wallet: wallet, taskManager: taskManager, cacheManager: cacheManager)
        feeRateService = FeeRateService(
            taskManager: taskManager,
            esploraBaseURL: { [weak self] in
                self?.networkConfig?.esploraBaseURL
            },
            maxRateSatPerVb: { [weak self] in
                guard let self, !self.isMainnet else { return nil }
                return FeeRateService.nonMainnetMaxRateSatPerVb
            }
        )
        // AddressService requires ModelContext, so it will be initialized later in setModelContext()
        addressService = nil
        walletOperationsService = WalletOperationsService(wallet: wallet, taskManager: taskManager)
        processStateService = ProcessStateService()
        
        // Initialize exit progression service
        exitProgressionService = ExitProgressionService(wallet: wallet)
        exitProgressionService?.setWalletManager(self)
        
        // Initialize round progression service
        roundProgressionService = RoundProgressionService(wallet: wallet)
        roundProgressionService?.setWalletManager(self)
        
        // Initialize VTXO auto-refresh service
        vtxoRefreshService = VTXORefreshService(wallet: wallet)
        vtxoRefreshService?.setWalletManager(self)
        
        // Initialize Lightning claim service
        // lightningClaimService = LightningClaimService(wallet: wallet)
        // lightningClaimService?.setWalletManager(self)
        
        // Initialize onchain transaction service
        onchainTransactionService = OnchainTransactionService(wallet: wallet, taskManager: taskManager)
        
        // Initialize transaction linking service (for movement-onchain linking)
        transactionLinkingService = TransactionLinkingService(walletManager: self)
        
        // Set linking service on transaction service
        transactionService?.setLinkingService(transactionLinkingService)
        
        // Initialize unified transaction service (merges ark + onchain)
        if let transactionService = transactionService,
           let onchainService = onchainTransactionService {
            unifiedTransactionService = UnifiedTransactionService(
                arkService: transactionService,
                onchainService: onchainService,
                walletManager: self
            )
            Self.logger.info("🔗 [WalletManager] UnifiedTransactionService initialized")
        }
        
        // Initialize relay registration service for APNs notifications
        #if os(iOS)
        let relayAPIToken = Bundle.main.object(forInfoDictionaryKey: "RelayAPIToken") as? String
        relayRegistrationService = RelayRegistrationService(relayAPIToken: relayAPIToken)
        relayRegistrationService?.onNeedsRefresh = { [weak self] in
            await self?.registerForPushNotifications()
        }
        Self.logger.info("📮 [WalletManager] RelayRegistrationService initialized\(relayAPIToken != nil ? " with API token" : " without API token")")
        #endif
        
        // Initialize wallet notification service for real-time movement updates
        walletNotificationService = WalletNotificationService(wallet: wallet)
        walletNotificationService?.setWalletManager(self)
        Self.logger.info("🔔 [WalletManager] WalletNotificationService initialized")
        
        // TagService and ContactService are initialized in init(), not here
        
        // Configure post-transaction callback
        walletOperationsService?.setTransactionCompletedCallback { [weak self] in
            // Refresh balances and reschedule VTXO notifications after transaction
            await self?.refreshAfterVTXOChange()
            // Increment backup transaction count after each transaction
            self?.processStateService?.incrementBackupTransactionCount()
            Self.logger.info("📊 DataVersion incremented to \(self?.dataVersion ?? 0) after transaction")
        }
    }
    
    func setModelContext(_ context: ModelContext, caller: String = #function, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        Self.logger.info("🔧 [WalletManager] 📞 setModelContext() CALLED")
        Self.logger.info("   ├─ From: \(fileName):\(line)")
        Self.logger.info("   └─ Function: \(caller)")
        
        self.modelContext = context
        
        // Initialize AddressService now that we have a ModelContext
        if isReadOnlyMode {
            // Read-only mode: Use ReadOnlyAddressService (no wallet required)
            if readOnlyAddressService == nil {
                readOnlyAddressService = ReadOnlyAddressService(modelContext: context)
                Self.logger.info("📍 [WalletManager] Initialized ReadOnlyAddressService for read-only mode")
            }
            // Initialize ReadOnlyBalanceService
            if readOnlyBalanceService == nil {
                readOnlyBalanceService = ReadOnlyBalanceService()
                Self.logger.info("💰 [WalletManager] Initialized ReadOnlyBalanceService for read-only mode")
            }
            readOnlyBalanceService?.setModelContext(context)
        } else if let wallet = wallet, addressService == nil {
            // Primary mode: Use full AddressService
            addressService = AddressService(wallet: wallet, taskManager: taskManager, modelContext: context)
            Self.logger.info("📍 [WalletManager] Initialized AddressService for primary mode")
        }
        
        transactionService?.setModelContext(context)
        transactionService?.setAddressService(addressService)  // ✅ Phase 3: Wire address service
        balanceService?.setModelContext(context)
        processStateService?.setModelContext(context)
        onchainTransactionService?.setModelContext(context)
        unifiedTransactionService?.setModelContext(context)  // Set context on unified service
        // Services are configured through ServiceContainer
        ServiceContainer.shared.configureServices(with: context)
        
        // Load exit cache from persistent storage (before wallet initialization)
        // This allows UI to render with cached exit data immediately
        Task {
            await loadExitCacheFromDisk()
        }
    }
    
    // MARK: - Coordination Methods
    func initialize(forceReadOnly: Bool? = nil, caller: String = #function, file: String = #file, line: Int = #line) async {
        let fileName = (file as NSString).lastPathComponent
        Self.logger.info("🔧 [WalletManager] 📞 initialize() CALLED")
        Self.logger.info("   ├─ Time: \(Date())")
        Self.logger.info("   ├─ From: \(fileName):\(line)")
        Self.logger.info("   └─ Function: \(caller)")
        if let forced = forceReadOnly {
            Self.logger.info("   ├─ forceReadOnly: \(forced)")
        }
        
        await taskManager.execute(key: "initialize") {
            Self.logger.info("🔧 [WalletManager] initialize execute at \(Date())")
            await self.performInitialization(forceReadOnly: forceReadOnly)
            Self.logger.info("🔧 [WalletManager] initialize execute done at \(Date())")
        }
    }
    
    /// Why this device is read-only. A missing seed beats not-primary as the
    /// explanation, because the seed is the actionable gap (wait for iCloud
    /// Keychain sync, or enter the recovery phrase).
    private func currentReadOnlyReason() -> ReadOnlyReason {
        securityService.hasMnemonic() ? .notPrimary : .seedNotSynced
    }

    /// Checks if this device is in read-only mode (not the primary device)
    private func checkReadOnlyMode() async {
        let deviceService = ServiceContainer.shared.deviceRegistrationService

        do {
            if let currentDevice = try await deviceService.getCurrentDevice() {
                isReadOnlyMode = !currentDevice.isPrimaryDevice

                // Update process state service with read-only mode status
                processStateService?.updateReadOnlyMode(isReadOnly: isReadOnlyMode, reason: isReadOnlyMode ? currentReadOnlyReason() : nil)
                
                if isReadOnlyMode {
                    Self.logger.info("🔒 [WalletManager] Device is in read-only mode (not primary device)")
                } else {
                    Self.logger.info("✅ [WalletManager] Device is primary - full wallet mode")
                }
            } else {
                // No device registration yet - assume primary (first device)
                isReadOnlyMode = false
                processStateService?.updateReadOnlyMode(isReadOnly: false)
                Self.logger.info("ℹ️ [WalletManager] No device registration found, assuming primary device")
            }
        } catch {
            // On error, assume primary to avoid blocking access
            isReadOnlyMode = false
            processStateService?.updateReadOnlyMode(isReadOnly: false)
            Self.logger.warning("⚠️ [WalletManager] Failed to check device status: \(error). Assuming primary device")
        }
    }
    
    private func performInitialization(forceReadOnly: Bool? = nil) async {
        Self.logger.info("🔧 [WalletManager] Starting initialization...")
        
        // Step 0a: CRITICAL - Check demotion status BEFORE opening wallet
        if await shouldBlockWalletAccess() {
            Self.logger.warning("⚠️ [WalletManager] Device has been demoted - switching to read-only mode")
            isReadOnlyMode = true
            processStateService?.updateReadOnlyMode(isReadOnly: true, reason: currentReadOnlyReason())
            
            // Initialize in read-only mode instead
            await initializeReadOnlyMode()
            return
        }
        
        // Step 0b: Determine read-only mode
        if let forced = forceReadOnly {
            // Caller explicitly specified read-only mode (from SecurityService detection)
            isReadOnlyMode = forced
            processStateService?.updateReadOnlyMode(isReadOnly: forced, reason: forced ? currentReadOnlyReason() : nil)
            Self.logger.info("✅ [WalletManager] Read-only mode set explicitly: \(forced)")
        } else {
            // Fallback: Check device registration (may have race conditions)
            await checkReadOnlyMode()
        }
        
        // Step 0c: CRITICAL - For primary devices, check if wallet backup needs to be restored
        if !isReadOnlyMode {
            await restoreWalletIfNeeded()
        }
        
        // Step 1: Branch based on read-only mode
        if isReadOnlyMode {
            await initializeReadOnlyMode()
        } else {
            await initializePrimaryMode()
        }
    }
    
    /// Initialize wallet in full mode (primary device with ASP connection)
    private func initializePrimaryMode() async {
        guard let wallet = wallet else {
            error = "Wallet not available"
            return
        }
        
        Self.logger.info("🔧 [WalletManager] Initializing in PRIMARY mode (full wallet access)")
        
        // Step 1: Explicitly open the wallet if it exists (FFI only)
        if let ffiWallet = wallet as? BarkWalletFFI {
            let opened = await ffiWallet.openWalletIfNeeded()
            if !opened {
                if securityService.hasMnemonic() {
                    // A seed exists but the wallet database could not be opened -
                    // this is an error state (e.g. network/database mismatch),
                    // not a first-launch situation
                    Self.logger.error("❌ Wallet failed to open despite mnemonic in Keychain")
                    error = "Wallet could not be opened. Please restart the app or contact support."
                } else {
                    Self.logger.info("ℹ️ No existing wallet to open - user needs to create or import")
                }
                isInitialized = false
                return
            }
            Self.logger.info("✅ Wallet opened successfully")
            
            // Start the daemon for background operations (syncs, exit progression, etc.)
            do {
                try await ffiWallet.runDaemon()
                Self.logger.info("🤖 Wallet daemon started")
            } catch {
                Self.logger.warning("⚠️ Failed to start wallet daemon: \(error.localizedDescription)")
                // Non-fatal - continue with manual background services
            }
        }
        
        // Step 2: Check wallet existence using SecurityService (Keychain)
        let walletExists = securityService.hasMnemonic()
        
        if walletExists {
            Self.logger.info("✅ Wallet mnemonic found in Keychain - wallet exists on \(self.currentNetworkName)")
            isInitialized = true
            
            #if DEBUG
            Self.logger.debug("📍 [ADDRESS TRACE] performInitialization() about to call refresh()")
            Self.logger.debug("   This will trigger address generation")
            #endif
            
            // Load all wallet data for existing wallet
            await refresh()
            
            // Refresh exit cache now that wallet is initialized
            // This updates the persistent cache loaded earlier with fresh data
            await refreshExitCache()
            
            // Create default tags if needed (after data is loaded)
            await createDefaultTagsIfNeeded()
            
            if !isMainnet {
                // Create default contacts if needed (after data is loaded)
                await createDefaultContactsIfNeeded()
            }
            
            // Ensure arkInfo is loaded before starting services that depend on it
            if arkInfo == nil {
                Self.logger.info("ℹ️ [WalletManager] arkInfo not yet loaded, caching now...")
                await balanceService?.cacheArkInfoIfNeeded()
                if arkInfo != nil {
                    Self.logger.info("✅ [WalletManager] arkInfo cached successfully")
                } else {
                    Self.logger.warning("⚠️ [WalletManager] Failed to cache arkInfo")
                }
            }
            
            // Start background progression services
            exitProgressionService?.start()
            roundProgressionService?.start()
            vtxoRefreshService?.start()
            lightningClaimService?.start()
            
            // Start wallet notification service for real-time updates
            if let transactionService = transactionService {
                walletNotificationService?.setTransactionService(transactionService)
                walletNotificationService?.start()
            }
            
            // Register for push notifications now that wallet is initialized
            #if os(iOS)
            Task {
                await registerForPushNotifications()
            }
            #endif
        } else {
            Self.logger.warning("⚠️ No mnemonic found in Keychain - wallet needs to be created or imported on \(self.currentNetworkName)")
            isInitialized = false
        }
    }
    
    /// Initialize wallet in read-only mode (secondary device with CloudKit sync only)
    private func initializeReadOnlyMode() async {
        Self.logger.info("🔒 [WalletManager] Initializing in READ-ONLY mode (CloudKit sync only)")
        
        // Initialize ReadOnlyAddressService if not already done
        // (It might not exist if setModelContext was called before isReadOnlyMode was set)
        if readOnlyAddressService == nil, let context = modelContext {
            readOnlyAddressService = ReadOnlyAddressService(modelContext: context)
            Self.logger.info("📍 [WalletManager] Initialized ReadOnlyAddressService in initializeReadOnlyMode")
        }
        
        // Initialize ReadOnlyBalanceService if not already done
        if readOnlyBalanceService == nil {
            readOnlyBalanceService = ReadOnlyBalanceService()
            if let context = modelContext {
                readOnlyBalanceService?.setModelContext(context)
            }
            Self.logger.info("💰 [WalletManager] Initialized ReadOnlyBalanceService in initializeReadOnlyMode")
        }
        
        // Check if wallet data exists via CloudKit sync
        // We don't check for local wallet file or mnemonic since this is a secondary device
        let deviceService = ServiceContainer.shared.deviceRegistrationService
        
        do {
            // Verify we have a valid device registration with wallet info
            if let currentDevice = try await deviceService.getCurrentDevice(),
               !currentDevice.walletHash.isEmpty {
                Self.logger.info("✅ [WalletManager] Device registered with wallet hash - enabling read-only access")
                isInitialized = true
                
                // Create default tags if needed (uses CloudKit)
                await createDefaultTagsIfNeeded()
                
                if !isMainnet {
                    // Create default contacts if needed (uses CloudKit)
                    await createDefaultContactsIfNeeded()
                }
                
                // Load addresses from database (CloudKit-synced)
                await readOnlyAddressService?.loadAddresses()
                Self.logger.info("📍 [WalletManager] Loaded addresses from database in read-only mode")
                
                Self.logger.info("✅ [WalletManager] Read-only mode initialized successfully")
            } else {
                Self.logger.info("ℹ️ [WalletManager] No wallet data available yet - user needs to set up wallet on primary device")
                isInitialized = false
            }
        } catch {
            Self.logger.error("❌ [WalletManager] Failed to initialize read-only mode: \(error)")
            isInitialized = false
            self.error = "Failed to initialize read-only mode: \(error.localizedDescription)"
        }
    }
    
    /// Centralized refresh - orchestrates all services
    func refresh(caller: String = #function, file: String = #file, line: Int = #line) async {
        let fileName = (file as NSString).lastPathComponent
        Self.logger.info("🔄 [WalletManager] 📞 refresh() CALLED")
        Self.logger.info("   ├─ From: \(fileName):\(line)")
        Self.logger.info("   └─ Function: \(caller)")
        
        // Increment counter and set isRefreshing if this is the first active call
        activeRefreshCount += 1
        let refreshNumber = activeRefreshCount
        Self.logger.info("🔄 [REFRESH STATE] Active refresh count: \(self.activeRefreshCount), refresh #\(refreshNumber)")
        
        if activeRefreshCount == 1 {
            Self.logger.info("🔄 [REFRESH STATE] Setting isRefreshing = true (first active refresh)")
            isRefreshing = true
        } else {
            Self.logger.info("🔄 [REFRESH STATE] Additional concurrent refresh call (not changing isRefreshing)")
        }
        
        defer {
            // Decrement counter and clear isRefreshing only when all calls complete
            activeRefreshCount -= 1
            Self.logger.info("🔄 [REFRESH STATE] Refresh #\(refreshNumber) completed. Active count now: \(self.activeRefreshCount)")
            
            if activeRefreshCount == 0 {
                Self.logger.info("🔄 [REFRESH STATE] Setting isRefreshing = false (all refreshes complete)")
                isRefreshing = false
            }
        }
        
        await taskManager.execute(key: "refresh") {
            await self.performRefresh()
        }
        
        Self.logger.info("🔄 [REFRESH STATE] refresh() #\(refreshNumber) returning")
    }
    
    private func performRefresh() async {
        Self.logger.info("WalletManager.performRefresh")
        
        #if DEBUG
        Self.logger.debug("📍 [ADDRESS TRACE] WalletManager.performRefresh() starting address load")
        Self.logger.debug("   📞 Called from:")
        Thread.callStackSymbols.prefix(6).enumerated().forEach { index, symbol in
            Self.logger.debug("      \(index): \(symbol)")
        }
        #endif
        
        defer { 
            hasLoadedOnce = true
        }
        
        guard wallet != nil else { 
            error = "Wallet not initialized"
            return 
        }
        
        // Track if any server communication succeeded
        var anyServerCallSucceeded = false
        
        // Step 1: Ensure server connection is fresh
        Self.logger.info("🔄 [Refresh] Step 1: Refreshing server connection...")
        await refreshServer()
        // Note: refreshServer() doesn't throw, it sets self.error on failure
        if error != nil {
            Self.logger.warning("⚠️ [Refresh] Server refresh failed, but continuing with data refresh")
            // We don't return here - we'll try to continue with the refresh
        } else {
            anyServerCallSucceeded = true
            Self.logger.info("✅ [Refresh] Server connection successful")
        }
        
        // Step 2: Sync wallet state with ASP server
        Self.logger.info("🔄 [Refresh] Step 2: Syncing wallet state with server...")
        do {
            try await sync()
            anyServerCallSucceeded = true
            Self.logger.info("✅ [Refresh] Wallet state synced successfully")
        } catch {
            Self.logger.warning("⚠️ [Refresh] Wallet sync failed: \(error)")
            // We'll continue with the refresh even if sync fails
            // The user's local cache might still be usable
        }
        
        // Step 3: Coordinate service refreshes in parallel where possible
        Self.logger.info("🔄 [Refresh] Step 3: Refreshing wallet data (balances, addresses, transactions, block height)...")
        await withTaskGroup(of: Void.self) { group in
            // Balance service handles its own coordination
            group.addTask { 
                await self.balanceService?.refreshAllBalances() 
            }
            
            // Address loading
            group.addTask {
                #if DEBUG
                Self.logger.debug("📍 [ADDRESS TRACE] Task group calling addressService.loadAddresses()")
                #endif
                await self.addressService?.loadAddresses() 
            }
            
            // Transaction refresh (Ark transactions)
            group.addTask { 
                await self.transactionService?.refreshTransactions() 
            }
            
            // Onchain transaction refresh (BDK transactions)
            group.addTask {
                await self.onchainTransactionService?.refreshTransactions()
            }
            
            // Block height fetch (needed for VTXO expiry calculations)
            group.addTask {
                do {
                    _ = try await self.getLatestBlockHeight()
                } catch {
                    Self.logger.warning("⚠️ [Refresh] Failed to fetch block height: \(error)")
                }
            }

            // Onchain fee rate refresh (best effort, keeps last-known-good on failure)
            group.addTask {
                await self.feeRateService?.refresh()
            }
        }
        
        // Merge transactions from both sources after refresh
        Self.logger.info("🔄 [Refresh] Step 3.1: Merging ark + onchain transactions...")
        await unifiedTransactionService?.mergeTransactions()
        
        // Check for errors from services and log them for debugging
        if let addressError = addressService?.error {
            Self.logger.warning("⚠️ [Refresh] AddressService error: \(addressError)")
            self.error = addressError
        }
        else if let transactionError = transactionService?.error {
            Self.logger.warning("⚠️ [Refresh] TransactionService error: \(transactionError)")
            self.error = transactionError
        }
        else if let balanceError = balanceService?.error {
            Self.logger.warning("⚠️ [Refresh] BalanceService error: \(balanceError)")
            self.error = balanceError
        }
        else if let onchainTxError = onchainTransactionService?.error {
            Self.logger.warning("⚠️ [Refresh] OnchainTransactionService error: \(onchainTxError)")
            self.error = onchainTxError
        } else {
            error = nil
        }
        
        // Step 4: After successful refresh, update process state service and exit cache
        Self.logger.info("🔄 [Refresh] Step 4: Updating process states and exit cache...")
        await refreshProcessStates(isConnected: anyServerCallSucceeded)
        await refreshExitCache()
        
        if error == nil {
            Self.logger.info("✅ All wallet data refreshed successfully on \(self.currentNetworkName)")
        } else {
            Self.logger.warning("⚠️ Wallet refresh completed with errors on \(self.currentNetworkName)")
        }

        if anyServerCallSucceeded && !hasEverSyncedSuccessfully {
            hasEverSyncedSuccessfully = true
            UserDefaults.standard.set(true, forKey: UserDefaults.initialSyncCompletedKey)
            Self.logger.info("📌 First successful sync recorded - future launches will trust an empty transaction cache")
        }
        
        // CRITICAL: Always increment dataVersion to trigger UI updates, even if there were errors
        // This ensures the UI shows whatever data we did manage to fetch
        dataVersion += 1
        Self.logger.info("📊 DataVersion incremented to \(self.dataVersion) after refresh (triggers UI update)")
    }
    
    /// Refresh process states after wallet data is loaded
    private func refreshProcessStates(isConnected: Bool) async {
        guard let processStateService = processStateService else { return }
        
        // Get VTXOs from wallet operations
        let vtxos: [VTXOModel]
        do {
            vtxos = try await getVTXOs()
        } catch {
            Self.logger.warning("⚠️ Could not fetch VTXOs for process state update: \(error)")
            vtxos = []
        }
        
        let blockHeight = balanceService?.estimatedBlockHeight ?? 0
        
        // Connection status is passed in based on actual server communication success
        let connectionError = error
        
        // Update all process states
        processStateService.refreshAll(
            vtxos: vtxos,
            blockHeight: blockHeight,
            isConnected: isConnected,
            connectionError: connectionError
        )
    }
    
    // MARK: - Extension References
    // See WalletManager+Tags.swift for tag operations
    // See WalletManager+Contacts.swift for contact operations
    // See WalletManager+ContactAddresses.swift for contact address operations
    // See WalletManager+Transactions.swift for transaction operations
    
    // MARK: - Preview Support (Remove when no longer needed)
    /// Set model context for preview environments
    func setPreviewContext(_ context: ModelContext) {
        ServiceContainer.shared.configureServices(with: context)
    }
    
    // See WalletManager+Operations.swift for wallet operations
    // See WalletManager+Fees.swift for fee estimation
    // See WalletManager+Wallet.swift for wallet lifecycle
    // See WalletManager+Lightning.swift for Lightning operations
    // See WalletManager+Exits.swift for exit operations
    // See WalletManager+Refresh.swift for refresh helpers
    // See WalletManager+Export.swift for data export
    // See WalletManager+Data.swift for data retrieval
    // See WalletManager+ProcessState.swift for process state
    // See WalletManager+CustomCommands.swift for custom commands
    // See WalletManager+Notifications.swift for push notifications (iOS)
    // See WalletManager+PaymentDestination.swift for payment context helpers
    
    // MARK: - Device Migration Support
    
    /// Close wallet gracefully for migration (device demotion)
    /// This is a lightweight version of closeWallet() that:
    /// - Stops all background services
    /// - Unregisters from push notifications (iOS)
    /// - Backs up and shuts down wallet FFI
    /// - PRESERVES SwiftData (transactions, tags, contacts)
    /// 
    /// Unlike closeWallet(), this does NOT clear transaction history
    /// because secondary devices need to display synced transaction data
    func closeWalletForMigration() async throws {
        guard let wallet = wallet else {
            throw BarkErrorArke.commandFailed("Wallet not initialized")
        }
        
        Self.logger.info("🔄 [WalletManager] Closing wallet for migration...")
        
        // Step 1: Reset manager state (lightweight - preserves SwiftData)
        Self.logger.info("Step 1: Resetting manager state (preserving SwiftData)...")
        await resetManagerStateForMigration()

        // Step 2: Switch to read-only mode immediately
        Self.logger.info("Step 2: Switching to read-only mode...")
        isReadOnlyMode = true
        processStateService?.updateReadOnlyMode(isReadOnly: true, reason: currentReadOnlyReason())
        Self.logger.info("🔒 [WalletManager] Device switched to read-only mode")
        
        // Step 3: Unregister from push notifications
        #if os(iOS)
        Self.logger.info("Step 3: Unregistering from push notifications...")
        await unregisterFromPushNotifications()
        #endif

        // Step 4: Give services time to settle
        Self.logger.info("Step 4: Waiting for services to settle...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Step 5: Shutdown wallet (FFI cleanup, backup, resource release)
        Self.logger.info("Step 5: Shutting down wallet FFI...")
        if let ffiWallet = wallet as? BarkWalletFFI {
            await ffiWallet.shutdownWallet()
        } else {
            // Mock wallet - just clear the reference
            Self.logger.debug("Mock wallet detected - skipping FFI shutdown")
        }
        
        // Clear service references
        walletOperationsService = nil
        exitProgressionService = nil
        roundProgressionService = nil
        vtxoRefreshService = nil
        lightningClaimService = nil
        onchainTransactionService = nil
        unifiedTransactionService = nil
        transactionLinkingService = nil
        relayRegistrationService = nil
        walletNotificationService = nil
        
        Self.logger.info("✅ Wallet closed successfully for migration (SwiftData preserved)")
    }
    
    /// Observe migration notifications
    private func observeMigrationNotifications() {
        // Demotion notification
        NotificationCenter.default.addObserver(
            forName: .deviceDemotedFromPrimary,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.closeWalletForMigration()
            }
        }
        
        // Promotion notification
        NotificationCenter.default.addObserver(
            forName: .devicePromotedToPrimary,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Re-initialize as primary device
                // This will:
                // 1. Open the wallet (via openWalletIfNeeded)
                // 2. Restore wallet from backup if needed (via restoreWalletIfNeeded)
                // 3. Load all wallet data (via refresh)
                // 4. Start all background services (exit, round, vtxo progression)
                // 5. Start wallet notification service
                // 6. Register for push notifications (iOS)
                await self?.initialize(forceReadOnly: false)
            }
        }
    }
    
    /// Multi-layered check if device has been demoted
    /// This runs BEFORE wallet initialization to prevent race conditions
    func shouldBlockWalletAccess() async -> Bool {
        guard let deviceId = try? ServiceContainer.shared.deviceRegistrationService.getOrCreateDeviceId() else {
            return false
        }
        
        // Layer 1: Check local UserDefaults (instant, <1ms)
        if UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted") {
            Self.logger.info("🛑 [WalletManager] Blocked: UserDefaults indicates demotion")
            return true
        }
        
        // Layer 2: Check iCloud KV store (local cache).
        // Access off the main actor — the first touch of NSUbiquitousKeyValueStore.default
        // can block on I/O, which on the launch path can trip the watchdog (SIGKILL 0xdead10cc).
        let kvIndicatesDemotion = await Task.detached(priority: .utility) { () -> Bool in
            let kvStore = NSUbiquitousKeyValueStore.default
            let isPrimaryInKVStore = kvStore.bool(forKey: "device_\(deviceId)_isPrimary")
            // Check if key exists (bool returns false for both "false" and "doesn't exist")
            return kvStore.object(forKey: "device_\(deviceId)_isPrimary") != nil && !isPrimaryInKVStore
        }.value
        if kvIndicatesDemotion {
            Self.logger.info("🛑 [WalletManager] Blocked: iCloud KV store indicates demotion")
            return true
        }
        
        // Layer 3: Check CloudKit via device registration (no network call, uses local cache)
        if let device = try? await ServiceContainer.shared.deviceRegistrationService.getCurrentDevice(),
           !device.isPrimaryDevice {
            Self.logger.info("🛑 [WalletManager] Blocked: CloudKit cache indicates demotion")
            return true
        }
        
        // All checks passed - allow wallet access
        return false
    }
    
    /// Restores wallet from iCloud backup if needed
    /// Called when device becomes primary and needs to sync with latest wallet state
    /// CRITICAL: Compares timestamps to ensure we always use the newest data
    private func restoreWalletIfNeeded() async {
        guard let ffiWallet = wallet as? BarkWalletFFI else {
            Self.logger.warning("⚠️ [WalletManager] Cannot restore - wallet is not BarkWalletFFI")
            return
        }

        // An open wallet is authoritative - restoring a backup over it would
        // shut it down and pair the keychain mnemonic with a foreign database
        // (e.g. right after wallet creation, when a stale backup may still
        // exist in iCloud from a previously deleted wallet)
        guard ffiWallet.wallet == nil else {
            Self.logger.info("ℹ️ [WalletManager] Wallet is open - skipping backup restore check")
            return
        }

        let walletFileExists = WalletBackupService.hasLocalWalletFile()
        let hasBackup = ffiWallet.hasBackupAvailable()
        
        if !walletFileExists {
            // No local file - restore from backup if available
            if hasBackup {
                Self.logger.info("📥 [WalletManager] No local wallet file - restoring from backup")
                
                do {
                    let restored = try await ffiWallet.restoreWalletFromBackup()
                    if restored {
                        Self.logger.info("✅ [WalletManager] Wallet state restored from backup")
                    } else {
                        Self.logger.warning("⚠️ [WalletManager] Failed to restore wallet from backup")
                    }
                } catch {
                    Self.logger.error("❌ [WalletManager] Error restoring wallet: \(error.localizedDescription)")
                }
            } else {
                Self.logger.info("ℹ️ [WalletManager] No backup available - wallet will start fresh")
            }
        } else if hasBackup {
            // Both local file and backup exist - compare timestamps to use the newest
            let localDate = WalletBackupService.getLocalWalletFileModificationDate()
            let backupInfo = await ffiWallet.getBackupInfo()
            
            if let localDate = localDate,
               let backupDate = backupInfo?.lastBackupDate {
                
                if backupDate > localDate {
                    Self.logger.warning("⚠️ [WalletManager] Backup is newer than local file")
                    Self.logger.warning("   Local:  \(localDate)")
                    Self.logger.warning("   Backup: \(backupDate)")
                    Self.logger.warning("   Restoring from backup to prevent data loss")
                    
                    do {
                        let restored = try await ffiWallet.restoreWalletFromBackup()
                        if restored {
                            Self.logger.info("✅ [WalletManager] Restored newer backup over stale local file")
                        } else {
                            Self.logger.error("❌ [WalletManager] Failed to restore newer backup")
                        }
                    } catch {
                        Self.logger.error("❌ [WalletManager] Error restoring backup: \(error.localizedDescription)")
                    }
                } else {
                    Self.logger.info("✅ [WalletManager] Local wallet file is up to date")
                    Self.logger.debug("   Local:  \(localDate)")
                    Self.logger.debug("   Backup: \(backupDate)")
                }
            } else {
                Self.logger.warning("⚠️ [WalletManager] Could not determine file timestamps - using local file")
            }
        } else {
            Self.logger.info("ℹ️ [WalletManager] Local wallet file exists, no backup available")
        }
    }
}

enum BarkErrorArke: Swift.Error, LocalizedError {
    case binaryNotFound
    case commandFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "bark binary not found in app bundle"
        case .commandFailed(let message):
            return message
        }
    }
}

