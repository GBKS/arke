//
//  MakePrimaryFlowView_iOS.swift
//  Arké
//
//  Flow 4.3 (Device_Linking.md): "Make this device primary", in three
//  branches. The flow has no state of its own beyond what the screen shows;
//  every step is derived from the registry, the KVS flag of the current
//  primary, and the iCloud Drive backup slot, so leaving and coming back is
//  harmless.
//

import SwiftUI
import ArkeUI

struct MakePrimaryFlowView_iOS: View {
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    @Environment(WalletManager.self) private var walletManager
    @Environment(\.deviceRegistrationService) private var deviceService
    @Environment(\.securityService) private var securityService

    private enum Step: Equatable {
        case loading
        case seedMissing
        case branchQuestion(primary: PrimaryInfo)
        case handover(primary: PrimaryInfo)
        case takeover(primary: PrimaryInfo)
        case direct
        case promoting
        case done
    }

    private struct PrimaryInfo: Equatable {
        let deviceId: String
        let name: String
        let lastSeenAt: Date
    }

    @State private var step: Step = .loading
    @State private var readiness: HandoverReadiness = .waitingForHandover
    @State private var waitTimedOut = false
    @State private var backupDate: Date?
    @State private var errorMessage: String?
    @State private var showSeedEntry = false
    @State private var waitTask: Task<Void, Never>?

    private static let handoverTimeout: Duration = .seconds(240)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                content
            }
            .padding(.vertical)
            .navigationTitle(L10n.sectionDeviceRole)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.buttonCancel) {
                        waitTask?.cancel()
                        isPresented = false
                    }
                    .disabled(step == .promoting)
                }
            }
        }
        .interactiveDismissDisabled(step == .promoting)
        .task { await load() }
        .onDisappear { waitTask?.cancel() }
        .sheet(isPresented: $showSeedEntry) {
            SeedEntrySheet_iOS(
                networkConfig: walletManager.networkConfig ?? .mainnet,
                onCancel: { showSeedEntry = false },
                onSeedSaved: {
                    showSeedEntry = false
                    Task { await load() }
                }
            )
            .environment(walletManager)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .loading:
            ProgressView()
                .frame(maxHeight: .infinity)

        case .seedMissing:
            header(icon: "key", title: String(localized: "make_primary_seed_title", defaultValue: "This device doesn't have the wallet key yet"))
            explanation(String(localized: "make_primary_seed_help",
                               defaultValue: "The key hasn't reached this device through iCloud Keychain. Enter the recovery phrase to continue, or wait for iCloud and try again."))
            Spacer()
            errorLine
            VStack(spacing: 12) {
                ArkeGlassButton(String(localized: "link_button_enter_phrase", defaultValue: "Enter Recovery Phrase")) {
                    showSeedEntry = true
                }
                ArkeGlassButton(String(localized: "link_button_check_again", defaultValue: "Check Again"), variant: .secondary) {
                    Task { await load() }
                }
            }
            .padding(.horizontal)

        case .branchQuestion(let primary):
            header(icon: "arrow.up", title: String(format: String(localized: "make_primary_question %@", defaultValue: "Do you still have %@?"), primary.name))
            explanation(String(format: String(localized: "make_primary_question_help %@ %@",
                                              defaultValue: "%@ is the primary device, last seen %@. Spending moves to this device either way; the question is only how."),
                               primary.name, primary.lastSeenAt.formatted(.relative(presentation: .named))))
            Spacer()
            VStack(spacing: 12) {
                ArkeGlassButton(String(localized: "make_primary_have_it", defaultValue: "Yes, I Have It")) {
                    startHandover(primary)
                }
                ArkeGlassButton(String(localized: "make_primary_lost_it", defaultValue: "No, I Lost It"), variant: .secondary) {
                    step = .takeover(primary: primary)
                }
            }
            .padding(.horizontal)

        case .handover(let primary):
            header(icon: "arrow.left.arrow.right", title: String(format: String(localized: "make_primary_handover_title %@", defaultValue: "Hand over from %@"), primary.name))
            explanation(String(format: String(localized: "make_primary_handover_instruction %@",
                                              defaultValue: "On %@, open Arké, go to Settings › Devices and tap Make This Device Secondary. Keep both devices online."),
                               primary.name))
            handoverStatus(primary)
            Spacer()
            errorLine
            VStack(spacing: 12) {
                ArkeGlassButton(String(localized: "button_make_device_primary", defaultValue: "Make Device Primary"),
                                isLoading: step == .promoting) {
                    Task { await promote(takeoverOf: nil) }
                }
                .disabled(readiness != .ready)
                if waitTimedOut {
                    ArkeGlassButton(String(localized: "make_primary_dont_have_it", defaultValue: "I Don't Have It Anymore"), variant: .secondary) {
                        waitTask?.cancel()
                        step = .takeover(primary: primary)
                    }
                }
            }
            .padding(.horizontal)

        case .takeover(let primary):
            header(icon: "exclamationmark.triangle", title: String(format: String(localized: "make_primary_takeover_title %@", defaultValue: "Take over from %@"), primary.name))
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: String(localized: "make_primary_takeover_security %@",
                                           defaultValue: "If someone could unlock %@, they can read this wallet's recovery phrase. Consider moving your funds to a new wallet afterwards."),
                            primary.name))
                Text(takeoverBackupLine(primary))
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            Spacer()
            errorLine
            ArkeGlassButton(String(localized: "make_primary_take_over", defaultValue: "Take Over"), isLoading: step == .promoting) {
                Task { await promote(takeoverOf: primary) }
            }
            .padding(.horizontal)

        case .direct:
            header(icon: "arrow.up", title: String(localized: "settings_make_this_device_primary", defaultValue: "Make This Device Primary?"))
            explanation(String(localized: "make_primary_direct_help",
                               defaultValue: "No device is primary right now. This device will become the primary device, able to send and receive payments."))
            if let backupDate {
                Text(String(format: String(localized: "make_primary_backup_date %@", defaultValue: "The wallet continues from the backup made %@."),
                            backupDate.formatted(.relative(presentation: .named))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            errorLine
            ArkeGlassButton(String(localized: "settings_make_primary", defaultValue: "Make Primary"), isLoading: step == .promoting) {
                Task { await promote(takeoverOf: nil) }
            }
            .padding(.horizontal)

        case .promoting:
            header(icon: "arrow.up", title: String(localized: "make_primary_opening", defaultValue: "Opening the wallet…"))
            ProgressView()
            Spacer()

        case .done:
            header(icon: "checkmark", title: String(localized: "make_primary_done", defaultValue: "This device is now primary"))
            Spacer()
        }
    }

    // MARK: - Pieces

    private func header(icon: String, title: String) -> some View {
        VStack(spacing: 20) {
            ArkeCircularIcon(icon: Image(systemName: icon))
            Text(title)
                .font(.system(.title, design: .serif))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var errorLine: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(Color.Arke.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func handoverStatus(_ primary: PrimaryInfo) -> some View {
        HStack(spacing: 8) {
            if readiness != .ready { ProgressView() }
            Text(handoverStatusText(primary))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        if waitTimedOut {
            Text(String(format: String(localized: "make_primary_handover_timeout %@",
                                       defaultValue: "Still waiting. Make sure %@ is online with Arké open."), primary.name))
                .font(.callout)
                .foregroundStyle(Color.Arke.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func handoverStatusText(_ primary: PrimaryInfo) -> String {
        switch readiness {
        case .waitingForHandover:
            return String(format: String(localized: "make_primary_status_waiting %@", defaultValue: "Waiting for %@ to hand over…"), primary.name)
        case .handoverStarted:
            return String(localized: "make_primary_status_started", defaultValue: "Handover started. Waiting for the device list to update…")
        case .waitingForBackup:
            return String(localized: "make_primary_status_backup", defaultValue: "Waiting for the latest backup to arrive…")
        case .ready:
            return String(localized: "make_primary_status_ready", defaultValue: "Latest backup received.")
        }
    }

    private func takeoverBackupLine(_ primary: PrimaryInfo) -> String {
        if let backupDate {
            return String(format: String(localized: "make_primary_takeover_backup %@ %@",
                                         defaultValue: "This device continues from the backup %@ made %@. Payments received since then appear after the first sync; amounts sent from that device since then are reconciled with the server."),
                          primary.name, backupDate.formatted(.relative(presentation: .named)))
        }
        return String(localized: "make_primary_takeover_no_backup",
                      defaultValue: "No backup from that device has reached iCloud. The wallet rebuilds from the server after you take over.")
    }

    // MARK: - Behaviour

    /// Step 0 and the branch: derived from the seed and the registry
    private func load() async {
        errorMessage = nil
        guard securityService.hasMnemonic() else {
            step = .seedMissing
            return
        }
        backupDate = await (walletManager.wallet as? BarkWalletFFI)?.getBackupInfo()?.lastBackupDate

        // Same scope as `promoteThisDeviceToPrimary`: this device's own row's
        // wallet hash, not the KVS hash (which can be nil and would widen the
        // lookup to other test wallets' primaries; review 2026-11-14, F7)
        let ownRow = try? await deviceService.getCurrentDevice()
        let hash = ownRow?.walletHash ?? deviceService.accountWalletHash()
        if let primary = try? await deviceService.getPrimaryDevice(walletHash: hash),
           primary.deviceId != ((try? deviceService.getOrCreateDeviceId()) ?? "") {
            let name = primary.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let info = PrimaryInfo(
                deviceId: primary.deviceId,
                name: name.isEmpty ? String(localized: "make_primary_unnamed_device", defaultValue: "the primary device") : name,
                lastSeenAt: primary.lastSeenAt
            )
            step = .branchQuestion(primary: info)
        } else {
            step = .direct
        }
    }

    /// Branch A: watch the other device's flag and row, then the backup slot
    private func startHandover(_ primary: PrimaryInfo) {
        step = .handover(primary: primary)
        readiness = .waitingForHandover
        waitTimedOut = false
        waitTask?.cancel()
        waitTask = Task { @MainActor in
            let monitor = BackupSlotMonitor()
            let deadline = ContinuousClock.now.advanced(by: Self.handoverTimeout)
            while !Task.isCancelled {
                // Pull the KVS cache before reading the other device's flag
                NSUbiquitousKeyValueStore.default.synchronize()
                let flag = deviceService.otherDevicePrimaryFlag(deviceId: primary.deviceId)
                await deviceService.loadRegisteredDevices()
                let row = deviceService.registeredDevices.first { $0.deviceId == primary.deviceId }
                let rowIsPrimary = row?.isPrimaryDevice ?? false

                // The backup must postdate the demotion. Both dates come from
                // the old primary's clock: `demotedAt` is written by it, and
                // the slot's date is stamped by its backup pass, so no skew
                // tolerance is needed and a periodic backup from before the
                // demotion never counts (review 2026-11-14, F2 and F5).
                var backupReady = false
                if !rowIsPrimary, let demotedAt = row?.demotedAt, let snapshot = await monitor.currentSnapshot() {
                    if BackupSlotMonitor.needsDownload(snapshot) { monitor.requestDownload() }
                    backupReady = BackupSlotMonitor.downloadedBackupIsNewer(snapshot, than: demotedAt)
                }
                readiness = HandoverReadiness.evaluate(otherFlag: flag, otherRowIsPrimary: rowIsPrimary, backupReady: backupReady)
                if readiness == .ready { return }
                if ContinuousClock.now > deadline { waitTimedOut = true }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Promote (branch A, C) or take over (branch B), then wait for the
    /// wallet to open as primary. On a takeover, reconcile stale spend state.
    private func promote(takeoverOf lost: PrimaryInfo?) async {
        waitTask?.cancel()
        errorMessage = nil
        let previous = step
        step = .promoting

        // Branches B and C never waited on the slot. A device that has not
        // downloaded it holds only a placeholder, which `restoreWalletIfNeeded`
        // reads as "no backup" and then opens from the seed alone (review
        // 2026-11-14, F4). Make the latest version local first; no slot item
        // at all means there is genuinely nothing to restore.
        if case .handover = previous {} else {
            let monitor = BackupSlotMonitor()
            if await monitor.currentSnapshot() != nil {
                let local = await monitor.ensureSlotIsLocal(timeout: .seconds(60))
                if !local {
                    errorMessage = String(localized: "make_primary_error_backup_download",
                                          defaultValue: "The wallet backup hasn't finished downloading from iCloud. Stay online and try again.")
                    step = previous
                    return
                }
            }
        }

        do {
            if let lost {
                try await deviceService.takeOver(lostDeviceId: lost.deviceId)
            } else {
                try await deviceService.promoteThisDeviceToPrimary()
            }
        } catch {
            errorMessage = error.localizedDescription
            step = previous
            return
        }

        // The promotion posts a notification; WalletManager re-initialises as
        // primary, restores the newest backup and opens bark. "Open as
        // primary" is the FFI handle being present with the mode flipped and
        // no initialisation in flight: a secondary is already `isInitialized`
        // and the mode flips before the restore, so neither is evidence on
        // its own (review 2026-11-14, F1). The mock wallet has no handle.
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        var opened = false
        while ContinuousClock.now < deadline {
            let handleOpen = (walletManager.wallet as? BarkWalletFFI).map { $0.wallet != nil } ?? true
            if handleOpen && !walletManager.isReadOnlyMode && !walletManager.isInitializing && walletManager.isInitialized {
                opened = true
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard opened else {
            errorMessage = walletManager.error
                ?? String(localized: "make_primary_error_open",
                          defaultValue: "The wallet did not open on this device. Relaunch Arké and check Settings › Devices.")
            step = previous
            return
        }

        if lost != nil {
            await walletManager.reconcileAfterTakeover()
        }
        step = .done
        try? await Task.sleep(for: .seconds(1))
        isPresented = false
        onSuccess?()
    }
}
