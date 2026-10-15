//
//  PhraseConfirmationTests.swift
//  ArkéTests
//
//  The two-word phrase check in front of a full wipe: when it is required,
//  what it asks for, and what counts as a match. Tests the decisions and the
//  failure modes, not the shuffling.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Phrase Confirmation Tests")
struct PhraseConfirmationTests {

    /// Deterministic generator so position draws can be compared.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private static let twelve = "abandon ability able about above absent absorb abstract absurd abuse access accident"
    private static let twentyFour = twelve + " account accuse achieve acid acoustic acquire across act action actor actress actual"

    // MARK: - When the check is required

    @Test("Required exactly when the deletion scope would be everywhere")
    func requiredMirrorsScope() {
        #expect(PhraseConfirmation.isRequired(strategy: .promptForCloudData, overrideRequested: false))
        #expect(PhraseConfirmation.isRequired(strategy: .promptForCloudData, overrideRequested: true))
        #expect(PhraseConfirmation.isRequired(strategy: .localOnly, overrideRequested: true))
        #expect(!PhraseConfirmation.isRequired(strategy: .localOnly, overrideRequested: false))
    }

    @Test("The predicate and the service's scope rule cannot drift apart")
    func requiredEqualsIncludesCloudData() {
        for strategy in [DeletionStrategy.promptForCloudData, .localOnly] {
            for override in [false, true] {
                #expect(
                    PhraseConfirmation.isRequired(strategy: strategy, overrideRequested: override)
                        == WalletDataCleanupService.includesCloudData(strategy: strategy, overrideConfirmed: override)
                )
            }
        }
    }

    // MARK: - What it asks for

    @Test("Two distinct ascending positions inside the phrase, with the words found there", arguments: [twelve, twentyFour])
    func challengeShape(phrase: String) throws {
        var generator = SeededGenerator(state: 7)
        let challenge = try #require(PhraseConfirmation.challenge(from: phrase, using: &generator))
        let words = phrase.split(separator: " ").map(String.init)

        #expect(challenge.positions.count == 2)
        #expect(challenge.positions[0] < challenge.positions[1])
        #expect(challenge.positions.allSatisfy { (1...words.count).contains($0) })
        #expect(challenge.expected == challenge.positions.map { words[$0 - 1] })
    }

    @Test("Positions change between draws")
    func positionsVaryBetweenDraws() {
        var generator = SeededGenerator(state: 1)
        var seen = Set<[Int]>()
        for _ in 0..<12 {
            if let challenge = PhraseConfirmation.challenge(from: Self.twentyFour, using: &generator) {
                seen.insert(challenge.positions)
            }
        }
        #expect(seen.count > 1)
    }

    @Test("A phrase with fewer words than the check asks for yields no challenge")
    func tooShortPhrase() {
        #expect(PhraseConfirmation.challenge(from: "abandon") == nil)
        #expect(PhraseConfirmation.challenge(from: "") == nil)
    }

    // MARK: - What counts as a match

    private static let fixed = PhraseConfirmation.Challenge(positions: [4, 9], expected: ["about", "absurd"])

    @Test("Exact words pass")
    func exactWordsPass() {
        #expect(Self.fixed.matches(["about", "absurd"]))
    }

    @Test("Case and surrounding whitespace are forgiven")
    func normalizationForgiven() {
        #expect(Self.fixed.matches([" About ", "ABSURD\n"]))
    }

    @Test("A wrong word, swapped order, an empty answer or a prefix fail")
    func mismatchesFail() {
        #expect(!Self.fixed.matches(["about", "abuse"]))
        #expect(!Self.fixed.matches(["absurd", "about"]))
        #expect(!Self.fixed.matches(["about", ""]))
        #expect(!Self.fixed.matches(["abou", "absurd"]))
        #expect(!Self.fixed.matches(["about"]))
    }
}
