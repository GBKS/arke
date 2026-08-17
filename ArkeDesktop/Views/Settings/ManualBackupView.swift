//
//  ManualBackupView.swift
//  Arké
//
//  Manual backup page: recovery phrase plus the wallet backup file.
//  On macOS both sections are shown inline instead of as sub-pages.
//

import SwiftUI
import AppKit
import ArkeUI

struct ManualBackupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(String(localized: "settings_offline_backup_help", defaultValue: "An offline backup needs both items below. Your recovery phrase alone won't recover your full balance. The backup file holds data that exists only on your device and in iCloud."))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                // Recovery Phrase
                RecoveryPhraseSettingView()

                Divider()

                // Backup file
                BackupStatusSectionView()
            }
            .padding()
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L10n.settingsManualBackup)
    }
}

// MARK: - Backup File Section

struct BackupStatusSectionView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var backupInfo: BackupInfo?
    @State private var isBackingUp = false
    @State private var lastBackupResult: BackupResult?
    @State private var exportErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "settings_backup_file", defaultValue: "Backup File"))
                .font(.system(size: 24, design: .serif))

            Text(String(localized: "backup_description", defaultValue: "The backup file includes all transactions from your payments balance."))
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let info = backupInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "backup_last_synced", defaultValue: "Last synced"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(info.formattedDate)
                    }

                    HStack {
                        Text(String(localized: "backup_size", defaultValue: "Size"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(info.formattedSize)
                    }
                }
                .font(.body)
            } else {
                Text(String(localized: "backup_no_backup_available", defaultValue: "No backup available"))
                    .foregroundColor(.secondary)
                    .font(.body)
            }

            if let result = lastBackupResult {
                HStack {
                    Image(systemName: result == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(result == .failed ? .red : .green)
                    Text(result == .success ? String(localized: "backup_successful", defaultValue: "Backup successful") : result == .alreadyUpToDate ? String(localized: "backup_already_up_to_date", defaultValue: "Backup already up-to-date") : String(localized: "backup_failed", defaultValue: "Backup failed"))
                        .foregroundColor(result == .failed ? .red : .green)
                }
                .font(.body)
            }

            if let exportErrorMessage = exportErrorMessage {
                Text(exportErrorMessage)
                    .foregroundColor(.Arke.red)
                    .font(.callout)
            }

            HStack(spacing: 12) {
                Button {
                    exportBackupFile()
                } label: {
                    Label(L10n.buttonDownload, systemImage: "square.and.arrow.down")
                }
                .disabled(backupInfo == nil)

                Button {
                    Task {
                        await performManualBackup()
                    }
                } label: {
                    if isBackingUp {
                        Label(String(localized: "backup_syncing", defaultValue: "Syncing.."), systemImage: "arrow.clockwise.icloud")
                    } else {
                        Label(String(localized: "backup_sync_now", defaultValue: "Sync Now"), systemImage: "arrow.clockwise.icloud")
                    }
                }
                .disabled(isBackingUp)
            }
            .controlSize(.large)
        }
        .task {
            await loadBackupInfo()
        }
    }

    private func loadBackupInfo() async {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI else { return }
        backupInfo = await barkWallet.getBackupInfo()
    }

    private func performManualBackup() async {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI else { return }

        isBackingUp = true
        lastBackupResult = nil

        let success = await barkWallet.backupWallet()

        lastBackupResult = success
        isBackingUp = false

        // Refresh backup info after backup
        await loadBackupInfo()

        // Clear the success/failure message after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            lastBackupResult = nil
        }
    }

    private func exportBackupFile() {
        guard let barkWallet = walletManager.wallet as? BarkWalletFFI,
              let sourceURL = barkWallet.getShareableBackupFileURL() else { return }

        exportErrorMessage = nil

        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            exportErrorMessage = String(format: L10n.errorFilePicker, error.localizedDescription)
        }
    }
}
