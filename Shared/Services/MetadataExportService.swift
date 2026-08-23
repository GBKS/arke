//
//  MetadataExportService.swift
//  Arké
//
//  Exports user-added metadata (contacts, tags, transaction notes and
//  assignments, personal profile) as a versioned JSON file. See
//  Docs/Features/Metadata_Export_Import.md for the format contract and
//  merge semantics. Import lands in Phase 2 and decodes the same DTOs.
//

import Foundation
import SwiftData

// MARK: - File Format (versioned envelope)

/// Top-level structure of an `arke-metadata` export file.
/// The DTOs are deliberately decoupled from both the SwiftData models and the
/// ArkéUI presentation models so the on-disk format stays stable.
struct MetadataExportFile: Codable {
    static let currentFormat = "arke-metadata"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String?
    /// Canonical network type ("mainnet", "signet", …) the wallet was on at export time.
    var network: String
    var profile: ExportedProfile?
    var tags: [ExportedTag]
    var contacts: [ExportedContact]
    var transactionAnnotations: [ExportedTransactionAnnotation]
}

struct ExportedProfile: Codable {
    var name: String
    var avatarData: Data?
    var createdAt: Date
    var updatedAt: Date
}

struct ExportedTag: Codable {
    var id: UUID
    var name: String
    var colorHex: String
    var emoji: String
    var createdDate: Date
    var isSystemTag: Bool
}

struct ExportedContact: Codable {
    var id: UUID
    var name: String
    var notes: String?
    var avatarData: Data?
    var contactType: String
    var createdAt: Date
    var updatedAt: Date
    var addresses: [ExportedContactAddress]
}

/// `normalizedAddress` intentionally does not travel — it is derived and the
/// importer recomputes it.
struct ExportedContactAddress: Codable {
    var id: UUID
    var address: String
    var format: String
    var label: String?
    var isPrimary: Bool
    var network: String?
    var createdAt: Date
    var updatedAt: Date
}

/// User annotations on a transaction, keyed by txid. The transaction itself
/// belongs to the wallet database and never travels in this file.
struct ExportedTransactionAnnotation: Codable {
    var txid: String
    var notes: String?
    var tagAssignments: [ExportedTagAssignment]
    var contactAssignments: [ExportedContactAssignment]
}

struct ExportedTagAssignment: Codable {
    var tagId: UUID
    var assignedDate: Date
}

struct ExportedContactAssignment: Codable {
    var contactId: UUID
    var assignedDate: Date
}

// MARK: - Export Service

@MainActor
struct MetadataExportService {

    /// Gather all user-added metadata from the store into the file DTOs.
    static func buildExportFile(context: ModelContext) throws -> MetadataExportFile {
        // Profile: only travels once the user actually configured one
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let profile = profiles.first(where: { $0.isConfigured }).map {
            ExportedProfile(name: $0.name, avatarData: $0.avatarData, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }

        let tags = try context.fetch(FetchDescriptor<PersistentTag>(sortBy: [SortDescriptor(\.name)])).map {
            ExportedTag(id: $0.id, name: $0.name, colorHex: $0.colorHex, emoji: $0.emoji,
                        createdDate: $0.createdDate, isSystemTag: $0.isSystemTag)
        }

        // All contacts travel, including app-provisioned ones (faucet, developer):
        // excluding them would leave dangling contactId references in the
        // annotations below. The importer's identity matching merges them
        // instead of duplicating.
        let contacts = try context.fetch(FetchDescriptor<PersistentContact>(sortBy: [SortDescriptor(\.cachedName)])).map { contact in
            ExportedContact(
                id: contact.id,
                name: contact.cachedName,
                notes: contact.notes,
                avatarData: contact.avatarData,
                contactType: contact.contactType,
                createdAt: contact.createdAt,
                updatedAt: contact.updatedAt,
                addresses: (contact.addresses ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                    .map {
                        ExportedContactAddress(id: $0.id, address: $0.address, format: $0.formatRawValue,
                                               label: $0.label, isPrimary: $0.isPrimary, network: $0.networkRawValue,
                                               createdAt: $0.createdAt, updatedAt: $0.updatedAt)
                    }
            )
        }

        // Annotations: only transactions the user actually touched. Relationship
        // predicates are unreliable with CloudKit-optional relationships, so
        // fetch and filter in memory.
        let transactions = try context.fetch(FetchDescriptor<PersistentTransaction>(sortBy: [SortDescriptor(\.txid)]))
        let annotations: [ExportedTransactionAnnotation] = transactions.compactMap { transaction in
            let notes = transaction.notes?.isEmpty == false ? transaction.notes : nil
            let tagAssignments = (transaction.tagAssignments ?? []).compactMap { assignment in
                assignment.tag.map { ExportedTagAssignment(tagId: $0.id, assignedDate: assignment.assignedDate) }
            }.sorted { $0.assignedDate < $1.assignedDate }
            let contactAssignments = (transaction.contactAssignments ?? []).compactMap { assignment in
                assignment.contact.map { ExportedContactAssignment(contactId: $0.id, assignedDate: assignment.assignedDate) }
            }.sorted { $0.assignedDate < $1.assignedDate }

            guard notes != nil || !tagAssignments.isEmpty || !contactAssignments.isEmpty else { return nil }
            return ExportedTransactionAnnotation(txid: transaction.txid, notes: notes,
                                                 tagAssignments: tagAssignments,
                                                 contactAssignments: contactAssignments)
        }

        return MetadataExportFile(
            format: MetadataExportFile.currentFormat,
            version: MetadataExportFile.currentVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            network: NetworkConfigPersistence.load().networkType,
            profile: profile,
            tags: tags,
            contacts: contacts,
            transactionAnnotations: annotations
        )
    }

    /// Encode the export with the same settings as the wallet-data export:
    /// ISO8601 dates, pretty-printed, sorted keys.
    static func makeExportData(context: ModelContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(try buildExportFile(context: context))
    }

    /// Suggested file name, e.g. `arke-metadata-2026-08-23-1430.json`.
    static func exportFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "arke-metadata-\(formatter.string(from: date)).json"
    }

    /// Write the export to a temporary file suitable for handing to the
    /// iOS share sheet.
    static func writeTemporaryExportFile(context: ModelContext) throws -> URL {
        let data = try makeExportData(context: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName())
        try data.write(to: url, options: .atomic)
        return url
    }
}
