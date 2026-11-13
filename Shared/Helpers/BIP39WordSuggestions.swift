//
//  BIP39WordSuggestions.swift
//  Arke
//
//  Prefix lookup over the English BIP39 word list for the recovery-phrase
//  entry screen: which list words start with what the user has typed, and
//  whether the typed letters already identify exactly one word. The list is
//  cached once; the BIP39 package's `wordList` is a computed property that
//  rebuilds its 2048-element literal on every access.
//
//  The engine reports list membership of single words only. Whether a whole
//  phrase is a valid mnemonic (checksum) stays with bark, see
//  `RecoveryPhraseInput`. Plan: Docs/Features/Import_Screen_Split.md §3.
//

import Foundation
import BIP39

nonisolated enum BIP39WordSuggestions {

    /// The English BIP39 list, in list order (alphabetical), built once.
    static let words: [String] = EnglishWordListProvider().wordList

    private static let wordSet: Set<String> = Set(words)

    /// Below this many typed letters nothing is suggested or completed: a
    /// one-letter prefix matches 82 words on average.
    static let minimumPrefixLength = 2

    /// How many chips the entry screen shows at most.
    static let defaultLimit = 6

    /// Trims surrounding whitespace and lowercases, the same rule the phrase
    /// confirmation check applies.
    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether the word, normalized, is in the list.
    static func contains(_ word: String) -> Bool {
        wordSet.contains(normalize(word))
    }

    /// List words starting with the typed prefix, in list order, at most
    /// `limit`. Empty below `minimumPrefixLength` and for a non-prefix.
    static func candidates(forPrefix prefix: String, limit: Int = defaultLimit) -> [String] {
        let normalized = normalize(prefix)
        guard normalized.count >= minimumPrefixLength, limit > 0 else { return [] }
        return Array(words.lazy.filter { $0.hasPrefix(normalized) }.prefix(limit))
    }

    /// The one list word the typed letters identify, or nil: nil when several
    /// words share the prefix, when the typed text already is a whole list
    /// word ("act" is a word and also a prefix of action, actor, actress,
    /// actual), below `minimumPrefixLength`, and for a non-prefix.
    static func uniqueCompletion(for text: String) -> String? {
        let normalized = normalize(text)
        guard normalized.count >= minimumPrefixLength, !wordSet.contains(normalized) else { return nil }
        let matches = candidates(forPrefix: normalized, limit: 2)
        return matches.count == 1 ? matches[0] : nil
    }
}
