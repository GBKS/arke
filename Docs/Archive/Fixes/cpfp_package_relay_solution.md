# CPFP Package Relay Solution Plan

> **📦 Archived 2026-07-09 — not implemented.** Neither the Bitcoin Core RPC option nor package-enabled Esplora was built. Instead, the Bark 0.11 bindings update switched the app to Bark's built-in BDK onchain wallet, which broadcasts exit packages internally, making this plan moot. See `bark_issue_cpfp_package_relay.md` (same folder) for the original problem analysis.

## Problem Confirmed

Bark's exit system **requires package relay support** in the chain backend. The current implementation broadcasts transactions individually via Esplora, which doesn't support package relay.

## Bark's Architecture (from maintainer response)

### How It's Supposed to Work

```
Exit State Machine
    ↓
Creates CPFP child via onchain wallet callbacks ✅ (We have this)
    ↓
Transaction Manager broadcasts [parent, child] as package
    ↓
Via ChainSource::broadcast_package(...) ✅ (Bark core handles this)
    ↓
Esplora backend calls client.submit_package(&txs, ...) ❌ (Our Esplora doesn't support this)
```

### What's Missing

Our integration bypasses Bark's package broadcast path because:

1. **We're not using Bark's ChainSource** - We're using Esplora via BDK directly
2. **Our Esplora doesn't support package relay** - esplora.signet.2nd.dev may not expose the package endpoint
3. **The broadcast goes through wrong path** - Individual `broadcastTransaction()` calls instead of package submission

### Key Facts from Bark Maintainer

- ✅ Zero-fee parents are **intentional and tested**
- ✅ Empty witness on P2A outputs is **correct by design**
- ✅ Package broadcast is **required, not optional**
- ✅ Bark core handles package broadcast via `ChainSource::broadcast_package()`
- ❌ There is **no wallet callback** for package broadcast (by design)
- 📦 Bark pins `esplora-client` version that supports `submit_package`

## Solutions

### Option 1: Use Bitcoin Core RPC ⭐ RECOMMENDED

**Add package relay support via Bitcoin Core node**

#### Pros:
- Full package relay support (native `submitpackage` RPC)
- Most robust solution
- Matches Bark's intended design
- Works for all unilateral exits

#### Cons:
- Requires Bitcoin Core node access
- More complex infrastructure
- Need to maintain both Esplora (for chain data) and Core (for broadcast)

#### Implementation:
1. Add Bitcoin Core RPC client to BDKOnchainWallet
2. Add `broadcastPackage(txHexes: [String])` method
3. Expose this through Bark FFI callbacks
4. Route package broadcasts to Core, single txs to Esplora

---

### Option 2: Use Package-Enabled Esplora

**Find or deploy an Esplora instance with package support**

#### Pros:
- Clean solution if available
- No need for separate Core node
- Simpler architecture

#### Cons:
- May not be available on public Signet Esplora
- Would need to deploy own Esplora instance
- Need to verify package endpoint compatibility

#### Implementation:
1. Check if esplora.signet.2nd.dev supports package endpoint
2. If not, deploy own Esplora with package support
3. Add package broadcast method to BDKOnchainWallet
4. Use esplora-client's `submit_package` equivalent

---

### Option 3: Fallback Mode with Min Relay Fees ⚠️ WORKAROUND ONLY

**Make parents pay minimum relay fee so both can broadcast individually**

#### Pros:
- Works with any Esplora
- No infrastructure changes needed
- Simple implementation

#### Cons:
- **Not Bark's intended design**
- Would require modifying Bark's exit logic
- May break assumptions in exit state machine
- Maintainer explicitly said this is a "workaround for backends without package support"

#### Implementation:
Would require changes to Bark core (not recommended)

---

## Recommended Path Forward

### Phase 1: Quick Investigation (15 mins)

Test if current Esplora supports packages:

```bash
# Check if Esplora has package endpoint
curl https://esplora.signet.2nd.dev/api/tx/submit-package \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"txs":["..."]}'
```

### Phase 2: Implement Bitcoin Core RPC (2-3 hours)

If Esplora doesn't support packages:

1. **Add Bitcoin Core RPC Client**
   ```swift
   // Shared/Data/BitcoinCoreRPC.swift
   final class BitcoinCoreRPC {
       func submitPackage(txHexes: [String]) async throws -> [String]
   }
   ```

2. **Extend BDKOnchainWallet**
   ```swift
   // Add to BDKOnchainWallet.swift
   private let bitcoinCoreRPC: BitcoinCoreRPC?
   
   func broadcastPackage(txHexes: [String]) throws -> [String] {
       if let rpc = bitcoinCoreRPC {
           return try rpc.submitPackage(txHexes: txHexes)
       } else {
           // Fallback: broadcast individually (will fail for CPFP)
           return try txHexes.map { try broadcastTransaction(txHex: $0) }
       }
   }
   ```

3. **Update Bark FFI Integration**
   - Expose package broadcast through custom callbacks
   - Route CPFP packages through this path

### Phase 3: Configuration

Add Bitcoin Core connection settings:

```swift
struct NetworkConfig {
    // Existing Esplora config...
    var esploraUrl: String
    
    // New Bitcoin Core RPC config
    var bitcoinCoreRpcUrl: String?  // Optional: "http://localhost:38332"
    var bitcoinCoreRpcUser: String?
    var bitcoinCoreRpcPassword: String?
}
```

### Phase 4: Testing

1. Start a Bitcoin Core Signet node with RPC enabled
2. Configure wallet to use Core for package broadcast
3. Test exit with CPFP
4. Verify package submission succeeds

---

## Implementation Checklist

- [ ] Test if Esplora supports package endpoint
- [ ] If not, decide between Bitcoin Core RPC or self-hosted Esplora
- [ ] Create BitcoinCoreRPC client class
- [ ] Add package broadcast method to BDKOnchainWallet
- [ ] Update NetworkConfig with Core RPC settings
- [ ] Add UI for Bitcoin Core connection settings (optional)
- [ ] Expose package broadcast through Bark callbacks
- [ ] Test with real exit transactions
- [ ] Document setup requirements for users

---

## Architecture Decision

**For production:** Use Bitcoin Core RPC for package relay
- Most reliable
- Future-proof for Bitcoin improvements
- Can still use Esplora for chain data queries

**For testing/development:** 
- Option A: Run local Bitcoin Core Signet node
- Option B: Deploy own Esplora with package support

---

## References

From Bark maintainer response:
- Exit state machine: `states.rs:178`
- Transaction manager: `transaction_manager.rs:233`
- Chain package broadcast: `chain.rs:482`
- Wallet callbacks (no package method): `mod.rs:130`
- Esplora package call: `chain.rs:498`
- Package dependency: `Cargo.toml:91`
- Zero-fee parent test: `wallet_ext.rs:14`, `wallet_ext.rs:125`
- CPFP builder: `bdk.rs:177`, `bdk.rs:205`
- Empty witness test: `fee.rs:33`

## Next Steps

**Immediate:** Test if esplora.signet.2nd.dev supports package endpoint

**If yes:** Implement package broadcast using Esplora
**If no:** Implement Bitcoin Core RPC support

Would you like me to start with testing the Esplora endpoint or proceed with implementing Bitcoin Core RPC?
