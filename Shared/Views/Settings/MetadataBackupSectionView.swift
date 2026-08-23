//
//  MetadataBackupSectionView.swift
//  Arké
//
//  Export and import of user-added metadata (contacts, tags, transaction
//  notes, profile) inside the Manual Backup section. Shown inline on macOS
//  and as a pushed page on iOS. Import shows a preview sheet before applying
//  the upsert merge — see Docs/Features/Metadata_Export_Import.md.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ArkeUI
#if os(macOS)
import AppKit
#endif

struct MetadataBackupSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WalletManager.self) private var walletManager
    @State private var exportErrorMessage: String?
    @State private var isShowingImporter = false
    @State private var importPreview: MetadataImportPreview?
    @State private var importResultMessage: String?

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

            Text(String(localized: "metadata_backup_description", defaultValue: "Exports your contacts, tags, transaction notes, and profile as a file, or imports one exported earlier. The file contains no keys and no funds."))
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

            if let importResultMessage = importResultMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(importResultMessage)
                        .foregroundColor(.green)
                }
                .font(.callout)
            }

            #if os(iOS)
            VStack(spacing: 20) {
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

                Button(action: { isShowingImporter = true }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "metadata_import_button", defaultValue: "Import"))
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
            #else
            HStack(spacing: 12) {
                Button(action: exportMetadata) {
                    Label(L10n.buttonDownload, systemImage: "square.and.arrow.down")
                }

                Button(action: { isShowingImporter = true }) {
                    Label(String(localized: "metadata_import_button", defaultValue: "Import"), systemImage: "doc.badge.plus")
                }
            }
            .controlSize(.large)
            #endif
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { importPreview = nil } }
        )) {
            if let preview = importPreview {
                MetadataImportPreviewSheet(preview: preview) {
                    applyImport(preview)
                }
            }
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

    private func handleFileImport(_ result: Result<[URL], Swift.Error>) {
        exportErrorMessage = nil
        importResultMessage = nil

        do {
            guard let url = try result.get().first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                exportErrorMessage = String(format: L10n.errorFilePicker, url.lastPathComponent)
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let file = try MetadataImportService.decode(data)
            importPreview = try MetadataImportService.preview(file: file, context: modelContext)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func applyImport(_ preview: MetadataImportPreview) {
        do {
            let result = try MetadataImportService.apply(file: preview.file, context: modelContext)
            importPreview = nil
            importResultMessage = String(localized: "metadata_import_success",
                                         defaultValue: "Imported \(result.createdContacts + result.updatedContacts) contacts, \(result.createdTags) tags, \(result.annotationsApplied) transaction annotations.")

            // Refresh the service caches so the imported data shows up immediately
            Task {
                await walletManager.refreshContacts()
                await ServiceContainer.shared.tagService.refreshTags()
            }
        } catch {
            importPreview = nil
            exportErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Import Preview Sheet

/// Confirmation sheet shown before an import is applied: what the file
/// contains, what would merge vs be created, and what can't attach yet.
private struct MetadataImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: MetadataImportPreview
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "metadata_import_preview_title", defaultValue: "Import Preview"))
                .font(.system(size: 24, design: .serif))

            VStack(alignment: .leading, spacing: 8) {
                row(label: String(localized: "metadata_import_exported", defaultValue: "Exported"),
                    value: preview.file.exportedAt.formatted(date: .abbreviated, time: .shortened))

                row(label: String(localized: "metadata_import_contacts", defaultValue: "Contacts"),
                    value: String(localized: "metadata_import_new_merged", defaultValue: "\(preview.newContacts) new, \(preview.mergedContacts) merged"))

                row(label: String(localized: "metadata_import_tags", defaultValue: "Tags"),
                    value: String(localized: "metadata_import_new_merged", defaultValue: "\(preview.newTags) new, \(preview.mergedTags) merged"))

                row(label: String(localized: "metadata_import_annotations", defaultValue: "Transaction notes & tags"),
                    value: "\(preview.matchedAnnotations)")

                if preview.willApplyProfile {
                    row(label: String(localized: "metadata_import_profile", defaultValue: "Profile"),
                        value: String(localized: "metadata_import_profile_applied", defaultValue: "Will be applied"))
                }
            }
            .font(.body)

            if preview.unmatchedAnnotations > 0 {
                Label(String(localized: "metadata_import_unmatched",
                             defaultValue: "\(preview.unmatchedAnnotations) annotations reference transactions not in this wallet yet. Import again after they sync."),
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if isNetworkMismatch {
                Label(String(localized: "metadata_import_network_mismatch",
                             defaultValue: "This file was exported from a \(preview.file.network) wallet."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundColor(.Arke.orange)
            }

            HStack(spacing: 12) {
                Button(L10n.buttonCancel) {
                    dismiss()
                }

                Button(String(localized: "metadata_import_confirm", defaultValue: "Import")) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 400)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium])
        #endif
    }

    private var isNetworkMismatch: Bool {
        preview.file.network != NetworkConfigPersistence.load().networkType
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
