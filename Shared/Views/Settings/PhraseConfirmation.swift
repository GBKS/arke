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

        /// Exact match per position after normalization. No prefix
        /// matching and no word-list lookup: the point is to prove a written
        /// copy, not to help complete one.
        func matches(_ answers: [String]) -> Bool {
            guard answers.count == expected.count else { return false }
            return zip(answers, expected).allSatisfy { PhraseConfirmation.normalize($0) == $1 }
        }
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
