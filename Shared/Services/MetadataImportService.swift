//
//  MetadataImportService.swift
//  Arké
//
//  Imports an arke-metadata file (see MetadataExportService for the DTOs and
//  Docs/Features/Metadata_Export_Import.md for the format contract). Merge is
//  upsert-by-identity and never deletes: UUID match first, then fallback
//  identity (tag name, contact address, contact name), newest updatedAt wins
//  where a timestamp exists. Annotations apply only to transactions already
//  in the local store; unmatched ones are counted and reported — re-importing
//  after the transactions sync attaches them.
//

import Foundation
import SwiftData
import ArkeUI

// MARK: - Errors

enum MetadataImportError: LocalizedError {
    case notAnArkeMetadataFile
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notAnArkeMetadataFile:
            return String(localized: "metadata_import_error_invalid", defaultValue: "This file is not an Arké data export.")
        case .unsupportedVersion(let version):
            return String(localized: "metadata_import_error_version", defaultValue: "This export file (version \(version)) was created by a newer app version. Update the app to import it.")
        }
    }
}

// MARK: - Merge Policy (pure, unit-testable without SwiftData)

enum MetadataImportPolicy {

    /// Shared normalization for identity matching (same recipe as
    /// ContactAddressService's normalizedAddress)
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Local tag the imported tag merges into, if any: UUID first, then name
    static func matchTag(importedId: UUID, importedName: String,
                         localIds: Set<UUID>, localIdsByName: [String: UUID]) -> UUID? {
        if localIds.contains(importedId) { return importedId }
        return localIdsByName[normalize(importedName)]
    }

    /// Local contact the imported contact merges into, if any:
    /// UUID first, then any shared address, then exact (normalized) name
    static func matchContact(importedId: UUID, importedName: String, importedAddresses: [String],
                             localIds: Set<UUID>, localIdsByAddress: [String: UUID],
                             localIdsByName: [String: UUID]) -> UUID? {
        if localIds.contains(importedId) { return importedId }
        for address in importedAddresses {
            if let match = localIdsByAddress[normalize(address)] { return match }
        }
        return localIdsByName[normalize(importedName)]
    }

    /// Newest-wins for entities carrying an updatedAt timestamp
    static func importedWins(importedUpdatedAt: Date, localUpdatedAt: Date) -> Bool {
        importedUpdatedAt > localUpdatedAt
    }

    /// Transaction notes carry no timestamp to arbitrate with, so a local
    /// note is never overwritten — the imported note only fills a gap
    static func shouldApplyNote(imported: String?, local: String?) -> Bool {
        guard let imported, !imported.isEmpty else { return false }
        return local?.isEmpty != false
    }
}

// MARK: - Preview & Result

/// What an import would do — shown in the confirmation sheet before applying
struct MetadataImportPreview {
    let file: MetadataExportFile
    let newTags: Int
    let mergedTags: Int
    let newContacts: Int
    let mergedContacts: Int
    let matchedAnnotations: Int
    let unmatchedAnnotations: Int
    let willApplyProfile: Bool
}

struct MetadataImportResult {
    let createdTags: Int
    let createdContacts: Int
    let updatedContacts: Int
    let annotationsApplied: Int
    let annotationsSkipped: Int
    let profileApplied: Bool
}

// MARK: - Import Service

@MainActor
struct MetadataImportService {

    /// Decode and validate an export file. Probes format/version first so a
    /// newer file version fails with a clear message instead of a decode error.
    static func decode(_ data: Data) throws -> MetadataExportFile {
        struct EnvelopeProbe: Codable {
            var format: String
            var version: Int
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let probe = try? decoder.decode(EnvelopeProbe.self, from: data),
              probe.format == MetadataExportFile.currentFormat else {
            throw MetadataImportError.notAnArkeMetadataFile
        }
        guard probe.version <= MetadataExportFile.currentVersion else {
            throw MetadataImportError.unsupportedVersion(probe.version)
        }

        do {
            return try decoder.decode(MetadataExportFile.self, from: data)
        } catch {
            throw MetadataImportError.notAnArkeMetadataFile
        }
    }

    /// Dry-run the merge against the local store for the confirmation sheet
    static func preview(file: MetadataExportFile, context: ModelContext) throws -> MetadataImportPreview {
        let local = try LocalSnapshot(context: context)

        var newTags = 0, mergedTags = 0
        for tag in file.tags {
            if MetadataImportPolicy.matchTag(importedId: tag.id, importedName: tag.name,
                                             localIds: local.tagIds, localIdsByName: local.tagIdsByName) != nil {
                mergedTags += 1
            } else {
                newTags += 1
            }
        }

        var newContacts = 0, mergedContacts = 0
        for contact in file.contacts {
            if MetadataImportPolicy.matchContact(importedId: contact.id, importedName: contact.name,
                                                 importedAddresses: contact.addresses.map(\.address),
                                                 localIds: local.contactIds,
                                                 localIdsByAddress: local.contactIdsByAddress,
                                                 localIdsByName: local.contactIdsByName) != nil {
                mergedContacts += 1
            } else {
                newContacts += 1
            }
        }

        let matched = file.transactionAnnotations.filter { local.txids.contains($0.txid) }.count

        return MetadataImportPreview(
            file: file,
            newTags: newTags,
            mergedTags: mergedTags,
            newContacts: newContacts,
            mergedContacts: mergedContacts,
            matchedAnnotations: matched,
            unmatchedAnnotations: file.transactionAnnotations.count - matched,
            willApplyProfile: shouldApplyProfile(file.profile, context: context)
        )
    }

    /// Apply the merge. Never deletes; saves once at the end.
    static func apply(file: MetadataExportFile, context: ModelContext) throws -> MetadataImportResult {
        var createdTags = 0, createdContacts = 0, updatedContacts = 0
        var annotationsApplied = 0, annotationsSkipped = 0

        // Tags — build the importedTagId → local model map used by annotations.
        // On a UUID match the imported fields win (same tag edited elsewhere);
        // on a name match the local tag stays untouched and just absorbs the
        // imported id's assignments (no timestamp to arbitrate fields with).
        let localTags = try context.fetch(FetchDescriptor<PersistentTag>())
        var tagsById = Dictionary(localTags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var tagsByName = Dictionary(localTags.map { (MetadataImportPolicy.normalize($0.name), $0) }, uniquingKeysWith: { first, _ in first })

        var tagForImportedId: [UUID: PersistentTag] = [:]
        for imported in file.tags {
            if let byId = tagsById[imported.id] {
                byId.name = imported.name
                byId.colorHex = imported.colorHex
                byId.emoji = imported.emoji
                tagForImportedId[imported.id] = byId
            } else if let byName = tagsByName[MetadataImportPolicy.normalize(imported.name)] {
                tagForImportedId[imported.id] = byName
            } else {
                let tag = PersistentTag(id: imported.id, name: imported.name, colorHex: imported.colorHex,
                                        emoji: imported.emoji, createdDate: imported.createdDate,
                                        isSystemTag: imported.isSystemTag)
                context.insert(tag)
                tagsById[tag.id] = tag
                tagsByName[MetadataImportPolicy.normalize(tag.name)] = tag
                tagForImportedId[imported.id] = tag
                createdTags += 1
            }
        }

        // Contacts — newest updatedAt wins for fields; addresses merge additively
        let localContacts = try context.fetch(FetchDescriptor<PersistentContact>())
        var contactsById = Dictionary(localContacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var contactsByAddress: [String: PersistentContact] = [:]
        var contactsByName: [String: PersistentContact] = [:]
        for contact in localContacts {
            for address in contact.addresses ?? [] {
                contactsByAddress[address.normalizedAddress] = contact
            }
            contactsByName[MetadataImportPolicy.normalize(contact.cachedName)] = contact
        }

        var contactForImportedId: [UUID: PersistentContact] = [:]
        for imported in file.contacts {
            let match = MetadataImportPolicy.matchContact(
                importedId: imported.id, importedName: imported.name,
                importedAddresses: imported.addresses.map(\.address),
                localIds: Set(contactsById.keys),
                localIdsByAddress: contactsByAddress.mapValues(\.id),
                localIdsByName: contactsByName.mapValues(\.id)
            ).flatMap { contactsById[$0] }

            if let existing = match {
                if MetadataImportPolicy.importedWins(importedUpdatedAt: imported.updatedAt, localUpdatedAt: existing.updatedAt) {
                    existing.cachedName = imported.name
                    existing.notes = imported.notes
                    existing.avatarData = imported.avatarData
                    existing.contactType = imported.contactType
                    // Keep the imported timestamp so newest-wins stays stable
                    // across devices and repeated imports
                    existing.updatedAt = imported.updatedAt
                    updatedContacts += 1
                }
                mergeAddresses(from: imported, into: existing, context: context)
                contactForImportedId[imported.id] = existing
            } else {
                let contact = PersistentContact(id: imported.id, cachedName: imported.name, notes: imported.notes,
                                                avatarData: imported.avatarData, createdAt: imported.createdAt,
                                                updatedAt: imported.updatedAt)
                contact.contactType = imported.contactType
                context.insert(contact)
                mergeAddresses(from: imported, into: contact, context: context)
                contactsById[contact.id] = contact
                contactForImportedId[imported.id] = contact
                createdContacts += 1
            }
        }

        // Annotations — only for transactions already in the store
        let localTransactions = try context.fetch(FetchDescriptor<PersistentTransaction>())
        let transactionsByTxid = Dictionary(localTransactions.map { ($0.txid, $0) }, uniquingKeysWith: { first, _ in first })

        for annotation in file.transactionAnnotations {
            guard let transaction = transactionsByTxid[annotation.txid] else {
                annotationsSkipped += 1
                continue
            }

            if MetadataImportPolicy.shouldApplyNote(imported: annotation.notes, local: transaction.notes) {
                transaction.notes = annotation.notes
            }

            let existingTagIds = Set((transaction.tagAssignments ?? []).compactMap { $0.tag?.id })
            for assignment in annotation.tagAssignments {
                guard let tag = tagForImportedId[assignment.tagId], !existingTagIds.contains(tag.id) else { continue }
                context.insert(TransactionTagAssignment(tag: tag, transaction: transaction, assignedDate: assignment.assignedDate))
            }

            let existingContactIds = Set((transaction.contactAssignments ?? []).compactMap { $0.contact?.id })
            for assignment in annotation.contactAssignments {
                guard let contact = contactForImportedId[assignment.contactId], !existingContactIds.contains(contact.id) else { continue }
                context.insert(TransactionContactAssignment(contact: contact, transaction: transaction, assignedDate: assignment.assignedDate))
            }

            annotationsApplied += 1
        }

        // Profile — only if unconfigured locally, or the imported one is newer
        var profileApplied = false
        if let imported = file.profile, shouldApplyProfile(imported, context: context) {
            let profiles = try context.fetch(FetchDescriptor<UserProfile>())
            if let existing = profiles.first {
                existing.name = imported.name
                existing.avatarData = imported.avatarData
                existing.updatedAt = imported.updatedAt
            } else {
                context.insert(UserProfile(name: imported.name, avatarData: imported.avatarData,
                                           createdAt: imported.createdAt, updatedAt: imported.updatedAt))
            }
            profileApplied = true
        }

        try context.save()

        return MetadataImportResult(
            createdTags: createdTags,
            createdContacts: createdContacts,
            updatedContacts: updatedContacts,
            annotationsApplied: annotationsApplied,
            annotationsSkipped: annotationsSkipped,
            profileApplied: profileApplied
        )
    }

    // MARK: - Helpers

    /// Local store lookups for the dry-run preview
    private struct LocalSnapshot {
        let tagIds: Set<UUID>
        let tagIdsByName: [String: UUID]
        let contactIds: Set<UUID>
        let contactIdsByAddress: [String: UUID]
        let contactIdsByName: [String: UUID]
        let txids: Set<String>

        init(context: ModelContext) throws {
            let tags = try context.fetch(FetchDescriptor<PersistentTag>())
            tagIds = Set(tags.map(\.id))
            tagIdsByName = Dictionary(tags.map { (MetadataImportPolicy.normalize($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })

            let contacts = try context.fetch(FetchDescriptor<PersistentContact>())
            contactIds = Set(contacts.map(\.id))
            var byAddress: [String: UUID] = [:]
            var byName: [String: UUID] = [:]
            for contact in contacts {
                for address in contact.addresses ?? [] {
                    byAddress[address.normalizedAddress] = contact.id
                }
                byName[MetadataImportPolicy.normalize(contact.cachedName)] = contact.id
            }
            contactIdsByAddress = byAddress
            contactIdsByName = byName

            let transactions = try context.fetch(FetchDescriptor<PersistentTransaction>())
            txids = Set(transactions.map(\.txid))
        }
    }

    private static func shouldApplyProfile(_ imported: ExportedProfile?, context: ModelContext) -> Bool {
        guard let imported else { return false }
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let existing = profiles.first(where: { $0.isConfigured }) else { return true }
        return MetadataImportPolicy.importedWins(importedUpdatedAt: imported.updatedAt, localUpdatedAt: existing.updatedAt)
    }

    /// Add imported addresses the contact doesn't have yet. Never flips an
    /// existing primary; an imported primary only applies if none is set.
    private static func mergeAddresses(from imported: ExportedContact, into contact: PersistentContact, context: ModelContext) {
        var existingNormalized = Set((contact.addresses ?? []).map(\.normalizedAddress))
        var hasPrimary = (contact.addresses ?? []).contains { $0.isPrimary }

        for importedAddress in imported.addresses {
            let normalized = MetadataImportPolicy.normalize(importedAddress.address)
            guard !existingNormalized.contains(normalized) else { continue }

            let address = PersistentContactAddress(
                id: importedAddress.id,
                address: importedAddress.address,
                normalizedAddress: normalized,
                format: AddressFormat(rawValue: importedAddress.format) ?? .bitcoin,
                label: importedAddress.label,
                isPrimary: importedAddress.isPrimary && !hasPrimary,
                network: importedAddress.network.flatMap { BitcoinNetwork(rawValue: $0) },
                createdAt: importedAddress.createdAt,
                updatedAt: importedAddress.updatedAt
            )
            address.contact = contact
            context.insert(address)
            existingNormalized.insert(normalized)
            if address.isPrimary { hasPrimary = true }
        }
    }
}
