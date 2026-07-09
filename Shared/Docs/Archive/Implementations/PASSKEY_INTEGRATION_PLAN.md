# Passkey Integration Implementation Plan

> **📦 Archived 2026-07-09 — not pursued.** Decision (Christoph): passkey integration does not bring enough benefit to Arke, so this plan was never implemented and there are no plans to revive it. Preserved for the recovery-mailbox research it contains (see also `PASSKEY_INTEGRATION_PLAN_REVIEW.md`). Note the plan also references `LinkWalletView`, which was removed in June 2026 when QR-based wallet linking was replaced with automatic iCloud Keychain sync.

## Executive Summary

This document outlines the implementation plan for integrating Apple Passkeys into Arke wallet creation and recovery. The hybrid approach balances convenience for mainstream users with sovereignty options for advanced users, while leveraging Ark's unique recovery capabilities.

**CRITICAL UPDATE:** Pragmatic recovery path identified via Bark's existing server infrastructure. Mnemonic + recovery mailbox = complete wallet recovery without requiring Rust FFI changes.

**Recovery Strategy:** 
- Passkey backs up mnemonic only (simple)
- Bark server recovery mailbox stores VTXO IDs (already implemented)
- Client fetches IDs → downloads VTXOs → imports via `importVtxo()` (WalletManager:1508)

**Target Date:** TBD  
**Status:** Planning Phase - Pragmatic Approach  
**Priority:** High (UX Improvement)

---

## Table of Contents

1. [Context & Motivation](#context--motivation)
2. [Technical Architecture](#technical-architecture)
3. [Implementation Phases](#implementation-phases)
4. [File Changes Required](#file-changes-required)
5. [Security Considerations](#security-considerations)
6. [User Experience Flow](#user-experience-flow)
7. [Testing Strategy](#testing-strategy)
8. [Future Enhancements](#future-enhancements)

---

## Context & Motivation

### Current State

**Wallet Creation:**
- BIP39 mnemonic generated via `bark` CLI or BDK
- Stored in local Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- PBKDF2 hash synced via `NSUbiquitousKeyValueStore` for cross-device detection
- Mnemonic intentionally never syncs to iCloud
- Multi-device setup requires manual QR code import

**Key Limitation:**
- Users must manually backup 12-24 word phrase
- Lost device = complex recovery process
- Poor UX compared to modern apps

### Why Passkeys Make Sense for Ark

Unlike traditional Bitcoin wallets, Ark has unique recovery characteristics:

1. **Mnemonic + Server Recovery Mailbox = Complete Recovery** ✨ NEW
   - Mnemonic recovers on-chain Bitcoin keys and signing ability
   - Bark server recovery mailbox stores VTXO IDs (already implemented)
   - `sync()` auto-recovers arkoor-received VTXOs
   - Recovery mailbox API + `importVtxo()` recovers round/board VTXOs
   - Together, they provide **complete wallet restoration**
   - **Trade-off:** Requires ASP availability (not 100% self-custody, but practical)

2. **Already requires iCloud for convenience features**
   - CloudKit stores: transactions, contacts, tags, device registry
   - `NSUbiquitousKeyValueStore` used for wallet detection
   - VTXO state in SwiftData/CloudKit for seamless multi-device
   - Without these, wallet works but loses convenience features (history, labels)

3. **User trust assumption is already present**
   - iPhone users are in Apple ecosystem
   - Already trusting iCloud for transaction history
   - Passkey sync is consistent with existing trust model

4. **Recovery mailbox enables pragmatic recovery** ✨ NEW
   - Server-side recovery mailbox already stores VTXO IDs
   - `importVtxo()` is AVAILABLE NOW (WalletManager:1508)
   - Client just needs to implement recovery mailbox reader
   - Practical 99% recovery without complex local VTXO export
   - **This is Arke's pragmatic approach**: Seamless UX + Practical Recovery

### Solution: Hybrid Approach

**Three-tier sovereignty spectrum:**

```
┌─────────────────────────────────────────────────────┐
│ Level 1: Passkey (Recommended - 95% of users)       │
│ ✓ Auto-sync across devices                          │
│ ✓ Seamless recovery with Face ID                    │
│ ✓ iCloud Keychain backup                            │
│ ✓ No manual phrase management                       │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Level 2: Passkey + Manual Export (Power users)      │
│ ✓ Everything from Level 1                           │
│ ✓ Export mnemonic (emergency backup)                │
│ ✓ CloudKit backup (transactions, contacts, tags)    │
│ ✓ Recovery via server mailbox (requires ASP)        │
│ ✓ Can escape Apple ecosystem (with ASP cooperation) │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Level 3: Pure Manual (Advanced - 5% of users)       │
│ ✓ No iCloud dependency                              │
│ ✓ Manual mnemonic backup                            │
│ ✓ Manual VTXO export/import                         │
│ ✓ Full self-sovereignty                             │
└─────────────────────────────────────────────────────┘
```

---

## Technical Architecture

### Core Components

#### 1. Passkey Service (`PasskeyService.swift`)

New service responsible for Passkey operations:

```swift
@MainActor
@Observable
class PasskeyService {
    // MARK: - Properties
    private let keychainService = "com.arke.wallet.passkey"
    private let credentialID = "arke.wallet.credential"
    
    // MARK: - Passkey Creation
    func createPasskey(for username: String) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration
    
    // MARK: - Passkey Authentication
    func authenticateWithPasskey() async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion
    
    // MARK: - Encryption/Decryption
    func encryptMnemonic(_ mnemonic: String, using credential: Data) throws -> Data
    func decryptMnemonic(_ encryptedData: Data, using credential: Data) throws -> String
    
    // MARK: - Storage
    func saveEncryptedMnemonic(_ encryptedData: Data) async throws
    func loadEncryptedMnemonic() async throws -> Data?
}
```

#### 2. Enhanced SecurityService

Update `Arke/Shared/Services/SecurityService.swift`:

```swift
// Add to SecurityService
enum WalletBackupMode {
    case passkey          // iCloud Keychain sync via Passkey
    case manual           // Traditional 12-word phrase
    case hybrid           // Passkey + manual export option
}

func saveMnemonic(
    _ mnemonic: String, 
    mode: WalletBackupMode,
    requireBiometric: Bool = false
) async throws

func getCurrentBackupMode() -> WalletBackupMode
func migrateToPasskey() async throws
func migrateToManual() async throws
```

#### 3. Data Flow

```
┌─────────────────────────────────────────────────────┐
│                 Wallet Creation                      │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │ Generate        │
              │ BIP39 Mnemonic  │
              └─────────────────┘
                        │
           ┌────────────┴────────────┐
           │                         │
           ▼                         ▼
    ┌─────────────┐          ┌─────────────┐
    │  PASSKEY    │          │   MANUAL    │
    │    MODE     │          │    MODE     │
    └─────────────┘          └─────────────┘
           │                         │
           ▼                         ▼
    ┌─────────────┐          ┌─────────────┐
    │ 1. Create   │          │ 1. Show     │
    │    Passkey  │          │    12-word  │
    │             │          │    phrase   │
    │ 2. Encrypt  │          │             │
    │    mnemonic │          │ 2. User     │
    │    with     │          │    writes   │
    │    Passkey  │          │    down     │
    │             │          │             │
    │ 3. Store in │          │ 3. Store    │
    │    iCloud   │          │    in local │
    │    Keychain │          │    Keychain │
    │             │          │    only     │
    │ 4. Store    │          │             │
    │    local    │          │ 4. No sync  │
    │    copy for │          │             │
    │    speed    │          │             │
    └─────────────┘          └─────────────┘
```

#### 4. VTXO Recovery System (Pragmatic Approach) ✨ NEW

**Current Bark Recovery Infrastructure (Server-Side):**

Per Bark maintainer conversation (2026-04-07):
- ✅ **Arkoor-received VTXOs**: Auto-recovered via `sync_mailbox` (full VTXO bytes in main mailbox)
- ❌ **Round/Board VTXOs**: VTXO IDs posted to recovery mailbox, but client ignores them
- ✅ **Recovery API exists**: `GET /api/v1/wallet/vtxos/{id}/encoded` returns full hex
- ✅ **Import API exists**: `POST /api/v1/wallet/import-vtxo` (via `importVtxo()` in WalletManager)

**Pragmatic Recovery Strategy:**

Instead of implementing local VTXO export (requires Rust FFI changes), leverage the **existing server recovery mailbox**:

1. **Passkey backs up mnemonic only** (simple, no VTXO export needed)
2. **Server recovery mailbox stores VTXO IDs** (already happening)
3. **Client implements recovery mailbox reader** (fetch IDs → download VTXOs → import)

**Recovery Flow:**
```
1. Authenticate with Passkey (or enter mnemonic manually)
2. Decrypt mnemonic from iCloud Keychain
3. Initialize wallet with mnemonic
4. Call sync() → auto-recovers arkoor-received VTXOs ✅
5. Fetch VTXO IDs from recovery mailbox (new implementation needed)
6. For each ID: GET /api/v1/wallet/vtxos/{id}/encoded
7. Import each VTXO using importVtxo(vtxoBase64:)
8. Restore CloudKit data (transactions, contacts, tags)
9. Sync with ASP to update VTXO states
```

**Implementation Requirements:**

```swift
// Add to BarkWalletProtocol.swift
func getRecoveryVtxoIds() async throws -> [String]
func getEncodedVtxo(vtxoId: String) async throws -> String

// Add to WalletManager.swift
func recoverVtxosFromMailbox() async throws -> RecoveryResult {
    // 1. Get VTXO IDs from recovery mailbox
    let vtxoIds = try await wallet.getRecoveryVtxoIds()
    
    // 2. Fetch and import each VTXO
    var recovered = 0
    var failed = 0
    for vtxoId in vtxoIds {
        do {
            let encoded = try await wallet.getEncodedVtxo(vtxoId: vtxoId)
            try await importVtxo(vtxoBase64: encoded)
            recovered += 1
        } catch {
            failed += 1
        }
    }
    
    return RecoveryResult(total: vtxoIds.count, recovered: recovered, failed: failed)
}
```

**Advantages:**
- ✅ **No Rust FFI changes needed** (uses existing server infrastructure)
- ✅ **Server already stores VTXO IDs** (no new server work)
- ✅ **Simple Passkey implementation** (mnemonic only)
- ✅ **Full recovery capability** (via server mailbox + sync)
- ✅ **Works today** (just needs client implementation)

**Trade-offs:**
- ⚠️ **Requires ASP availability** for full recovery (not 100% self-custody)
- ⚠️ **No cross-ASP migration** (VTXOs tied to specific ASP)
- ⚠️ **Privacy consideration**: ASP knows recovery is happening

**Future Enhancement (Optional):**
Once Bark implements automatic recovery mailbox processing, steps 5-7 become automatic.

**Manual Export Option (Level 3 Self-Custody):**
For users who want ASP-independent backup:
- Export mnemonic manually (already possible)
- CloudKit backup (already exists)
- Wait for Bark's automatic recovery mailbox processing (server-side work)
- OR wait for local VTXO export implementation (Rust FFI work)

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal:** Create core Passkey infrastructure + recovery mailbox client

**Tasks:**
1. **Implement recovery mailbox client** ⚠️
   - Add `getRecoveryVtxoIds()` to BarkWalletProtocol
   - Add `getEncodedVtxo(vtxoId:)` to BarkWalletProtocol
   - Implement in BarkWalletFFI using Bark's existing API
   - Add `recoverVtxosFromMailbox()` to WalletManager
   - Test recovery flow: mnemonic → sync → recovery mailbox → import

2. Create `PasskeyService.swift` in `Arke/Shared/Services/`
   - Implement Passkey registration flow
   - Implement Passkey authentication flow
   - Add encryption/decryption using CryptoKit
   - Add iCloud Keychain storage

3. Update `SecurityService.swift`
   - Add `WalletBackupMode` enum
   - Add mode-aware `saveMnemonic()` method
   - Add migration methods
   - Keep backward compatibility

4. Add entitlements
   - Update `Arké mobile.entitlements`
   - Add "Associated Domains" for Passkey
   - Ensure iCloud Keychain is enabled

**Files Modified:**
- `Arke/Shared/Data/BarkWalletFFI.swift` (add recovery mailbox methods)
- `Arke/Shared/Data/BarkWalletProtocol.swift` (add recovery mailbox protocol)
- `Arke/Shared/Data/WalletManager.swift` (add recoverVtxosFromMailbox)
- `Arke/Shared/Services/PasskeyService.swift` (new)
- `Arke/Shared/Services/SecurityService.swift`
- `Arke/Arké mobile/Arke_mobile.entitlements`
- `Arke/Arké/Arké.entitlements`

**Testing:**
- Test recovery mailbox fetching VTXO IDs
- Test VTXO download and import flow
- Test with multiple VTXOs (1, 10, 50)
- Test arkoor-received VTXOs (auto via sync)
- Test round/board VTXOs (via recovery mailbox)
- Unit tests for encryption/decryption
- Test Passkey creation in simulator
- Test iCloud Keychain storage

---

### Phase 2: Wallet Creation UI (Week 3-4)

**Goal:** Add Passkey option to wallet creation flow

**Tasks:**
1. Create backup mode selection view
   - `BackupModeSelectionView_iOS.swift`
   - Show two options: Passkey (recommended) vs Manual
   - Clear explanation of each approach

2. Update `CreateWalletView_iOS.swift`
   - Add backup mode parameter
   - Call appropriate creation method based on mode
   - Handle Passkey creation errors gracefully

3. Create Passkey creation success view
   - Show confirmation that Passkey was created
   - Explain cross-device sync
   - Option to view/export mnemonic anyway (hybrid mode)

**Files Modified:**
- `Arke/Arké mobile/Views/FirstUse/BackupModeSelectionView_iOS.swift` (new)
- `Arke/Arké mobile/Views/FirstUse/CreateWalletView_iOS.swift`
- `Arke/Arké mobile/Views/FirstUse/OnboardingFlow_iOS.swift`
- `Arke/Shared/Data/WalletManager.swift` (add mode parameter)

**UI Flow:**
```
OnboardingFlow
    ↓
Choose Backup Method
    ├─ Passkey (Recommended)
    │   ↓
    │   Face ID Prompt
    │   ↓
    │   Creating Wallet...
    │   ↓
    │   Success! (with optional "View Recovery Phrase" button)
    │
    └─ Manual Backup (Advanced)
        ↓
        Creating Wallet...
        ↓
        Write Down Your 12 Words
        ↓
        Confirm Words
```

**Testing:**
- Test Passkey creation flow
- Test Face ID prompt
- Test error handling (user cancels, Face ID unavailable)
- Test on physical device

---

### Phase 3: Recovery Flow (Week 5-6)

**Goal:** Allow users to recover wallet using Passkey + VTXO import

**Tasks:**
1. Update `LinkWalletView_iOS.swift`
   - Detect if Passkey exists in iCloud Keychain
   - Show "Recover with Face ID" button if available
   - Show "Import from QR Code" as alternative
   - Show recovery progress (mnemonic → VTXOs → CloudKit)

2. Create complete Passkey recovery flow
   - Authenticate with Face ID
   - Decrypt mnemonic from iCloud Keychain
   - Import wallet using decrypted mnemonic
   - **Call sync() to auto-recover arkoor-received VTXOs** ✨ NEW
   - **Fetch VTXO IDs from recovery mailbox** ✨ NEW
   - **Download and import round/board VTXOs** ✨ NEW
   - Restore from CloudKit (transactions, contacts, tags)
   - Sync with ASP to update VTXO states

3. Handle VTXO recovery scenarios
   - Success: All VTXOs recovered (sync + recovery mailbox)
   - Partial: Some VTXOs failed (expired, already claimed)
   - Offline: ASP unavailable (can still restore mnemonic, defer VTXO recovery)
   - Show recovery progress UI (arkoor VTXOs → round/board VTXOs → CloudKit)

4. Handle migration scenarios
   - Manual → Passkey upgrade (with VTXO backup)
   - Passkey → Manual downgrade (export bundle first)

**Files Modified:**
- `Arke/Arké mobile/Views/FirstUse/LinkWalletView_iOS.swift`
- `Arke/Arké mobile/Views/FirstUse/PasskeyRecoveryView_iOS.swift` (new)
- `Arke/Shared/Services/SecurityService.swift` (add recovery methods)

**Testing:**
- Test recovery on new device with VTXOs
- Test recovery with iCloud sync delay
- Test arkoor VTXO auto-recovery (via sync)
- Test round/board VTXO recovery (via recovery mailbox)
- Test partial VTXO recovery (some fail, some succeed)
- Test recovery when ASP is offline (mnemonic only)
- Test fallback to QR code if Passkey fails
- Test recovery progress UI shows each stage

---

### Phase 4: Settings Integration (Week 7-8)

**Goal:** Allow users to manage backup mode and export complete wallet

**Tasks:**
1. Update `SecuritySettingsView.swift`
   - Show current backup mode
   - "Upgrade to Passkey" button (if manual)
   - "Switch to Manual Backup" button (if Passkey)
   - "Export Recovery Phrase" option (always available)
   - Show last VTXO backup time (if Passkey mode)

2. Create mnemonic export flow
   - Require Face ID authentication
   - Show mnemonic with copy/share options
   - Warning about security implications

3. **Add recovery status UI**
   - Show "Recovering wallet..." progress screen
   - Stage 1: Mnemonic restored ✓
   - Stage 2: Arkoor VTXOs recovered (via sync) ✓
   - Stage 3: Round/Board VTXOs recovered (via mailbox) ✓
   - Stage 4: CloudKit data restored ✓
   - Handle ASP offline gracefully (defer VTXO recovery)

**Files Modified:**
- `Arke/Arké mobile/Views/Settings/SecuritySettingsView_iOS.swift` (new/update existing)
- `Arke/Arké mobile/Views/Settings/ExportRecoveryPhraseView_iOS.swift` (new)
- `Arke/Arké mobile/Views/Settings/BackupModeManagementView_iOS.swift` (new)
- `Arke/Arké mobile/Views/FirstUse/WalletRecoveryProgressView_iOS.swift` (new)

**UI Structure:**
```
Settings → Security & Backup
    ├─ Backup Method
    │   ├─ Current: Passkey (iCloud)
    │   └─ Change to Manual (Advanced)
    │
    ├─ Export for Recovery
    │   └─ Export Recovery Phrase (Mnemonic only)
    │
    └─ Devices with Access
        └─ [List of devices from DeviceRegistration]
```

**Testing:**
- Test mode switching
- Test mnemonic export with biometric auth
- Test recovery progress UI
- Test on devices without Face ID

---

### Phase 5: Migration & Polish (Week 9-10)

**Goal:** Handle existing users and edge cases

**Tasks:**
1. Detect existing users without Passkey
   - Show one-time migration prompt
   - Explain benefits of Passkey
   - Allow dismissal (don't force)

2. Handle edge cases
   - User disabled iCloud Keychain
   - User disabled Face ID/passcode
   - Passkey sync failures
   - Multiple devices with timing issues

3. Add analytics/logging
   - Track Passkey adoption rate
   - Track recovery success rate
   - Track mode switching patterns

4. Documentation
   - Update user-facing help docs
   - Update developer docs
   - Add troubleshooting guide

**Files Modified:**
- `Arke/Shared/Services/MigrationService.swift` (new)
- `Arke/Arké mobile/Views/Settings/PasskeyMigrationPromptView_iOS.swift` (new)
- Various files for error handling improvements

**Testing:**
- Test migration from manual to Passkey
- Test all error scenarios
- User acceptance testing

---

## File Changes Required

### New Files

```
Arke/Shared/Services/
├─ PasskeyService.swift
└─ MigrationService.swift (Phase 5)

Arke/Arké mobile/Views/FirstUse/
├─ BackupModeSelectionView_iOS.swift
└─ PasskeyRecoveryView_iOS.swift

Arke/Arké mobile/Views/Settings/
├─ SecuritySettingsView_iOS.swift (may already exist)
├─ ExportRecoveryPhraseView_iOS.swift
├─ BackupModeManagementView_iOS.swift
└─ PasskeyMigrationPromptView_iOS.swift (Phase 5)

Arke/Shared/Docs/
└─ PASSKEY_USER_GUIDE.md (user-facing)
```

### Modified Files

```
Arke/Shared/Services/
└─ SecurityService.swift
    - Add WalletBackupMode enum
    - Add mode-aware save/load methods
    - Add migration methods

Arke/Shared/Data/
└─ WalletManager.swift
    - Add createWallet(mode:) parameter
    - Update initialization to detect mode

Arke/Arké mobile/Views/FirstUse/
├─ CreateWalletView_iOS.swift
│   - Add mode selection
│   - Handle Passkey flow
├─ LinkWalletView_iOS.swift
│   - Add Passkey recovery option
└─ OnboardingFlow_iOS.swift
    - Add mode selection step

Arke/Arké mobile/
├─ Arke_mobile.entitlements
│   - Add Associated Domains
│   - Ensure iCloud Keychain
└─ Arké/Arké.entitlements
    - Same updates for macOS target

Arke/Shared/Models/
└─ WalletConfiguration.swift (if exists)
    - Add backupMode property
```

---

## Security Considerations

### Encryption Approach

**Passkey-derived encryption:**
```swift
// Use Passkey credential ID as key derivation material
let credentialID = passkeyAssertion.credentialID
let salt = "com.arke.wallet.v1".data(using: .utf8)!

// Derive encryption key using HKDF
let symmetricKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: credentialID),
    salt: salt,
    outputByteCount: 32
)

// Encrypt mnemonic using ChaChaPoly
let sealedBox = try ChaChaPoly.seal(
    mnemonicData,
    using: symmetricKey
)

// Store sealed box in iCloud Keychain
```

### Storage Locations

**Passkey Mode:**
- **Local Keychain**: Unencrypted mnemonic (fast access, never syncs)
  - `kSecAttrSynchronizable = false`
  - `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  
- **iCloud Keychain**: Encrypted mnemonic (backup, syncs)
  - `kSecAttrSynchronizable = true`
  - `kSecAttrAccessControl = .biometryCurrentSet`
  - Requires Face ID to decrypt

**Manual Mode:**
- **Local Keychain only**: Unencrypted mnemonic
  - `kSecAttrSynchronizable = false`
  - User responsible for backup

### Threat Model

**Passkey protects against:**
- ✅ Device loss (syncs to new device)
- ✅ Accidental deletion (recoverable from iCloud)
- ✅ User forgot password (uses biometric)
- ✅ Unauthorized iCloud access (encrypted, requires biometric)

**Passkey does NOT protect against:**
- ❌ Apple account compromise + biometric compromise
- ❌ Malicious apps with Keychain access (same as current)
- ❌ Physical coercion to unlock with Face ID
- ❌ iCloud infrastructure breach (encrypted at rest, but Apple holds keys)

**Mitigation:**
- Always offer manual export option
- Educate users about trade-offs
- Consider hardware security key support later

---

## User Experience Flow

### First-Time User Journey (Passkey Mode)

```
1. User opens app
   ↓
2. "Welcome to Arke" (intro video)
   ↓
3. "How would you like to protect your wallet?"
   
   ┌──────────────────────────────────────────┐
   │  🔐 Face ID Protection (Recommended)     │
   │                                          │
   │  ✓ Automatic backup to iCloud            │
   │  ✓ Works on all your Apple devices       │
   │  ✓ No recovery phrase to remember        │
   │                                          │
   │       [Continue with Face ID]            │
   └──────────────────────────────────────────┘
   
   ┌──────────────────────────────────────────┐
   │  📝 Manual Backup (Advanced)             │
   │                                          │
   │  ✓ Full self-custody                     │
   │  ✓ No iCloud dependency                  │
   │  ✓ You manage 12-word phrase             │
   │                                          │
   │       [Use Manual Backup]                │
   └──────────────────────────────────────────┘
   
   ↓ (User selects Passkey)
   
4. Face ID prompt appears
   "Arke wants to create a secure wallet 
    protected by Face ID"
   
   [Face ID animation]
   
   ↓
   
5. Creating your wallet...
   [Magic wallet creation animation]
   
   ✅ Success!
   
   Your wallet is protected by Face ID and 
   automatically backed up to iCloud.
   
   Optional: [View Recovery Phrase Anyway]
   
   [Get Started]
```

### Multi-Device Setup (Passkey Mode)

```
User gets new iPhone
   ↓
Signs in with Apple ID
   ↓
Opens Arke app
   ↓
"Welcome back!"

We found your wallet in iCloud.
   
   [Unlock with Face ID]
   
   ↓
   
Face ID prompt
   ↓
   
✅ Wallet restored!

Restoring your data...
├─ Balance: ✓
├─ Transactions: ✓
├─ Contacts: ✓
└─ Tags: ✓

[Continue]
```

### Settings Management

```
Settings → Security & Backup

┌─────────────────────────────────────┐
│ Backup Method                       │
│                                     │
│ Current: Face ID (iCloud)           │
│                                     │
│ Your wallet syncs across all your  │
│ Apple devices using iCloud.         │
│                                     │
│ [Change Backup Method...]           │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ Export for Self-Custody             │
│                                     │
│ [Export Recovery Phrase]            │
│                                     │
│ [Export VTXOs] Coming Soon          │
│                                     │
│ Save these securely to maintain     │
│ access even without iCloud.         │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ Devices with Access                 │
│                                     │
│ • iPhone 15 Pro (This device)       │
│ • iPad Pro (Last active 2 days ago) │
│                                     │
│ [Manage Devices...]                 │
└─────────────────────────────────────┘
```

---

## Testing Strategy

### Unit Tests

```swift
// PasskeyServiceTests.swift
class PasskeyServiceTests: XCTestCase {
    func testEncryptionDecryption()
    func testPasskeyCreation()
    func testPasskeyAuthentication()
    func testKeychainStorage()
    func testMigrationToPasskey()
    func testMigrationToManual()
}

// SecurityServiceTests.swift (additions)
func testBackupModeDetection()
func testModeSwitching()
func testPasskeyFallback()
```

### Integration Tests

```swift
// WalletCreationTests.swift
func testCreateWalletWithPasskey()
func testCreateWalletManual()
func testRecoverWalletWithPasskey()
func testRecoverWalletFromQR()
func testMultiDeviceSync()
```

### Manual Testing Checklist

**Phase 1:**
- [ ] Passkey creation on physical device
- [ ] Face ID prompt appears correctly
- [ ] Encryption/decryption works
- [ ] iCloud Keychain storage persists

**Phase 2:**
- [ ] Backup mode selection appears
- [ ] Both flows complete successfully
- [ ] Error handling works (user cancels)
- [ ] UI is clear and intuitive

**Phase 3:**
- [ ] Recovery on new device works
- [ ] Face ID recovery is seamless
- [ ] QR code fallback works
- [ ] Migration preserves all data

**Phase 4:**
- [ ] Settings show correct mode
- [ ] Mode switching works both ways
- [ ] Export shows mnemonic correctly
- [ ] All changes persist

**Phase 5:**
- [ ] Existing users see migration prompt
- [ ] Migration doesn't lose data
- [ ] Edge cases handled gracefully

### Device Testing Matrix

| Device | iOS Version | iCloud | Face ID | Test |
|--------|-------------|--------|---------|------|
| iPhone 15 Pro | 18.0 | ✓ | ✓ | Primary |
| iPhone SE | 17.0 | ✓ | ✗ (Touch ID) | Fallback |
| iPad Pro | 18.0 | ✓ | ✓ | Multi-device |
| Simulator | 18.0 | ✗ | ✗ | Dev testing |

---

## Future Enhancements

### Phase 6+: Advanced Features

1. **VTXO Export/Import**
   - When Ark protocol supports VTXO portability
   - Add export button next to mnemonic export
   - Full self-custody achieved

2. **Hardware Security Key Support**
   - Support USB/NFC security keys
   - Even more secure than biometrics
   - For paranoid users

3. **Cross-Platform Passkey**
   - Android support via FIDO2
   - Web wallet support
   - True cross-platform sync

4. **Social Recovery**
   - Shamir's Secret Sharing
   - Split recovery phrase across trusted contacts
   - Recover without any single backup

5. **Inheritance/Dead Man's Switch**
   - Time-locked recovery
   - Trusted contacts can recover after N months
   - Bitcoin inheritance solved

---

## Success Metrics

### User Experience
- **Wallet creation time**: < 30 seconds (vs 5+ minutes for manual)
- **Multi-device setup time**: < 10 seconds (vs 2+ minutes for QR)
- **User satisfaction**: Track via in-app survey
- **Support requests**: Monitor backup-related issues

### Technical
- **Passkey adoption rate**: Target 80%+ of new users
- **Recovery success rate**: Target 99%+
- **Mode switching rate**: Track migrations both ways
- **Error rate**: < 1% of Passkey operations

### Business
- **User retention**: Improved onboarding = better retention
- **Viral growth**: Easier setup = more referrals
- **Competitive advantage**: Best-in-class Bitcoin wallet UX

---

## Risk Mitigation

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| iCloud Keychain failure | High | Low | Always keep local copy + manual export |
| Passkey API changes | Medium | Medium | Follow Apple's beta releases closely |
| Encryption bug | Critical | Low | Extensive testing + code review |
| Sync timing issues | Medium | Medium | Robust retry logic + user feedback |

### User Experience Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| User doesn't trust iCloud | Medium | Medium | Offer manual mode prominently |
| User loses Apple ID | High | Low | Encourage manual export |
| Confusion about modes | Medium | Medium | Clear UI + education |
| Lock-in perception | Low | Medium | Emphasize export options |

---

## Appendix

### Passkey API Reference

```swift
import AuthenticationServices

// Registration
let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
    relyingPartyIdentifier: "arke.app"
)

let challenge = Data() // From server or local generation
let userID = Data() // Unique user identifier

let registrationRequest = provider.createCredentialRegistrationRequest(
    challenge: challenge,
    name: "user@example.com",
    userID: userID
)

// Authentication
let assertionRequest = provider.createCredentialAssertionRequest(
    challenge: challenge
)

// Present UI
let controller = ASAuthorizationController(
    authorizationRequests: [registrationRequest]
)
controller.delegate = self
controller.presentationContextProvider = self
controller.performRequests()
```

### Encryption Example

```swift
import CryptoKit

func encryptMnemonic(_ mnemonic: String, credentialID: Data) throws -> Data {
    // Derive key from Passkey credential
    let salt = "com.arke.wallet.v1".data(using: .utf8)!
    let key = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: credentialID),
        salt: salt,
        outputByteCount: 32
    )
    
    // Encrypt with ChaChaPoly (authenticated encryption)
    let mnemonicData = mnemonic.data(using: .utf8)!
    let sealedBox = try ChaChaPoly.seal(mnemonicData, using: key)
    
    // Return combined (nonce + ciphertext + tag)
    return sealedBox.combined
}

func decryptMnemonic(_ encrypted: Data, credentialID: Data) throws -> String {
    // Derive same key
    let salt = "com.arke.wallet.v1".data(using: .utf8)!
    let key = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: credentialID),
        salt: salt,
        outputByteCount: 32
    )
    
    // Decrypt
    let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
    let decryptedData = try ChaChaPoly.open(sealedBox, using: key)
    
    return String(data: decryptedData, encoding: .utf8)!
}
```

### Keychain Storage Example

```swift
func saveToiCloudKeychain(_ data: Data, account: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.arke.wallet.passkey",
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrSynchronizable as String: true, // iCloud sync!
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
    ]
    
    // Delete old entry
    SecItemDelete(query as CFDictionary)
    
    // Add new entry
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed(status)
    }
}
```

### VTXO Export/Import Implementation

**Current State (As of 2026-04-07):**

```swift
// ✅ IMPORT EXISTS - WalletManager.swift:1508
func importVtxo(vtxoBase64: String) async throws {
    guard let wallet = wallet else {
        throw BarkErrorArke.commandFailed("Wallet not initialized")
    }
    try await wallet.importVtxo(vtxoBase64: vtxoBase64)
}

// ❌ EXPORT MISSING - Needs implementation in Bark Rust library
// Required additions:

// 1. Add to BarkWalletProtocol.swift:
func exportVtxo(vtxoId: String) async throws -> String
func exportAllVtxos() async throws -> [String: String]

// 2. Add to BarkWalletFFI.swift (Swift bindings):
func exportVtxo(vtxoId: String) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        // Call Rust FFI function
        bark_export_vtxo(wallet_ptr, vtxo_id, continuation)
    }
}

// 3. Add to Bark Rust library (bark/src/lib.rs or similar):
#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        fn bark_export_vtxo(
            wallet: *mut Wallet,
            vtxo_id: String,
        ) -> Result<String, BarkError>;
    }
}

fn bark_export_vtxo(
    wallet: *mut Wallet,
    vtxo_id: String,
) -> Result<String, BarkError> {
    let wallet = unsafe { &*wallet };
    let vtxo = wallet.get_vtxo_by_id(&vtxo_id)?;
    let serialized = vtxo.serialize()?;
    Ok(base64::encode(&serialized))
}
```

**VtxoBackupService Architecture:**

```swift
@MainActor
class VtxoBackupService {
    private let walletManager: WalletManager
    private let securityService: SecurityService
    private let passkeyService: PasskeyService
    
    // MARK: - Export
    
    /// Export all VTXOs to encrypted bundle
    func exportWalletBundle(
        password: String? = nil,
        usePasskey: Bool = true
    ) async throws -> WalletBundle {
        // 1. Get mnemonic
        let mnemonic = try await walletManager.getMnemonic()
        
        // 2. Export all VTXOs
        let vtxos = try await walletManager.spendableVtxos()
        var vtxoMap: [String: String] = [:]
        for vtxo in vtxos {
            let serialized = try await walletManager.exportVtxo(vtxoId: vtxo.vtxoId)
            vtxoMap[vtxo.vtxoId] = serialized
        }
        
        // 3. Get metadata
        let blockHeight = try await walletManager.estimatedBlockHeight ?? 0
        let networkName = walletManager.currentNetworkName
        
        // 4. Create bundle
        let bundle = WalletBundle(
            version: 1,
            exportDate: Date(),
            networkName: networkName,
            mnemonic: mnemonic,
            vtxos: vtxoMap,
            blockHeight: UInt32(blockHeight),
            metadata: WalletBundle.Metadata(
                vtxoCount: vtxoMap.count,
                totalSats: vtxos.reduce(0) { $0 + $1.amountSats }
            )
        )
        
        // 5. Encrypt bundle
        if usePasskey {
            return try await encryptWithPasskey(bundle)
        } else if let password = password {
            return try encryptWithPassword(bundle, password: password)
        } else {
            throw BarkErrorArke.commandFailed("Must provide password or use Passkey")
        }
    }
    
    // MARK: - Import
    
    /// Import wallet from encrypted bundle
    func importWalletBundle(
        _ encryptedBundle: Data,
        password: String? = nil,
        usePasskey: Bool = true
    ) async throws -> ImportResult {
        // 1. Decrypt bundle
        let bundle: WalletBundle
        if usePasskey {
            bundle = try await decryptWithPasskey(encryptedBundle)
        } else if let password = password {
            bundle = try decryptWithPassword(encryptedBundle, password: password)
        } else {
            throw BarkErrorArke.commandFailed("Must provide password or use Passkey")
        }
        
        // 2. Validate bundle
        guard bundle.version == 1 else {
            throw BarkErrorArke.commandFailed("Unsupported bundle version: \(bundle.version)")
        }
        
        guard bundle.networkName == walletManager.currentNetworkName else {
            throw BarkErrorArke.commandFailed("Network mismatch: expected \(walletManager.currentNetworkName), got \(bundle.networkName)")
        }
        
        // 3. Import mnemonic (initialize wallet)
        try await walletManager.importWallet(
            network: bundle.networkName,
            asp: nil,
            mnemonic: bundle.mnemonic
        )
        
        // 4. Import VTXOs (one by one, track successes/failures)
        var imported = 0
        var failed = 0
        var errors: [String: String] = [:]
        
        for (vtxoId, vtxoBase64) in bundle.vtxos {
            do {
                try await walletManager.importVtxo(vtxoBase64: vtxoBase64)
                imported += 1
            } catch {
                failed += 1
                errors[vtxoId] = error.localizedDescription
            }
        }
        
        // 5. Return result
        return ImportResult(
            totalVtxos: bundle.vtxos.count,
            imported: imported,
            failed: failed,
            errors: errors
        )
    }
    
    // MARK: - Automatic Backup
    
    /// Backup VTXOs to iCloud Keychain after transaction
    func automaticBackup() async throws {
        guard securityService.getCurrentBackupMode() == .passkey else {
            return // Only auto-backup in Passkey mode
        }
        
        let bundle = try await exportWalletBundle(usePasskey: true)
        try await saveToiCloudKeychain(bundle)
        
        // Update last backup time
        UserDefaults.standard.set(Date(), forKey: "lastVtxoBackupTime")
    }
}

struct WalletBundle: Codable {
    let version: Int
    let exportDate: Date
    let networkName: String
    let mnemonic: String  // Will be encrypted
    let vtxos: [String: String]  // vtxoId -> base64
    let blockHeight: UInt32
    let metadata: Metadata
    
    struct Metadata: Codable {
        let vtxoCount: Int
        let totalSats: UInt64
    }
}

struct ImportResult {
    let totalVtxos: Int
    let imported: Int
    let failed: Int
    let errors: [String: String]
    
    var isPartialSuccess: Bool {
        imported > 0 && failed > 0
    }
    
    var isComplete: Bool {
        failed == 0
    }
}
```

---

## Conclusion

Passkey integration with **server-side recovery mailbox** represents a **pragmatic UX improvement** for Arke while achieving practical recovery. This approach leverages existing Bark infrastructure and can be implemented without Rust FFI changes.

**Key Benefits:**
- ✅ Eliminates manual backup friction (Passkey seamlessness)
- ✅ Seamless multi-device experience (iCloud sync)
- ✅ **Complete wallet recovery** (mnemonic + recovery mailbox) ✨
- ✅ **Practical self-custody** (requires ASP cooperation)
- ✅ Simple implementation (no Rust FFI changes needed)
- ✅ Consistent with Ark's existing iCloud usage

**Competitive Advantage:**

Arke offers a **pragmatic balance**:
1. Face ID-based seamless recovery (like Coinbase Wallet)
2. PLUS off-chain state recovery via server (practical approach)
3. PLUS on-chain key control (traditional wallet security)

This pragmatic approach prioritizes **working recovery today** over theoretical 100% self-custody.

**Trade-offs Acknowledged:**
- ⚠️ Requires ASP availability for VTXO recovery
- ⚠️ Not 100% self-custody (but practical for 99% of use cases)
- ⚠️ Privacy: ASP knows when recovery occurs
- ✅ Mnemonic still gives on-chain key control
- ✅ Can be enhanced later with local VTXO export

**Implementation Timeline:** ~8-10 weeks (5 phases)

**Critical Dependencies:**
1. Recovery mailbox client implementation (Swift only)
2. Passkey implementation (Standard iOS APIs)
3. iCloud Keychain storage (Already enabled)

**Next Steps:**
1. Review and approve this pragmatic plan
2. Create detailed tickets for Phase 1
3. Begin PasskeyService implementation
4. Implement recovery mailbox client (getRecoveryVtxoIds, getEncodedVtxo)
5. Test complete recovery flow (mnemonic → sync → recovery mailbox → import)
6. Iterate based on testing feedback

---

**Document Version:** 3.0 (Pragmatic Approach)  
**Last Updated:** 2026-04-07  
**Author:** Assistant  
**Status:** Pragmatic Recovery Strategy - Ready for Review  
**Major Changes:**
- **v3.0:** Pivoted to server recovery mailbox (pragmatic approach)
- Removed local VTXO export dependency (deferred to future)
- Simplified implementation to Swift-only changes
- Acknowledged ASP-dependency trade-off
- Maintained high priority for UX improvement
