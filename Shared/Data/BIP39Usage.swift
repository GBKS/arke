//
//  BIP39Usage.swift
//  Ark wallet prototype
//
//  Examples of using swift-bip39 library
//

import Foundation
import BIP39

/// Examples and utilities for working with BIP39 mnemonics
enum BIP39Examples {
    
    // MARK: - Dependencies
    
    private static let entropyGenerator: EntropyGenerating = EntropyGenerator()
    private static let mnemonicConstructor: MnemonicConstructing = MnemonicConstructor()
    private static let seedDerivator: SeedDerivating = SeedDerivator()

    // MARK: - Basic Usage
    
    /// Generate a new 12-word mnemonic (128-bit entropy)
    static func generate12WordMnemonic() throws -> String {
        let entropy = entropyGenerator.entropy(security: .medium) // 128-bit
        let mnemonic = mnemonicConstructor.mnemonic(entropy: entropy, wordList: BIP39WordSuggestions.words)
        return mnemonic
    }
    
    /// Generate a new 24-word mnemonic (256-bit entropy)
    static func generate24WordMnemonic() throws -> String {
        let entropy = entropyGenerator.entropy(security: .strongest) // 256-bit
        let mnemonic = mnemonicConstructor.mnemonic(entropy: entropy, wordList: BIP39WordSuggestions.words)
        return mnemonic
    }
    
    /// Generate a mnemonic with specific entropy security level
    static func generateMnemonic(security: EntropySecurity = .medium) -> String {
        let entropy = entropyGenerator.entropy(security: security)
        let mnemonic = mnemonicConstructor.mnemonic(entropy: entropy, wordList: BIP39WordSuggestions.words)
        return mnemonic
    }
    
    /// Generate seed from mnemonic with optional passphrase
    static func generateSeed(from mnemonic: String, passphrase: String = "") -> Data {
        let seed = seedDerivator.seed(mnemonic: mnemonic, passphrase: passphrase)
        return seed
    }
    
    // Validation lives in `RecoveryPhraseInput.isValidPhrase` (bark's
    // binding checks list membership and the checksum).

    // MARK: - Conversion
    
    /// Convert mnemonic phrase to seed bytes
    static func phraseToSeed(_ phrase: String, passphrase: String = "") -> Data {
        return seedDerivator.seed(mnemonic: phrase, passphrase: passphrase)
    }
    
    /// Convert entropy to mnemonic phrase
    static func entropyToPhrase(_ entropy: Data) -> String {
        let mnemonic = mnemonicConstructor.mnemonic(entropy: entropy, wordList: BIP39WordSuggestions.words)
        return mnemonic
    }
    
    // MARK: - Word List Access
    
    /// Get the word at a specific index from the BIP39 wordlist
    static func word(at index: Int) -> String? {
        let wordList = BIP39WordSuggestions.words
        guard index >= 0 && index < wordList.count else { return nil }
        return wordList[index]
    }
    
    /// Get all words in the BIP39 wordlist
    static func allWords() -> [String] {
        return BIP39WordSuggestions.words
    }
    
    // MARK: - Examples
    
    /// Run all examples
    static func runExamples() {
        print("=== BIP39 Examples ===\n")
        
        // Example 1: Generate 12-word mnemonic
        do {
            let mnemonic12 = try generate12WordMnemonic()
            print("12-word mnemonic:")
            print(mnemonic12)
            print("Words: \(mnemonic12.split(separator: " ").count)\n")
        } catch {
            print("Error generating 12-word mnemonic: \(error)\n")
        }
        
        // Example 2: Generate 24-word mnemonic
        do {
            let mnemonic24 = try generate24WordMnemonic()
            print("24-word mnemonic:")
            print(mnemonic24)
            print("Words: \(mnemonic24.split(separator: " ").count)\n")
        } catch {
            print("Error generating 24-word mnemonic: \(error)\n")
        }
        
        // Example 5: Generate seed from mnemonic
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let seed = generateSeed(from: mnemonic)
        print("Mnemonic: \(mnemonic)")
        print("Seed (hex): \(seed.map { String(format: "%02x", $0) }.joined())")
        print("Seed length: \(seed.count) bytes\n")
        
        // Example 6: Generate seed with passphrase
        let seedWithPassphrase = generateSeed(from: mnemonic, passphrase: "mypassphrase")
        print("With passphrase 'mypassphrase':")
        print("Seed (hex): \(seedWithPassphrase.map { String(format: "%02x", $0) }.joined())")
        print("Note: Seeds are different with different passphrases\n")
        
        // Example 7: Word list access
        if let firstWord = word(at: 0), let lastWord = word(at: 2047) {
            print("First word in BIP39 list: \(firstWord)")
            print("Last word in BIP39 list: \(lastWord)")
            print("Total words in list: \(allWords().count)\n")
        }
    }
}

// MARK: - Error Types

enum MnemonicError: Error, LocalizedError {
    case entropyGenerationFailed
    case invalidWordCount(Int)
    case invalidWord(String, at: Int)
    
    var errorDescription: String? {
        switch self {
        case .entropyGenerationFailed:
            return "Failed to generate cryptographically secure random entropy"
        case .invalidWordCount(let count):
            return "Invalid word count: \(count). Must be 12, 15, 18, 21, or 24 words"
        case .invalidWord(let word, let index):
            return "Invalid word '\(word)' at position \(index + 1)"
        }
    }
}

// MARK: - Testing Helpers

#if DEBUG
extension BIP39Examples {
    /// Common test mnemonics for development
    enum TestMnemonics {
        /// Standard 12-word test mnemonic
        static let test12Word = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        
        /// Standard 24-word test mnemonic
        static let test24Word = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
        
        /// Another valid 12-word mnemonic for testing
        static let alternate12Word = "legal winner thank year wave sausage worth useful legal winner thank yellow"
        
        /// Another valid 24-word mnemonic for testing
        static let alternate24Word = "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless"
    }
}
#endif
