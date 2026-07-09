# BIP39 Mnemonic Support

**Status:** Implemented and stable
**Library:** [anquii/BIP39](https://github.com/anquii/BIP39) (Swift Package)
**Consolidated 2026-07-09** from BIP39_INTEGRATION_GUIDE, BIP39_QUICK_REFERENCE, and BIP39_TROUBLESHOOTING (inventory Step 16). Rewritten to match the actual library API — the old guides documented `Mnemonic`/`Entropy` types this library does not expose.

## Overview

The app uses the `anquii/BIP39` package for mnemonic phrase generation and validation. Wallet seed phrases are **12 words (128-bit entropy)**, generated with cryptographically secure randomness and stored in the Keychain.

## Where It's Used

| File | Role |
|------|------|
| `Shared/Data/BarkWalletFFI/BarkWalletFFI+Mnemonic.swift` | Production path: generation, validation, Keychain storage/retrieval via SecurityService |
| `Shared/Data/BIP39Usage.swift` | `BIP39Examples` — utilities, seed derivation examples, wordlist access, and `TestMnemonics` (DEBUG) |

## The Actual Library API

`anquii/BIP39` is protocol-based. There are **no** `Mnemonic` or `Entropy` types (a common source of confusion — earlier docs and many online examples assume a different library):

```swift
import BIP39

let wordListProvider = EnglishWordListProvider()
let mnemonicConstructor = MnemonicConstructor()
let seedDerivator = SeedDerivator()
let entropyGenerator = EntropyGenerator()
```

### Generate a Mnemonic

Production code generates its own entropy with `SecRandomCopyBytes` rather than using `EntropyGenerator` (see `BarkWalletFFI+Mnemonic.swift`):

```swift
// 16 bytes = 128 bits = 12 words (24 words would be 32 bytes)
var randomBytes = [UInt8](repeating: 0, count: 16)
let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
guard result == errSecSuccess else { throw ... }

let phrase = mnemonicConstructor.mnemonic(
    entropy: Data(randomBytes),
    wordList: wordListProvider.wordList
)
```

Alternatively, via the library's generator (`BIP39Examples`):

```swift
let entropy = entropyGenerator.entropy(security: .medium)    // 128-bit → 12 words
let entropy = entropyGenerator.entropy(security: .strongest) // 256-bit → 24 words
let phrase = mnemonicConstructor.mnemonic(entropy: entropy, wordList: wordListProvider.wordList)
```

### Validate a Mnemonic

The library does not expose a validator, so validation is manual — wordlist membership plus word count:

```swift
let words = phrase.split(separator: " ").map(String.init)
let wordList = EnglishWordListProvider().wordList

let allWordsValid = words.allSatisfy { wordList.contains($0) }
let validCount = [12, 15, 18, 21, 24].contains(words.count)
```

> **Known gap:** checksum validation is a TODO in both `BarkWalletFFI+Mnemonic.swift` and `BIP39Usage.swift`. A phrase with valid words and count but a corrupted checksum currently passes app-side validation (Bark rejects it later at restore).

### Derive a Seed

```swift
let seed: Data = seedDerivator.seed(mnemonic: phrase, passphrase: "")
```

## Storage

Mnemonics are stored **only** in the Keychain via `SecurityService` (no file-system fallback), always synchronizable and without a keychain ACL — biometric gating happens at the app level (see Decision B in `Initialization/STARTUP_WALLET_DETECTION_PLAN.md`). For new-wallet creation, `WalletManager` handles storage; `BarkWalletFFI.storeMnemonic` is used only for import flows.

## BIP39 Reference

| Words | Entropy (bits) | Checksum (bits) | Total (bits) |
|-------|----------------|-----------------|--------------|
| 12    | 128            | 4               | 132          |
| 15    | 160            | 5               | 165          |
| 18    | 192            | 6               | 198          |
| 21    | 224            | 7               | 231          |
| 24    | 256            | 8               | 264          |

- Standardized English wordlist of 2,048 words; each word encodes 11 bits.
- All words are unique within their first 4 letters.
- [BIP39 Specification](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) · [Word List](https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt)

## Test Mnemonics

Defined in `BIP39Examples.TestMnemonics` (DEBUG only):

```
12: abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
24: abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art
```

The 12-word test phrase is also what `BarkWalletFFI.getMnemonic()` returns in SwiftUI preview mode.

## Security Practices

- Entropy comes from `SecRandomCopyBytes` (cryptographically secure).
- Never hardcode mnemonics outside `TestMnemonics`/preview paths.
- Mnemonics live in the Keychain only — never plain text, never logged.
- Validate user input before attempting a wallet import.

## Troubleshooting

- **"No such module 'BIP39'"** — the package isn't linked to the target. Check Project → Package Dependencies for `https://github.com/anquii/BIP39`, and the target's Frameworks list. Then clean build (Shift+Cmd+K); resetting package caches (File → Packages → Reset Package Caches) fixes most SPM cache issues.
- **"Cannot find 'Mnemonic'/'Entropy' in scope"** — those types don't exist in this library; you're looking at examples for a different BIP39 package. Use the protocol-based API above.
