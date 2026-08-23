//
//  MetadataBackupSectionView.swift
//  Arké
//
//  Export of user-added metadata (contacts, tags, transaction notes,
//  profile) inside the Manual Backup section. Shown inline on macOS and as
//  a pushed page on iOS. Import arrives in Phase 2 of the feature — see
//  Docs/Features/Metadata_Export_Import.md.
//

import SwiftUI
import SwiftData
import ArkeUI
#if os(macOS)
import AppKit
#endif

struct MetadataBackupSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportErrorMessage: String?

    var body: some View {
        #if os(iOS)
        ScrollView {
            content
                .padding()
        }
        .navigationTitle(String(localized: "settings_metadata_backup", defaultValue: "Contacts & Metadata"))
        .navigationBarTitleDisplayMode(.large)
        #else
        content
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            Text(String(localized: "settings_metadata_backup", defaultValue: "Contacts & Metadata"))
                .font(.system(size: 24, design: .serif))
            #endif

            Text(String(localized: "metadata_backup_description", defaultValue: "Exports your contacts, tags, transaction notes, and profile as a file. It contains no keys and no funds."))
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(iOS)
                .font(.title3)
                #else
                .font(.body)
                #endif

            if let exportErrorMessage = exportErrorMessage {
                Text(exportErrorMessage)
                    .foregroundColor(.Arke.red)
                    .font(.callout)
            }

            #if os(iOS)
            Button(action: exportMetadata) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(L10n.buttonDownload)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            #else
            Button(action: exportMetadata) {
                Label(L10n.buttonDownload, systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)
            #endif
        }
    }

    private func exportMetadata() {
        exportErrorMessage = nil
        do {
            #if os(iOS)
            let url = try MetadataExportService.writeTemporaryExportFile(context: modelContext)
            ShareHelper.share(items: [url])
            #else
            let data = try MetadataExportService.makeExportData(context: modelContext)

            let panel = NSSavePanel()
            panel.nameFieldStringValue = MetadataExportService.exportFileName()
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try data.write(to: destination, options: .atomic)
            #endif
        } catch {
            exportErrorMessage = String(format: L10n.errorFilePicker, error.localizedDescription)
        }
    }
}
