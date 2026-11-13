//
//  ImportBackupFileView_iOS.swift
//  Arké
//
//  Second import step: the wallet backup file. Choosing the file is the
//  default; restoring from the phrase alone is the emergency path behind a
//  small Skip and a confirmation (funds come back from the network, history
//  and anything in progress do not). The import call runs here, with the
//  phrase validated on the previous step.
//  Plan: Docs/Features/Import_Screen_Split.md §4.
//

import SwiftUI
import ArkeUI
import UniformTypeIdentifiers
import OSLog

struct ImportBackupFileView_iOS: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ImportBackupFileView")

    /// Server and chain chosen on the cover screen.
    let networkConfig: NetworkConfig
    /// The validated phrase from the previous step, space-separated.
    let phrase: String
    let onBack: () -> Void
    let onWalletImported: () -> Void

    @Environment(WalletManager.self) private var walletManager
    @State private var backupFileURL: URL?
    @State private var backupFileName: String?
    @State private var showingFilePicker = false
    @State private var showingSkipConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isImporting = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                    header

                    VStack(spacing: 8) {
                        Text(String(localized: "backup_file_section_title", defaultValue: "Wallet Backup File"))
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(Color.Arke.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)

                        Text(String(localized: "onboarding_import_backup_body", defaultValue: "Choose the backup file you exported from Arké. It restores your payment history and anything still in progress."))
                            .font(.system(.title2))
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(localized: "onboarding_import_backup_without", defaultValue: "Without it, your funds are recovered from the network and the history starts fresh."))
                            .font(.system(.body))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // The file control sits with the text that explains it;
                    // the bottom button only imports, so the two cannot be
                    // mistaken for each other
                    if let fileName = backupFileName {
                        selectedFileCard(fileName)
                    } else {
                        selectFileButton
                    }

                    Spacer(minLength: 10)

                    importButton
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, safeAreaInsets.top)
                .padding(.bottom, safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    backupFileURL = url
                    backupFileName = url.lastPathComponent

                    // Announce file selection for VoiceOver users
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIAccessibility.post(notification: .announcement,
                            argument: String(format: String(localized: "accessibility_backup_file_selected", defaultValue: "Selected backup file: %@"), url.lastPathComponent))
                    }
                }
            case .failure(let error):
                showError(String(format: L10n.errorFilePicker, error.localizedDescription))
            }
        }
        // An alert, not a confirmation dialog: on iPhone the dialog rendered as
        // a narrow popover that drops its Cancel button, leaving the
        // destructive choice as the only visible action (simulator check
        // 2026-11-12).
        .alert(
            String(localized: "onboarding_import_skip_title", defaultValue: "Restore without the backup file?"),
            isPresented: $showingSkipConfirmation
        ) {
            Button(String(localized: "onboarding_import_skip_confirm", defaultValue: "Restore without file"), role: .destructive) {
                Task {
                    await importWallet(backupURL: nil)
                }
            }
            Button(L10n.buttonCancel, role: .cancel) { }
        } message: {
            Text(String(localized: "onboarding_import_skip_message", defaultValue: "Your funds are recovered from the network, but your payment history and anything still in progress are not. If the file exists on another device or in Files, go back and choose it."))
        }
        .alert(String(localized: "error_import", defaultValue: "Import Error"), isPresented: $showingError) {
            Button(L10n.buttonOk) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .accessibilityLabel(L10n.buttonBack)
            // Once the import runs, bark owns the wallet directory and the
            // keychain write follows; leaving the screen mid-way has no
            // defined outcome.
            .disabled(isImporting)

            Spacer()

            // The emergency path: small, in the corner, behind a confirmation
            Button {
                showingSkipConfirmation = true
            } label: {
                Text(String(localized: "button_skip", defaultValue: "Skip"))
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color.Arke.gold)
                    // Small to look at, full-size to tap
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .accessibilityHint(String(localized: "onboarding_import_skip_hint", defaultValue: "Restores the wallet from the recovery phrase alone"))
        }
        .padding(.top, 10)
    }

    /// The chosen file; tapping it opens the picker again.
    private func selectedFileCard(_ fileName: String) -> some View {
        Button {
            showingFilePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(String(localized: "backup_file_selected", defaultValue: "Backup file selected"))
                        .font(.footnote)
                        .opacity(0.8)
                }
                // Wrapped lines (long file names) centre by default;
                // keep every line flush left like the stack itself.
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.Arke.gold)
            .padding(15)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.Arke.gold.opacity(0.5), lineWidth: 2)
            )
        }
        .frame(maxWidth: 400)
        .disabled(isImporting)
        .accessibilityHint(String(localized: "onboarding_import_change_file_hint", defaultValue: "Choose a different backup file"))
    }

    /// Opens the picker; replaced by the file card once a file is chosen.
    private var selectFileButton: some View {
        Button {
            openFilePicker()
        } label: {
            Label(String(localized: "button_select_backup_file", defaultValue: "Select Backup File"), systemImage: "doc.badge.plus")
                .font(.system(.body, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(Color.Arke.gold)
        .frame(maxWidth: 400)
        .disabled(isImporting)
    }

    /// Disabled until a file is chosen; the phrase-only path is Skip.
    private var importButton: some View {
        Button {
            guard let url = backupFileURL else { return }
            Task {
                await importWallet(backupURL: url)
            }
        } label: {
            Text(isImporting ? String(localized: "status_importing", defaultValue: "Importing...") : L10n.buttonImportWallet)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(Color.Arke.gold4)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color.Arke.gold)
        .disabled(backupFileURL == nil || isImporting)
    }

    // MARK: - Actions

    private func openFilePicker() {
        showingFilePicker = true

        // Announce when file picker is opened for VoiceOver users
        if UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIAccessibility.post(notification: .announcement,
                    argument: String(localized: "accessibility_file_picker_opened", defaultValue: "File picker opened. Select your backup file."))
            }
        }
    }

    private func importWallet(backupURL: URL?) async {
        isImporting = true

        do {
            // With a file the wallet database is restored directly; without
            // one bark recovers funds from the network via its seed-recovery
            // scan (local history is not restored)
            let result: String
            if let backupURL {
                result = try await walletManager.importWalletWithBackup(
                    mnemonic: phrase,
                    backupFileURL: backupURL,
                    networkConfig: networkConfig
                )
                Self.logger.info("✅ Wallet imported successfully with backup: \(result)")
            } else {
                result = try await walletManager.importWallet(
                    mnemonic: phrase,
                    networkConfig: networkConfig
                )
                Self.logger.info("✅ Wallet imported successfully from recovery phrase only: \(result)")
            }

            onWalletImported()
        } catch {
            isImporting = false
            showError(String(format: String(localized: "error_import_wallet", defaultValue: "Failed to import wallet: %@"), error.localizedDescription))
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
