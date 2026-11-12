//
//  DeleteExportStepView.swift
//  Arke
//
//  The step between the Delete wallet screen and the two-word phrase check
//  on a full wipe (DECIDED 2026-11-12): the wallet backup file (required:
//  phrase + file is the normal restore, the phrase alone is the emergency
//  path, Christoph 2026-11-12) and the contacts & metadata export
//  (optional), each one tap away, before the wipe empties the iCloud backup
//  slot and the mirrored history. Replaces the "Back up Wallet" link, which
//  led into the three-page manual backup section and back out again.
//  Plan: Docs/Features/Wallet_Deletion_Export_Step.md.
//
//  Continue is disabled until the backup row reports a completed share
//  (DECIDED 2026-11-12, third round), with no caption under the button.
//  "Completed" is what iOS reports: Save to Files, AirDrop and Copy count,
//  a cancelled sheet does not; the app cannot know where the file went.
//  Fail-open when there is no file to export (no local database and no
//  iCloud slot, or the copy failed): the row says so and Continue is
//  enabled, since blocking there would make the wallet undeletable. Nothing
//  here is destructive. The screen owns only the two exports and their
//  outcomes; the phrase check, the slider sheet and the deletion call stay
//  where they were.
//

import SwiftUI
import SwiftData
import ArkeUI
#if os(macOS)
import AppKit
#endif

struct DeleteExportStepView: View {
    @Environment(\.modelContext) private var modelContext

    /// The user moves on to the phrase check.
    let onContinue: () -> Void

    /// What became of the last export attempt for one file.
    private enum ExportOutcome: Equatable {
        /// The user finished an activity with the file (saved, sent, copied).
        case saved
        /// No file to export, or writing the copy failed.
        case failed(String)
    }

    @State private var walletFileOutcome: ExportOutcome?
    @State private var metadataOutcome: ExportOutcome?
    /// The metadata row only when the user added something to export
    /// (DECIDED 2026-11-12); an empty export is a non-choice on a screen
    /// about committing. Starts hidden so it cannot flash and vanish; a
    /// failed check shows the row rather than hiding data.
    @State private var showsMetadataRow = false

    /// The backup file is saved, or there is none to save (fail-open: the
    /// wallet must stay deletable). The metadata export never gates.
    private var canContinue: Bool {
        switch walletFileOutcome {
        case .saved, .failed: return true
        case nil: return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "settings_delete_export_title", defaultValue: "Take your data with you"))
                        .font(.system(.title, design: .serif))

                    Text(String(localized: "settings_delete_export_body", defaultValue: "Deleting everything also removes the wallet's iCloud backup. Save your own copy first."))
                        .font(.title3)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 0) {
                    exportRow(
                        icon: "tablecells.fill",
                        tint: .Arke.teal,
                        title: String(localized: "settings_delete_export_wallet_file", defaultValue: "Wallet backup file"),
                        subtitle: String(localized: "settings_delete_export_wallet_file_subtitle", defaultValue: "Needed to restore the wallet with your recovery phrase"),
                        outcome: walletFileOutcome,
                        action: exportWalletFile
                    )

                    if showsMetadataRow {
                        Divider()
                            .padding(.vertical, 12)

                        exportRow(
                            icon: "person.text.rectangle.fill",
                            tint: .Arke.purple,
                            title: String(localized: "settings_metadata_backup", defaultValue: "Contacts & Metadata"),
                            subtitle: String(localized: "settings_delete_export_metadata_subtitle", defaultValue: "Optional. Contacts, tags, notes, and profile."),
                            outcome: metadataOutcome,
                            action: exportMetadata
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showsMetadataRow)

                // No caption under the disabled button (Christoph,
                // 2026-11-12): the body and the Download button say what is
                // missing, and this screen needs the user's attention anyway
                Button {
                    onContinue()
                } label: {
                    Text(String(localized: "button_continue", defaultValue: "Continue"))
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Color.Arke.gold)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.2), value: canContinue)
                .padding(.top, 15)
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .task {
            showsMetadataRow = (try? MetadataExportService.hasUserAddedMetadata(context: modelContext)) ?? true
        }
    }

    /// One file: icon tile, title, subtitle, and a Download button that
    /// turns into a checkmark once the share sheet reports completion. The
    /// button stays live after a success so the user can save a second
    /// copy; a failure message sits under the row.
    private func exportRow(icon: String, tint: Color, title: String, subtitle: String,
                           outcome: ExportOutcome?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: action) {
                    HStack(spacing: 6) {
                        if outcome == .saved {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                            Text(String(localized: "status_saved", defaultValue: "Saved"))
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text(L10n.buttonDownload)
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
                .tint(outcome == .saved ? Color.green : nil)
                .accessibilityLabel(title)
                .accessibilityValue(outcome == .saved ? String(localized: "status_saved", defaultValue: "Saved") : "")
            }

            if case .failed(let message) = outcome {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.Arke.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: outcome)
    }

    // MARK: - Exports

    /// The newer of the live `db.sqlite` and the iCloud backup file, through
    /// the static entry so a read-only secondary with no handle is covered
    /// (`WalletBackupService.getShareableWalletFileURL()` for the rule).
    private func exportWalletFile() {
        guard let url = WalletBackupService.shareableWalletFileURL() else {
            walletFileOutcome = .failed(String(localized: "settings_delete_export_wallet_file_missing", defaultValue: "No wallet backup file is available on this device."))
            return
        }
        deliver(url) { walletFileOutcome = $0 }
    }

    /// Same export as the Contacts & Metadata page.
    private func exportMetadata() {
        do {
            let url = try MetadataExportService.writeTemporaryExportFile(context: modelContext)
            deliver(url) { metadataOutcome = $0 }
        } catch {
            metadataOutcome = .failed(String(format: L10n.errorFilePicker, error.localizedDescription))
        }
    }

    /// Hands a temporary file to the user: the share sheet on iOS, a save
    /// panel on macOS. The outcome is what the system reports back; the
    /// app cannot know where the file went, only that an activity finished.
    private func deliver(_ url: URL, outcome: @escaping (ExportOutcome) -> Void) {
        #if os(iOS)
        ShareHelper.share(items: [url]) { completed in
            if completed {
                outcome(.saved)
            }
        }
        #else
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            outcome(.saved)
        } catch {
            outcome(.failed(String(format: L10n.errorFilePicker, error.localizedDescription)))
        }
        #endif
    }
}
