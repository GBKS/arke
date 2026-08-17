//
//  LocalizationCatalogTests.swift
//  Arke
//
//  Guard for the defaultValue: migration (see
//  Shared/Docs/Localization/Default_Value_Migration_Plan.md): every active
//  snake_case key must carry English — either a stringUnit value or plural
//  variation values — and keys present in both catalogs must not drift.
//  A key without English renders as the raw key in the UI.
//
//  Parses the catalogs from the repo via #filePath, so these tests run
//  against the working tree, not a bundled resource copy.
//

import Foundation
import Testing

@Suite("Localization Catalog Guard")
struct LocalizationCatalogTests {

    struct CatalogEntry {
        let english: String?
        let isStale: Bool
    }

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/Shared
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static let catalogPaths = [
        "Shared": "Shared/Localizable.xcstrings",
        "ArkéUI": "ArkeUI/Sources/ArkéUI/Localizable.xcstrings",
    ]

    static func loadCatalog(_ relativePath: String) throws -> [String: CatalogEntry] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(root?["strings"] as? [String: Any])

        var entries: [String: CatalogEntry] = [:]
        for (key, value) in strings {
            let entry = value as? [String: Any] ?? [:]
            let en = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]

            var english = ((en?["stringUnit"] as? [String: Any])?["value"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            if english == nil,
               let plural = ((en?["variations"] as? [String: Any])?["plural"] as? [String: Any]) {
                let forms = plural.values
                    .compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                    .compactMap { $0["value"] as? String }
                    .filter { !$0.isEmpty }
                english = forms.isEmpty ? nil : forms.sorted().joined(separator: "; ")
            }

            entries[key] = CatalogEntry(
                english: english,
                isStale: (entry["extractionState"] as? String) == "stale"
            )
        }
        return entries
    }

    static func isSnakeCaseKey(_ key: String) -> Bool {
        // Semantic keys: lowercase snake_case, optionally with a format-specifier
        // tail ("balance_vtxos_expiring_soon %lld").
        let base = key.components(separatedBy: " ").first ?? key
        guard base.contains("_") else { return false }
        return base.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    @Test("Every active snake_case key has an English value", arguments: catalogPaths.keys)
    func activeKeysHaveEnglish(catalogName: String) throws {
        let catalog = try Self.loadCatalog(Self.catalogPaths[catalogName]!)
        let missing = catalog
            .filter { Self.isSnakeCaseKey($0.key) && !$0.value.isStale && $0.value.english == nil }
            .keys.sorted()
        #expect(missing.isEmpty,
                "\(catalogName): keys without English render raw in the UI: \(missing)")
    }

    @Test("Keys in both catalogs have identical English (Shared is canonical)")
    func noValueDriftBetweenCatalogs() throws {
        let shared = try Self.loadCatalog(Self.catalogPaths["Shared"]!)
        let arkeUI = try Self.loadCatalog(Self.catalogPaths["ArkéUI"]!)
        let drift = shared
            .compactMapValues(\.english)
            .compactMap { key, sharedValue -> String? in
                guard let packageValue = arkeUI[key]?.english,
                      packageValue != sharedValue else { return nil }
                return "\(key): Shared=“\(sharedValue)” ArkéUI=“\(packageValue)”"
            }
            .sorted()
        #expect(drift.isEmpty, "Same key, different text depending on module: \(drift)")
    }

    @Test("No keys with surrounding whitespace", arguments: catalogPaths.keys)
    func noSurroundingWhitespaceKeys(catalogName: String) throws {
        let catalog = try Self.loadCatalog(Self.catalogPaths[catalogName]!)
        let padded = catalog.keys
            .filter { $0 != $0.trimmingCharacters(in: .whitespacesAndNewlines) && !catalog[$0]!.isStale }
            .sorted()
        #expect(padded.isEmpty,
                "\(catalogName): padded keys are a concatenation smell (Rule 5): \(padded)")
    }
}
