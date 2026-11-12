//
//  PhraseConfirmation.swift
//  Arke
//
//  The two-word recovery-phrase check in front of a full wipe: when it is
//  required, which words are asked for, and whether the answers match. Pure
//  so it can be unit-tested without a WalletManager or a keychain.
//
//  Background (DECIDED 2026-10-10, flow 2026-10-15; plan
//  Docs/Features/Wallet_Deletion_Phrase_Confirmation.md): the last-device
//  full wipe deletes the synchronizable seed as its final step, after which
//  only a phrase the user wrote down can restore the wallet. Asking for two
//  words by position is a consent check and a backup-existence proof in
//  one. Local-only deletion keeps the seed on the account and is exempt.
//

import Foundation

nonisolated enum PhraseConfirmation {

    /// How many words the user is asked for.
    static let wordCount = 2

    /// Whether this deletion needs the check. Mirrors the service's scope
    /// rule (`WalletDataCleanupService.includesCloudData`) so the screen
    /// appears exactly when the scope would be `.everywhere`: a last-device
    /// deletion, or a `.localOnly` verdict the user overrides.
    static func isRequired(strategy: DeletionStrategy, overrideRequested: Bool) -> Bool {
        WalletDataCleanupService.includesCloudData(strategy: strategy, overrideConfirmed: overrideRequested)
    }

    /// Two positions and the words expected there. Holds only those two
    /// words; the rest of the phrase is dropped before the value is built.
    struct Challenge: Equatable {
        /// 1-based positions as shown to the user, ascending.
        let positions: [Int]
        /// The expected words, normalized, in the same order as `positions`.
        let expected: [String]

        /// Match per position after normalization: the whole word, or its
        /// first four letters (DECIDED 2026-11-12). Every word of the BIP39
        /// English list is unique in its first four letters, so the four
        /// letters identify the word as surely as the whole of it and a
        /// guess gains nothing; what the rule forgives is a typo after the
        /// fourth letter, or stopping early. Words shorter than four
        /// letters must match whole. No word-list lookup and no hint which
        /// word failed: the point is to prove a written copy, not to help
        /// complete one.
        func matches(_ answers: [String]) -> Bool {
            guard answers.count == expected.count else { return false }
            return zip(answers, expected).allSatisfy { answer, word in
                PhraseConfirmation.wordMatches(answer: PhraseConfirmation.normalize(answer), expected: word)
            }
        }
    }

    /// How many leading letters identify a BIP39 English word on their own.
    static let identifyingPrefixLength = 4

    /// One word against its expected value, both normalized. Whole-word
    /// equality, or an answer of at least four letters whose first four
    /// equal the expected word's first four (which requires the expected
    /// word itself to have at least four).
    static func wordMatches(answer: String, expected: String) -> Bool {
        if answer == expected { return true }
        guard answer.count >= identifyingPrefixLength,
              expected.count >= identifyingPrefixLength else { return false }
        return answer.prefix(identifyingPrefixLength) == expected.prefix(identifyingPrefixLength)
    }

    /// Builds a challenge from the phrase with random positions. Nil when
    /// the phrase has fewer words than the check asks for.
    static func challenge(from phrase: String) -> Challenge? {
        var generator = SystemRandomNumberGenerator()
        return challenge(from: phrase, using: &generator)
    }

    /// Positions are drawn fresh on every call (random per presentation,
    /// DECIDED 2026-10-15), so a screenshot of the phrase screen does not
    /// pre-answer the check. The generator is injectable for tests only.
    static func challenge(from phrase: String, using generator: inout some RandomNumberGenerator) -> Challenge? {
        let words = phrase
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { normalize(String($0)) }
        guard words.count >= wordCount else { return nil }

        var candidates = Array(1...words.count)
        candidates.shuffle(using: &generator)
        let positions = Array(candidates.prefix(wordCount)).sorted()

        return Challenge(
            positions: positions,
            expected: positions.map { words[$0 - 1] }
        )
    }

    /// Trims surrounding whitespace and lowercases. Typing "Apple " for
    /// "apple" is not a failed backup.
    static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
