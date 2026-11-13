//
//  RecoveryPhraseInput.swift
//  Arke
//
//  What the recovery-phrase entry screen and the import pre-check agree on:
//  the word counts bark imports, how pasted text becomes words, and whether a
//  complete phrase is a valid mnemonic. The checksum question goes to bark's
//  binding (`validateMnemonic`), which returns false for a bad checksum and
//  for an unknown word without any network use (MnemonicChecksumTests), so a
//  phrase bark would refuse never reaches the keychain.
//  Plan: Docs/Features/Import_Screen_Split.md §3.
//

import Foundation
import Bark

nonisolated enum RecoveryPhraseInput {

    /// The counts `BarkWalletFFI.importWallet` accepts.
    static let supportedWordCounts = [12, 24]

    /// Splits pasted text into lowercase words. Anything that is not a
    /// letter separates words, so "1. abandon 2) ability", line breaks, commas
    /// and doubled spaces all split cleanly; BIP39 English words are ASCII
    /// letters only. Nil unless the result is 12 or 24 words, so a URL or a
    /// sentence on the clipboard fills nothing.
    static func words(fromPasted text: String) -> [String]? {
        let tokens = tokens(in: text)
        guard supportedWordCounts.contains(tokens.count) else { return nil }
        return tokens
    }

    /// Lowercase letter runs in the text, in order.
    static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    /// Whether the words form a mnemonic bark will import: a supported count
    /// and a passing checksum with every word in the list.
    static func isValidPhrase(words: [String]) -> Bool {
        guard supportedWordCounts.contains(words.count) else { return false }
        return (try? Bark.validateMnemonic(mnemonic: words.joined(separator: " "))) == true
    }

    /// Same check for a space-separated phrase string.
    static func isValidPhrase(_ phrase: String) -> Bool {
        let words = phrase
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).lowercased() }
        return isValidPhrase(words: words)
    }
}
