//
//  RecoveryPhraseInputTests.swift
//  ArkéTests
//
//  The recovery-phrase entry engine: what the suggestion strip offers, when
//  a typed prefix completes on its own, how pasted text becomes words, and
//  which phrases the pre-check lets through. Decisions and failure modes,
//  not the list itself. Plan: Docs/Features/Import_Screen_Split.md §9.
//

import Testing
import BIP39

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Recovery Phrase Input Tests")
struct RecoveryPhraseInputTests {

    // MARK: - Cached list

    @Test("The cached list is the package's list, 2048 words")
    func cachedListMatchesPackage() {
        #expect(BIP39WordSuggestions.words.count == 2048)
        #expect(BIP39WordSuggestions.words == EnglishWordListProvider().wordList)
        #expect(BIP39WordSuggestions.contains("Zoo "))
        #expect(!BIP39WordSuggestions.contains("zzzzz"))
    }

    // MARK: - Suggestions

    @Test("Candidates start at two letters, keep list order and honour the limit")
    func candidatesThresholdOrderLimit() {
        #expect(BIP39WordSuggestions.candidates(forPrefix: "c").isEmpty)
        #expect(BIP39WordSuggestions.candidates(forPrefix: "cab") == ["cabbage", "cabin", "cable"])
        #expect(BIP39WordSuggestions.candidates(forPrefix: "ca", limit: 3) == ["cabbage", "cabin", "cable"])
        #expect(BIP39WordSuggestions.candidates(forPrefix: " CAB ") == ["cabbage", "cabin", "cable"])
        #expect(BIP39WordSuggestions.candidates(forPrefix: "xq").isEmpty)
        #expect(BIP39WordSuggestions.candidates(forPrefix: "re").count == BIP39WordSuggestions.defaultLimit)
    }

    @Test("A unique prefix completes; a whole word, an ambiguous prefix, one letter and a non-prefix do not")
    func uniqueCompletionRules() {
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "cabi") == "cabin")
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "sket") == "sketch")
        #expect(BIP39WordSuggestions.uniqueCompletion(for: " Cabi ") == "cabin")
        // "act" is a list word and a prefix of action, actor, actress, actual
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "act") == nil)
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "zoo") == nil)
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "cab") == nil)
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "z") == nil)
        #expect(BIP39WordSuggestions.uniqueCompletion(for: "xq") == nil)
    }

    // MARK: - Paste

    private static let twelve = ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                                 "abandon", "abandon", "abandon", "abandon", "abandon", "about"]

    @Test("Numbered, line-broken, comma-separated and mixed-case phrases all split into the same words")
    func pasteFormats() {
        let numbered = (1...12).map { "\($0). \(Self.twelve[$0 - 1])" }.joined(separator: " ")
        let bracketed = (1...12).map { "\($0)) \(Self.twelve[$0 - 1])" }.joined(separator: "\n")
        let commas = Self.twelve.joined(separator: ", ")
        let shouting = Self.twelve.joined(separator: "  ").uppercased()
        for text in [numbered, bracketed, commas, shouting] {
            #expect(RecoveryPhraseInput.words(fromPasted: text) == Self.twelve)
        }
    }

    @Test("Eleven, thirteen and twenty-five words are refused; twenty-four are taken")
    func pasteCounts() {
        #expect(RecoveryPhraseInput.words(fromPasted: Self.twelve.dropLast().joined(separator: " ")) == nil)
        #expect(RecoveryPhraseInput.words(fromPasted: (Self.twelve + ["abandon"]).joined(separator: " ")) == nil)
        #expect(RecoveryPhraseInput.words(fromPasted: (Self.twelve + Self.twelve + ["abandon"]).joined(separator: " ")) == nil)
        #expect(RecoveryPhraseInput.words(fromPasted: (Self.twelve + Self.twelve).joined(separator: " "))?.count == 24)
        #expect(RecoveryPhraseInput.words(fromPasted: "https://example.com/not-a-phrase") == nil)
    }

    // MARK: - Pre-check

    @Test("The pre-check passes a valid phrase and refuses a bad checksum, an unknown word and an unsupported count")
    func precheck() {
        #expect(RecoveryPhraseInput.isValidPhrase(words: Self.twelve))
        #expect(RecoveryPhraseInput.isValidPhrase(Self.twelve.joined(separator: "  ").uppercased()))
        #expect(!RecoveryPhraseInput.isValidPhrase(words: Array(repeating: "abandon", count: 12)))
        #expect(!RecoveryPhraseInput.isValidPhrase(words: Self.twelve.dropLast() + ["zzzzz"]))
        #expect(!RecoveryPhraseInput.isValidPhrase(words: Self.twelve + ["abandon", "abandon", "abandon"]))
        #expect(!RecoveryPhraseInput.isValidPhrase(words: []))
    }
}
