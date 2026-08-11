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
                Text("settings_offline_backup_help")
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
        .navigationTitle("settings_manual_backup")
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
            Text("settings_backup_file")
                .font(.system(size: 24, design: .serif))

            Text(String(localized: "backup_description"))
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let info = backupInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "backup_last_synced"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(info.formattedDate)
                    }

                    HStack {
                        Text(String(localized: "backup_size"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(info.formattedSize)
                    }
                }
                .font(.body)
            } else {
                Text(String(localized: "backup_no_backup_available"))
                    .foregroundColor(.secondary)
                    .font(.body)
            }

            if let result = lastBackupResult {
                HStack {
                    Image(systemName: result == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(result == .failed ? .red : .green)
                    Text(result == .success ? String(localized: "backup_successful") : result == .alreadyUpToDate ? String(localized: "backup_already_up_to_date") : String(localized: "backup_failed"))
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
                    Label(String(localized: "button_download"), systemImage: "square.and.arrow.down")
                }
                .disabled(backupInfo == nil)

                Button {
                    Task {
                        await performManualBackup()
                    }
                } label: {
                    if isBackingUp {
                        Label(String(localized: "backup_syncing"), systemImage: "arrow.clockwise.icloud")
                    } else {
                        Label(String(localized: "backup_sync_now"), systemImage: "arrow.clockwise.icloud")
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
            exportErrorMessage = String(format: NSLocalizedString("error_file_picker", comment: ""), error.localizedDescription)
        }
    }
}
