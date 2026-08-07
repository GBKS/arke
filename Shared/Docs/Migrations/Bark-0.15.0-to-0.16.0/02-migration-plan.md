# Migration Plan: Bark FFI Bindings v0.15.0 → v0.16.0

Principle: **map at the FFI boundary, change nothing downstream.** The app
already has typed domain models for everything that changed
(`ParsedExitState`, `VTXOState`, `ArkéUI.FeeSchedule`); the migration swaps
their *source* from string parsing / JSON decoding to direct enum/struct
mapping. Downstream consumers (`ExitProgress`, `ExitBlockedInfo`,
`ExitProgressionService/Logic`, exit + VTXO UI) go through those models and
should not need edits beyond the sites listed here.

Exhaustive `switch`es everywhere, no `default:` on Bark enums — future
binding bumps must surface as compile errors.

---

## 1. Fee schedule (compile fix + collision)

**Files:** `Shared/Data/BarkWalletFFI/BarkWalletFFI+Configuration.swift`
(lines 97, 144, 173, 176, 198), `Shared/Data/MockBarkWallet.swift`
(line 118), `Shared/Services/VTXORefreshService.swift` (bare `FeeSchedule`
parameter types at lines 289, 335).

All three import `Bark` **and** `ArkeUI`, so every bare `FeeSchedule`
reference is now ambiguous. Keep ArkéUI's `FeeSchedule` — it is the intentionally
Bark-free presentation model (fee math, display strings, previews; header
comment says exactly that). Do not delete it, do not make UI consume
`Bark.FeeSchedule`.

1. Add a boundary mapper (suggested home: a small
   `FeeSchedule+Bark.swift` next to `VTXOModel+Bark.swift`, same pattern):
   `init(from ffi: Bark.FeeSchedule)` on `ArkeUI.FeeSchedule`, mapping
   `UInt64 → Int` and `minFeeSats → minFeeSat` etc., including
   `PpmExpiryFeeEntry → PpmExpiryEntry`.
2. `getArkInfo()` (Configuration:176): replace
   `FeeSchedule.from(jsonString: ffiArkInfo.feeScheduleJson)` with the
   mapper. The result is non-optional now — the `if feeSchedule != nil`
   logging branch (177) simplifies. Fix the debug log at 173 that
   interpolates `feeScheduleJson`.
3. Qualify remaining bare references (`ArkeUI.FeeSchedule` /
   `Bark.FeeSchedule`) in both files, including the sample schedule at
   Configuration:97 and MockBarkWallet:118 (those construct the ArkéUI
   type — just qualify).
4. `ArkéUI.FeeSchedule.from(jsonString:)` becomes unused — delete it.
   The Codable conformance and snake_case `CodingKeys` **stay**:
   `ArkInfoModel` is Codable and `WalletManager+Export` encodes it
   (`arkInfo` at Export.swift:74), so the export JSON format depends on
   those keys.

## 2. VTXO state (compile fix)

Old FFI strings were lowercase and match the new case names exactly, so
these are mechanical:

| Site | Change |
|---|---|
| `Shared/Data/BarkWalletFFI/BarkWalletFFI+VTXO.swift:524` `mapFFIStateToVTXOState(_ stateString: String)` | Take `VtxoState`; exhaustive switch. `.locked(let holder)` → `.locked` (holder currently unused — fine), `.exited` → `VTXOState.exited` (as the string branch already does). The `"pending"` and `default:` branches have no enum counterpart — drop them. |
| `Shared/Models/VTXOModel+Bark.swift:19-27` `VTXOModel.init(from vtxo: Vtxo)` | `vtxo.state.lowercased()` no longer compiles. Same exhaustive switch. Today's string version maps unknown — **including `"exited"`** — to `.pending`, silently mislabeling exited VTXOs; the enum switch fixes that latent bug (behavior change, list it in the completion report). These two mappers duplicate each other; consolidating them is a reasonable one-line-of-opportunism, not required. |
| `ArkeMobile/Views/Data/PendingRoundsListView_iOS.swift:141` | `$0.state == "locked"` → `if case .locked = $0.state` (associated value means plain `==` won't do). |
| `Shared/Helpers/RoundStateDebugger.swift:30` | Same. |
| `Shared/Data/MockBarkWallet.swift:449,459,476,505`, `BarkWalletFFI+VTXO.swift:382` | `state: "spendable"` → `state: .spendable`, etc. |

`VtxoLockHolder` (who holds the lock) is new information — not surfaced
anywhere today; ignore in this pass.

## 3. Exit state (the core of the migration)

### 3.1 New boundary mapper

New file (suggested: `Shared/Data/ExitStatus/ParsedExitState+Bark.swift`):

- `ParsedExitState.init(from state: Bark.ExitState)` — total, exhaustive,
  no `.unparsed` output. Maps associated values onto the existing
  `StartState`/`ProcessingState`/… structs. **Always qualify
  `Bark.ExitState`:** the app has its own `ExitState` (the live-activity
  enum in `ExitProgressActivityAttributes.swift:53`), which shadows
  Bark's in-module. That enum keeps its name — do not rename it here.
- `ExitTransaction.init(from tx: Bark.ExitTx)`,
  app `ExitTxStatus` ← `Bark.ExitTxStatus` (qualify — the app's own
  `ExitTxStatus` shadows Bark's in-module), app `TxOrigin` ←
  `Bark.ExitTxOrigin`, `ArkeBlockRef` ← `Bark.BlockRef`.
- Mapping notes: Bark `.awaitingConfirmation(childTxid:origin:)` → app
  `.broadcastWithCpfp(...)` (the app case already documents it covers
  bark's `AwaitingConfirmation`); Bark `.awaitingInputConfirmation(txids: [String])`
  → app `.awaitingInputConfirmation(.init(dependencyTxids: Set(txids)))`;
  Bark `.block(confirmedIn: BlockRef)` → app `.block(confirmedIn: ArkeBlockRef?)`
  (non-optional → optional, fine). App-only cases `.needsSignedPackage` /
  `.needsBroadcasting` / `.unparsed` receive no new values — they remain
  reachable only from legacy persisted strings.

### 3.2 Live-status plumbing

`Shared/Data/ExitStatus/ExitTransactionStatus+Parsing.swift`:
`parsedState` / `parsedHistory` switch from
`ExitStatusParser.parseState(state)` to the new mapper (`parsedState`
becomes non-optional in effect; keep the optional type if that keeps the
diff small). `allTransactionIds` / txid extraction: move the extraction
logic to operate on `ParsedExitState` (it already does internally —
`ExitStatusParser.extractTxids` — just re-route the entry points so they
don't re-parse strings). Callers of those entry points that compile
through unchanged once retargeted: `TransactionLinkingService:95,376`
(`extractUserFundedTransactionIds(from: status)`).

Direct-consumer compile breaks found in review — fix alongside:

- `ExitProgress.swift:68` — `status.parsedState ?? .unparsed(status.state)`:
  the fallback interpolates a `String`; with the total mapper the `??`
  fallback becomes unreachable — simplify.
- `ExitProgressionService+LiveActivity.swift:345` —
  `ExitStatusParser.parseState(status.state)` → `status.parsedState` /
  the mapper.
- `Shared/Views/Activity/ExitVtxo+Extensions.swift:259-264` —
  `formattedHistory` does `history.joined(separator: " → ")`, which
  doesn't exist on `[ExitState]`; map each entry to a display name first.
- `ArkeMobile/Views/Data/ExitStatusDetailView_iOS.swift` — a debug view
  that renders raw states: `Text(status.state)` (735) needs a `String`;
  the history-row subview (~795-825) holds `state: String` and calls
  `ExitStatusParser.parseState(state)` (805, 818). Change the subview to
  take `Bark.ExitState`, render the raw line via `String(describing:)`,
  and parse via the mapper. It's a developer-facing view — the raw-format
  drift (CamelCase Rust-Debug → Swift enum description) is fine.

`Shared/Views/Activity/ExitVtxo+Extensions.swift` (lines ~55-149, 217-256):
`extractStateCaseName(String(describing: state))` + lowercased matching
happens to still work on the enum, but replace with a real
`switch exitVtxo.state` (or map to `ParsedExitState` first and switch on
that). Keep user-visible wording identical (`stateDisplayName` values are
localized and cached in `PersistentExitCache.stateDisplayName`). One
wording nit while there: `.canceled` currently falls into the `default:`
branch and would render the raw case name, which changes "Canceled" →
"canceled" — give it an explicit localized case.

### 3.3 Persistence — `ExitStatusSnapshot` v1 → v2 (the risky part)

`Shared/Models/PersistentExitCache.swift:65-93`. Constraints:

- On-disk v1 snapshots hold Rust-Debug strings, including **pre-0.11 case
  names** (`NeedsSignedPackage`, `NeedsBroadcasting`, `BroadcastWithCpfp`).
- They are the **only durable record of claimed exits** (bark purges
  claimed exits — see `bark-purges-claimed-exits` memory). Losing them
  breaks historical exit display and fee attribution.
- `ExitStatusSnapshot.status` reconstructs a `Bark.ExitTransactionStatus`
  from strings — impossible once `state` is `ExitState`. The snapshot can
  no longer round-trip through Bark types.

Design:

1. Make `ParsedExitState` (and `ExitTransaction`, app `ExitTxStatus`,
   `TxOrigin`, `ArkeBlockRef`) `Codable`. Pure value types, mechanical.
2. `ExitStatusSnapshot` v2: `vtxoId`, `state: ParsedExitState`,
   `history: [ParsedExitState]?`, `transactionCount`, plus a `version`
   field. Decode: try v2; on failure (or version 1 / missing version),
   decode the v1 shape and run each string through
   `ExitStatusParser.parseState` — v1 fallback stays forever.
3. Replace `snapshotStatus: ExitTransactionStatus?` with a parsed-snapshot
   accessor (e.g. `snapshotParsedState` / a small struct holding parsed
   state + history + transactionCount). `ExitStore`
   (`WalletManager+Exits.swift:29`, the single owner of unilateral-exit
   state) exposes this via `persistedStatus(for:)` — its return type
   changes with the accessor, and `ExitBlockedInfoTests:203` compares
   `.state` through it. Consumers:
   - `WalletManager+Exits.swift:203-204`: `state.hasPrefix("Claimed") ||
     state.hasPrefix("ClaimInProgress")` → `if case .claimed`, `if case
     .claimInProgress` on the parsed state.
   - Check the other `snapshotStatus` users found by grep:
     `ExitProgressionService(+LiveActivity)`, `ExitProgressionLogic`,
     `TransactionLinkingService`, `ExitStatusDetailView_iOS` — most consume
     `parsedState`/`parsedHistory` and follow automatically once the
     accessor returns parsed values.
4. Writes go v2. No proactive rewrite of old rows — they upgrade lazily on
   next save, and the v1 decode path covers the rest.

`ExitStatusParser` itself: **keep**, demoted to legacy-snapshot decoder.
Update its header comment to say so. Its `extractAllTransactionIds(from:
Bark.ExitTransactionStatus)` entry points move/retarget per §3.2.

### 3.4 `getExitVtxos` / `progressExits` / `listClaimableExits` consumers

`ExitVtxo.isClaimable` and `ExitProgressStatus.error` are unchanged, and
`ExitProgressionService/Logic` don't touch `.state` directly (verified by
grep) — they should compile untouched once `ExitVtxo+Extensions` and the
parsing extensions are fixed. The richer data now on `ExitState`
(`claimableHeight`, `claimTxid`, per-tx CPFP status) is already what
`ParsedExitState` carried, so **no flow redesign**: simplify only where old
code worked around missing data, which after review is essentially nowhere
new.

## 4. Tests

- `Tests/Shared/ExitProgressTests.swift`: `makeStatus(state: String, …)` →
  take `Bark.ExitState` (or `ParsedExitState`, depending on what
  `ExitProgress` consumes after §3.2); also the
  `ExitProgressStatus(state: "Processing"/"AwaitingDelta"/"Claimable")`
  fixtures at lines 414, 415, 429.
- `Tests/Shared/ExitStatusParserTests.swift`: the string-parsing tests
  **stay as-is** — they now guard the legacy v1 decode path. Only fixtures
  that construct `Bark.ExitTransactionStatus` directly need enum values.
- `Tests/Shared/ExitBlockedInfoTests.swift:145,189`:
  `ExitVtxo(state: "Claimable")` → `.claimable(tipHeight:…)` etc.; the
  `ExitTransactionStatus` fixtures at 183-185 and 240-242 embed full
  Rust-Debug state strings — construct `Bark.ExitState` values instead,
  or route through a v1-snapshot decode where the test targets
  persistence.
- `Tests/Shared/ExitFeeAttributionTests.swift`: the `status()` fixture
  (~line 62) builds a `Bark.ExitTransactionStatus` from Rust-Debug
  strings (state + three history entries) — those exact strings are
  valuable as **legacy v1-snapshot decode fixtures**; move them there
  rather than deleting, and give the live-path attribution tests
  enum-built fixtures. The parser-variant tests (bark 0.11 origins,
  `AwaitingConfirmation`, third-party CPFP) stay on strings by design.
  The attribution logic itself reads `TxOrigin.isWallet` on parsed types
  and should survive unchanged.
- **New tests:** (a) `Bark.ExitState → ParsedExitState` mapper — one case
  each incl. nested `ExitTx` statuses and origins; (b) snapshot decode:
  v1 JSON fixture (real string from an old device log) → parsed; v2
  round-trip; pre-0.11 case-name fixture → parsed.
- Per the lean-verification workflow: scoped tests during the work, full
  mobile suite at the end; desktop ignored.

## 5. Suggested order of work

1. §1 fee schedule + §2 VTXO state (mechanical, isolates the build noise).
2. §3.1 mapper + §3.2 plumbing (compiles the exit path).
3. §3.3 snapshot v2 + consumer rework.
4. §4 tests, then full mobile suite.
5. Update this doc's README status + write `04-completion-report.md`.

Keep every change type-substitution-shaped; list any behavior change that
isn't in the completion report.

## 6. Deferred: adopting the new onchain methods

Not in this pass. When picked up:

- `getUTXOs() -> [UTXOModel]`
  (`BarkWalletFFI+VTXO.swift:76-88`) is currently a **stub returning `[]`**
  — `utxos()` would light it up for real, including `.exit` outputs
  (claimed unilateral exits), which pairs with the persistent exit cache.
- `getOnchainTransactions()` / `getLatestBlockHeight()`
  (`BarkWalletProtocol.swift:39,45`) could be backed by `transactions()` /
  `tipHeight()`; `WalletTransaction.isCpfp` is interesting for exit fee
  attribution.
- `feeRates()` could feed `FeeRateService` — mind the units:
  sat/kWU ÷ 250 = sat/vB, round up, floor at 1.
- BDK-backed onchain wallet only; wrap in `do/catch` and keep existing
  paths as fallback.
