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

    /// All catalogs, including the Info.plist permission strings — used by the
    /// translation-era checks (empty values, specifier parity).
    static let allCatalogPaths = catalogPaths.merging([
        "Mobile-InfoPlist": "ArkeMobile/InfoPlist.xcstrings",
        "Desktop-InfoPlist": "ArkeDesktop/InfoPlist.xcstrings",
    ]) { a, _ in a }

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

    // MARK: - Translation-era checks (de/ja …)
    //
    // A MISSING language entry is fine (translation pending — falls back to
    // English via defaultValue). An EMPTY value, or one whose format
    // specifiers disagree with the English, is always a bug: empties render
    // as blank text, specifier mismatches garble or crash at format time.

    /// All per-language values of a key: [language: [value strings]]
    /// (base value plus any plural-variation forms).
    static func allValues(_ relativePath: String) throws -> [String: [String: [String]]] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(root?["strings"] as? [String: Any])

        var result: [String: [String: [String]]] = [:]
        for (key, value) in strings {
            let localizations = ((value as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
            var perLanguage: [String: [String]] = [:]
            for (language, loc) in localizations {
                guard let loc = loc as? [String: Any] else { continue }
                var values: [String] = []
                if let unit = loc["stringUnit"] as? [String: Any], let v = unit["value"] as? String {
                    values.append(v)
                }
                if let plural = (loc["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    values += plural.values
                        .compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
                }
                perLanguage[language] = values
            }
            result[key] = perLanguage
        }
        return result
    }

    /// Format specifiers in positional order: "%2$@ costs %1$lld" -> at index 0
    /// "lld", index 1 "@". Non-positional specifiers take consecutive indices.
    static func specifiers(_ value: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var nextIndex = 0
        let pattern = /%(\d+\$)?(lld|llu|ld|lu|d|u|@|f)/
        for match in value.matches(of: pattern) {
            let index: Int
            if let positional = match.1 {
                index = Int(positional.dropLast())! - 1
            } else {
                index = nextIndex
            }
            result[index] = String(match.2)
            nextIndex = index + 1
        }
        return result
    }

    @Test("No translated value is empty", arguments: allCatalogPaths.keys)
    func noEmptyTranslations(catalogName: String) throws {
        let catalog = try Self.allValues(Self.allCatalogPaths[catalogName]!)
        let empty = catalog.flatMap { key, languages in
            languages.compactMap { language, values in
                values.contains("") ? "\(key) [\(language)]" : nil
            }
        }.sorted()
        #expect(empty.isEmpty,
                "\(catalogName): empty values render blank text — delete the entry (falls back to English) or fill it: \(empty)")
    }

    @Test("Translations keep the English format specifiers", arguments: allCatalogPaths.keys)
    func specifierParity(catalogName: String) throws {
        let catalog = try Self.allValues(Self.allCatalogPaths[catalogName]!)
        var mismatches: [String] = []
        for (key, languages) in catalog {
            // The reference is the union across English forms (a plural "one"
            // form may legitimately drop the number, so translated forms must
            // use a SUBSET of English's argument slots, with matching types).
            guard let englishForms = languages["en"], !englishForms.isEmpty else { continue }
            var reference: [Int: String] = [:]
            for form in englishForms {
                reference.merge(Self.specifiers(form)) { a, _ in a }
            }
            for (language, values) in languages where language != "en" {
                for value in values {
                    for (index, type) in Self.specifiers(value) where reference[index] != type {
                        mismatches.append(
                            "\(key) [\(language)] arg \(index + 1): \(type) vs en \(reference[index] ?? "absent") in “\(value)”")
                    }
                }
            }
        }
        #expect(mismatches.isEmpty,
                "\(catalogName): specifier mismatches garble or crash at format time: \(mismatches.sorted())")
    }
}
