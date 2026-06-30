# Previewable Models & Module Views — Extraction Plan

## Goal

Be able to build and iterate **data-driven views in isolation** (Xcode Previews,
sample data) without dragging in the things that make previews slow or broken —
specifically **Bark** (its UniFFI code breaks previews) and the **SwiftData
persistence store** / **WalletManager** app logic.

This extends the work already done in the `ArkeUI` package (presentational
components) to the next layer up: the value types those components consume, and
the composed views built on top of them.

## TL;DR

This is a **refactor, not a file move**. The components package lifted cleanly
because those files were already presentation-only. The model layer is not in
that shape yet: the central types reach into Bark, SwiftData, and `WalletManager`.

The work is to split each model into:
- a **pure value type (DTO)** — fields + dependency-free formatting helpers → moves into `ArkeUI`, and
- **bridging code** — `Persistent*` conversion, Bark mapping, `WalletManager` lookups → stays in the app.

Package shape is resolved: these types **fold into the existing `ArkeUI` package**
(under a `Models/` folder), rather than a new `ArkeModels` package. See the
"Decision" section for why.

## Current state (as surveyed 2026-06-30)

### What's already clean
- **`ArkeUI` is model-agnostic.** It references *none* of `TagModel`,
  `ContactModel`, `TransactionModel`, `VTXOModel`, `PersistentTransaction`, or
  `WalletManager`. Dependency runs one way: models `import ArkeUI`, never the
  reverse. No cycle risk for a package layered on top of `ArkeUI`.
- `MovementCategory` (`Shared/Data/MovementCategory.swift`) is pure
  (`import Foundation` only) — trivially movable.
- `BitcoinFormatter` and the formatting helpers already live in `ArkeUI`, so the
  formatting computed-properties on the models have their dependency available.

### What blocks a naive move
- **`Shared/Models/TransactionModel.swift`** mixes three concerns:
  1. **Bark** — `import Bark`; `ExitStatus.init(from: ExitVtxo)` (`ExitVtxo` is a Bark type).
  2. **SwiftData persistence** — `init(from: PersistentTransaction)`,
     `toPersistentTransaction()`, and an inline
     `FetchDescriptor<PersistentTransaction>` + `#Predicate`
     (in `totalFeesIncludingLinked`).
  3. **App logic** — `static weak var walletManager: AnyObject?` feeding
     `liveConfirmations` and `currentExitStatus`, which read `WalletManager`
     state.
- **19 of 30** files in `Shared/Models` `import SwiftData`; most are
  `Persistent*` `@Model` classes that *are* the store, not previewable DTOs.
- `TransactionModel` and `VTXOModel` `import Bark`.
- **17 of 114** files in `Shared/Views` `import Bark` directly; many more reach
  `WalletManager` transitively.

## Target layering

```
ArkeUI            One package, organized internally:
   |                Components/  (presentational — exists today)
   |                Models/      (pure value types + enums: TransactionModel,
   |                              TagModel, ContactModel, ExitStatus,
   |                              MovementCategory, + sample data)
   |                Views/       (composed, data-driven views over those models)
   |              No Bark. No SwiftData. No WalletManager.
   ↑
App (Shared / ArkeMobile / ArkeDesktop)
                  owns Persistent* @Model classes, Bark mapping, WalletManager;
                  converts to/from the pure types at the boundary.
```

Dependency rule: **a type may not live in `ArkeUI` if it imports Bark,
SwiftData, or touches WalletManager.** Those couplings get pushed *up* into the
app as boundary code. (`ArkeUI` links neither Bark nor SwiftData today; keeping
it that way is what makes everything in it previewable.)

### Decision (resolved): fold the pure models into `ArkeUI`

Do **not** create a separate `ArkeModels` package. Put the pure value types in
`ArkeUI` under a `Models/` folder (and composed views under `Views/`), alongside
`Components/`.

Rationale:
- **The models are presentation DTOs, not domain-pure types.** `TagModel`
  already exposes a SwiftUI `Color` (`var color: Color { Color(hex:) ?? .Arke.blue }`)
  and uses ArkeUI's palette; `ContactModel` imports SwiftUI and ArkeUI too. They
  belong with the UI layer.
- **ArkeUI is already the enforced "clean zone."** It links neither Bark nor
  SwiftData, so anything placed in it inherits the "no Bark / no SwiftData"
  guarantee at compile time — exactly the constraint a separate `ArkeModels`
  would re-implement.
- **The preview goal needs Bark *absent*, not a module boundary.** Xcode previews
  work per-file within a package; one clean package delivers isolation.
- **YAGNI / lower friction.** No non-UI consumer exists today (widgets use
  SwiftUI; persistence/sync uses the `Persistent*` classes that stay in the app).
  Folding avoids extra `public` boilerplate, a second `Package.swift`, and a
  three-package chain.

**Reconsider and split out a separate `ArkeModels` later only if** (a) a genuine
non-UI consumer appears (CLI, server-side component, or a model-only test target
you want to build without SwiftUI), or (b) ArkeUI's compile time becomes painful.
At that point it is a mechanical file-move plus one dependency edge, so deferring
costs nothing.

## The per-type refactoring pattern

For each model that should become previewable:

1. **Keep the pure struct + dependency-free computed properties** in the
   previewable package. For `TransactionModel` this is the bulk of it: all the
   `formatted*` properties (built on `BitcoinFormatter`), `netAmount`,
   `totalFees`, tag/contact/notes helpers, `isInternalTransfer`.
2. **Move persistence bridging into the app** as an extension:
   `init(from: PersistentTransaction)`, `toPersistentTransaction()`, and the
   `FetchDescriptor`-based `totalFeesIncludingLinked` / `*IncludingLinked`
   variants. The app depends on the models package, so it can extend the type.
3. **Invert the service lookups.** Replace `static weak var walletManager` +
   `liveConfirmations` / `currentExitStatus` with values passed in (or a small
   protocol the app conforms to). A pure model must not reach into a singleton.
4. **Map Bark types at the boundary.** `ExitStatus` is already a plain struct;
   give it a memberwise init and convert from Bark's `ExitVtxo` in app code
   instead of inside the model's initializer.
5. **Add sample data** (`static let sampleSend`, `.sampleReceive`, etc.) in the
   package so previews need no database or Bark.

## Proposed sequencing

### Phase 0 — Prepare ArkeUI structure
- Package shape is **resolved**: fold into `ArkeUI` (no new package — see
  "Decision" above).
- Add `Models/` (and, for Phase 3, `Views/`) folders under
  `ArkeUI/Sources/ArkéUI/` alongside `Components/`.
- No `Package.swift` dependency changes needed; `ArkeUI` already links what these
  types require (SwiftUI; nothing else).

### Phase 1 — Prove the pattern on one vertical slice

`TransactionModel` turned out **not** to be independently movable: its stored
properties embed `[TagModel]` and `[ContactModel]`, and `ContactModel` embeds
`[ContactAddressModel]` + `ContactType` + `AddressFormat`. Moving it requires the
whole tag/contact model graph first. So Phase 1 was re-scoped into ordered
sub-steps, starting with the leaf-most type. `TagModel` is a prerequisite for
`TransactionModel` regardless, has no embedded app-models, and exercises the
SwiftData-bridging + sample-data-preview pattern end-to-end.

**Phase 1a — `TagModel` (DONE, 2026-06-30):**
- Pure `TagModel` value type moved to `ArkeUI/Sources/ArkéUI/Models/TagModel.swift`
  (`public`, `Sendable`; keeps `color`/`displayName`/`appearance`/`createDefaultTags`;
  added sample data + an isolated `#Preview` driving `TagChip`).
- Persistence bridging (`init(from: PersistentTag)`, `toPersistentTag()`) moved to
  app-side `Shared/Models/TagModel+Persistence.swift`.
- Added `import ArkeUI` to the 5 files that referenced `TagModel` without it.
- Verified: both apps build; isolated preview renders from sample data.

**Phase 1b — `ContactModel` graph (DONE, 2026-06-30):**
- Pure value types moved to `ArkeUI/Sources/ArkéUI/Models/`
  (all `public`, `Sendable`):
  - `ContactModel.swift` — keeps `displayName`, `formatted*` (via
    `BitcoinFormatter`), the `*Addresses` / `addressCount` / `addressTypesSummary`
    / `addresses(for:)` helpers, `withUpdatedTimestamp`; added sample data
    (`sampleAlice`/`sampleBob`/`sampleFaucet` + `samples`) and an isolated
    `#Preview`.
  - `ContactAddressModel.swift` — keeps `displayName`/`fullDisplayName`/
    `shortAddress`/`supportsBitcoinNetworks`/`withUpdatedTimestamp`/
    `withPrimaryStatus` + `CustomStringConvertible`; added `sampleArk`/
    `sampleBitcoin`/`sampleLightning` factories.
  - `ContactType.swift` and `AddressFormat.swift` — pure enums, moved wholesale.
  - `BitcoinNetwork.swift` — **split** out of `Shared/Data/NetworkConfig.swift`:
    the pure parts (cases, `displayName`, `init?(networkType:)`) moved into the
    package; the `NetworkConfig`-based `matches(_:)` stays app-side as an
    extension in `NetworkConfig.swift`. `NetworkConfig` itself did **not** move.
- Persistence/bridging kept app-side as extensions in `Shared/Models/`:
  - `ContactModel+Persistence.swift` — `init(from: PersistentContact)`,
    `toPersistentContact()`, and the `NetworkConfig` helper `addressesForNetwork(_:)`.
  - `ContactAddressModel+Persistence.swift` — `init(from: PaymentDestination …)`,
    `init(from: PersistentContactAddress)`, `toPersistentAddress()`, and the
    `NetworkConfig` helper `isCompatibleWith(_:)`.
- Added `import ArkeUI` to the ~23 app files that referenced these types without
  it (incl. `Persistent*`, `PaymentDestination`/`PaymentRequest`,
  `AddressValidator`, `ContactService*`, contact views/view-models).
- Verified: both apps build; previews render from sample data.

**Phase 1b watch-item (learned):** because all four moved types are `Codable`,
the synthesized `init(from: Decoder)` collides with the app-side bridging
`init(from: PersistentContact)` / `init(from: PersistentContactAddress)` /
`init(from: PaymentDestination)`. This is fine **as long as the bridging
extension files are actually compiled into the target.** When they were missing
from a target's membership, every `Type(from:)` call silently resolved to the
`Decodable` initializer and produced misleading errors ("argument does not
conform to `Decoder`", "'nil' is not compatible with closure result type"). If
you see those, suspect target membership of the `+Persistence` files, not the
code.

**Phase 1c — `TransactionModel` (DONE, 2026-06-30):** the poster child. Added the
Bark boundary (`ExitStatus`/`ExitVtxo`) and the `WalletManager` static-lookup
inversion on top of the now-moved tag/contact types.
- Pure value types moved to `ArkeUI/Sources/ArkéUI/Models/` (all `public`,
  `Sendable`):
  - `TransactionModel.swift` — stored props + memberwise init + every
    dependency-free helper (the `formatted*`/`netAmount`/`totalFees`/fee helpers,
    tag/contact/notes/linking helpers, `isInternalTransfer`, and the pure
    `hasUnilateralExit`); added `sampleReceive`/`sampleSend`/`samplePending` +
    `#Preview`.
  - `MovementCategory.swift` (incl. nested `FilterGroup`), `TransactionStatusEnum.swift`
    (uses the `.Arke` palette, so it belongs with the UI layer), and
    `ExitStatus.swift` (pure struct + `public` memberwise init).
- App-side concerns kept as extensions in `Shared/Models/`:
  - `TransactionModel+Persistence.swift` — `init(from: PersistentTransaction)`,
    `toPersistentTransaction()`, and the four `*IncludingLinked` fee/amount
    variants (the `FetchDescriptor<PersistentTransaction>` code).
  - `TransactionModel+WalletManager.swift` — the inverted singleton lookups:
    `static weak var walletManager`, `liveConfirmations`, `currentExitStatus`,
    `isExitClaimed`. (Static stored properties *are* allowed in extensions.)
  - `ExitStatus+Bark.swift` — `init(from: ExitVtxo)` at the Bark boundary.
- `TransactionModel+OnchainAdapter.swift` and `+DisplayHelpers.swift` were already
  app-side extensions and needed no change beyond the now-public memberwise init.
- Added `import ArkeUI` to the 7 app files that referenced the moved types
  without it.
- Verified: both apps build; previews render from sample data.

**Phase 1c notes (learned):**
- **The `WalletManager` extension still imports `Bark`.** `currentExitStatus`
  reads `walletManager.allUnilateralExits` (`[ExitVtxo]`, a Bark type) and maps
  via `ExitStatus(from:)`, so `TransactionModel+WalletManager.swift` imports Bark.
  That's expected and fine — it's app-side; the point is the *pure* model in
  ArkeUI imports neither Bark nor SwiftData.
- **Same target-membership step as Phase 1b** (see below): the three deletions
  left stale references and the three new `Shared/Models/` files had to be added
  to the target in Xcode before the build resolved.

- **Phase 1 exit criteria (all met):** preview renders from sample data; both apps
  build (iOS + macOS); no behavior change.

**Phase 1 (transaction graph) is complete.** The tag/contact/transaction value
types and their enums (`TagModel`, `ContactModel`, `ContactAddressModel`,
`ContactType`, `AddressFormat`, `BitcoinNetwork`, `TransactionModel`,
`MovementCategory`, `TransactionStatusEnum`, `ExitStatus`) now live in
`ArkeUI/Models/`, with all Bark/SwiftData/WalletManager coupling pushed app-side.

### Phase 2 — Migrate the remaining pure value types

Survey of everything left in `Shared/Models` (done 2026-06-30) sorts the
remaining types into four buckets. Counts below are *files that reference the
type* (`views` = under any `Views/` folder; signals preview payoff).

**Bucket A — stays in the app (not a previewable DTO). Do not move.**
- `@Model` SwiftData store classes: `ArkBalanceModel`, `OnchainBalanceModel`,
  `OnchainTransactionEntity`, `PersistentContact`/`PersistentContactAddress`/
  `PersistentTag`/`PersistentTransaction`/`PersistentExitCache`,
  `PendingPaymentMetadata` (+ `PendingTagAssignment`), `DeviceRegistration`,
  `UserProfile`, `TransactionContactAssignment`, `TransactionTagAssignment`.
- All existing `*+Persistence` / `*+WalletManager` / `*+OnchainAdapter` /
  `*+DisplayHelpers` extension files (already app-side bridging).
- `ExitProgressActivityAttributes` (imports `ActivityKit`; Live-Activity infra
  shared with `ArkeWidgets`, not a previewable view DTO). **Out of scope** unless
  a preview need appears.

**Bucket B — straightforward moves (pure structs/enums; mirror Phase 1a/1b).**
Make `public` + `Sendable`, add sample data, drop any unnecessary `import
SwiftData`. Highest payoff first:
- `UTXOModel` (views=6) — already `Foundation`+`ArkeUI`, pure. Easy.
- `FeePriority` (views=6) — enum + `OnchainFeeRates` struct; imports `SwiftUI`
  (palette). UI DTO — belongs in the package.
- `FeeSchedule` (views=1) — several pure fee value structs (`PpmExpiryEntry`,
  `BoardFeeStructure`, …). Low view use but cohesive with `FeePriority`.
- `ArkInfoModel` (views=1) — references `BitcoinNetwork` (already in ArkeUI).
- `ArkConfigModel` (views=1) — pure `Foundation` struct.
- `OnchainTransactionModel` (+ `ConfirmationTime`) (views=0) — pure `Foundation`;
  no direct view use, but it feeds `TransactionModel+OnchainAdapter` and is the
  natural source DTO. Move for consistency, or **defer** (see note).
- Networking/response DTOs `ArkBalanceResponse`, `OnchainBalanceResponse`,
  `TotalBalanceModel` (views=0). Their `import SwiftData` is unused (only a
  "mirrored from …Model" comment). Pure, but **service-only** — moving them is
  churn with no preview payoff. **Recommend deferring** these to Phase 2c /
  leaving app-side unless a view ends up consuming them.

**Bucket C — Bark boundary (mirror Phase 1c `ExitStatus`/`VTXO`).**
- `VTXOModel` (views=8) + `VTXOState` + `VTXOKind`: pure struct/enums move to
  `ArkeUI/Models/`; the only Bark coupling is `init(from vtxo: Vtxo)`
  (`VTXOModel.swift:226`) — relocate to an app-side `VTXOModel+Bark.swift`,
  exactly like `ExitStatus+Bark.swift`. Highest single-type payoff in Phase 2.

**Bucket D — the genuinely harder one: balance display (needs a decision).**
`ArkBalanceModel` / `OnchainBalanceModel` are `@Model` classes consumed
*directly* by balance views (views=3 each). Per the Bucket-A rule they stay in
the app, so making balance views previewable is **not a move** — it requires
introducing a pure balance snapshot value type that views consume, with the
`@Model` converted to it at the boundary (the `*Response` structs already
"mirror" these classes and may be the basis). This is a real refactor; treat it
as its own sub-step and **get a design decision before starting** (new
`BalanceSnapshot` DTO vs. promoting the existing `*Response` types).

**Proposed sequencing (each step: build iOS+macOS, preview from sample data, no
behavior change — same exit criteria as Phase 1):**
- **Phase 2a — `VTXOModel` (Bark boundary) (DONE, 2026-06-30).** Moved the
  `VTXOModel` struct + its computed helpers, the `VTXOState`/`VTXOKind` enums with
  their display/icon/color extensions, the JSON parsing helpers, and `mockVTXOs()`
  (+ a `samples` alias and `#Preview`) into `ArkeUI/Sources/ArkéUI/Models/VTXOModel.swift`
  (all `public`, `Sendable`). The only Bark coupling — `init(from vtxo: Vtxo)` —
  stayed app-side in `Shared/Models/VTXOModel+Bark.swift`. Added `import ArkeUI`
  to the 6 app files that referenced VTXO types without it. Same target-membership
  pass as before (stale deletion + new file). Verified: both apps build; preview
  renders from sample data.
- **Phase 2b — pure UI DTOs (DONE, 2026-06-30).** Moved to `ArkeUI/Models/`
  (all `public`, `Sendable`): `UTXOModel` (+ its `Array` totals extension);
  `FeePriority` + `OnchainFeeRates`; `FeeSchedule` + its five fee structs +
  `FeeOperation`; `ArkInfoModel`; `ArkConfigModel`. Notes:
  - **Explicit public memberwise inits** were added to every moved struct.
    (JSON `Decodable` decoding works cross-module without one — the protocol
    requirement is satisfiable even when the synthesized init isn't `public` — but
    *memberwise* call sites in mocks/services do need it.)
  - **Localized strings → `bundle: .module`.** `FeePriority` (9 keys) and
    `ArkConfigModel` (`format_network`, `data_server`) had `String(localized:)`;
    all 11 keys were added to `ArkeUI/Sources/ArkéUI/Localizable.xcstrings` with
    canonical values copied from `Shared/Localizable.xcstrings`. (`symbol_ellipsis`
    was already in the package bundle, which is why the Phase 1/2a moves rendered
    correctly without a bundle arg.)
  - Added `import ArkeUI` to the 5 app files that referenced these without it.
  - These were all clean moves — **no Bark/SwiftData boundary, so no new app-side
    files** (the membership pass was pure stale-reference removal).
  - Verified: both apps build; previews render from sample data.
- **Phase 2c / 2d — DEFERRED to Phase 3 (decided 2026-06-30, demand-driven).**
  The remaining candidates (`OnchainTransactionModel`, `ArkBalanceResponse`,
  `OnchainBalanceResponse`, `TotalBalanceModel`) have **zero view consumers
  today** — the main balance views read `WalletManager`'s `formatted*` strings /
  `totalBalance`; only the SwiftData `@Query`-bound **Data debug views**
  (`ArkBalanceView`, `OnchainBalanceView`) touch the `@Model`s, and those stay
  app-side. Findings from the survey:
  - `ArkBalanceResponse` / `OnchainBalanceResponse` are already pure DTOs that
    *mirror* their `@Model` computed properties (their `import SwiftData` is
    unused). Trivially movable — but no preview payoff yet.
  - **`TotalBalanceModel` is *not* pure:** it stores `ArkBalanceModel` /
    `OnchainBalanceModel` (the `@Model` classes) directly, so making it
    previewable is a real refactor — rewrite it to wrap the `*Response` value
    types and update `WalletManager.totalBalance` + every consumer.
  - `WalletManager` already exposes a `BalanceData` value struct holding
    `ArkBalanceResponse?` / `OnchainBalanceResponse?`, plus computed `arkBalance`/
    `onchainBalance`/`totalBalance` (`@Model`/`TotalBalanceModel`) accessors.
  - **Decision:** don't move these speculatively. Move each at the moment a
    Phase 3 previewable view needs it — so `TotalBalanceModel`'s `@Model`
    decoupling has a concrete view to validate against. The `@Model` classes and
    the `@Query`-bound Data debug views stay app-side regardless.

**Phase 2 is complete.** Every value type with view payoff is now in
`ArkeUI/Models/`: the tag/contact/transaction graph (Phase 1) plus `VTXOModel`,
`UTXOModel`, `FeePriority`/`OnchainFeeRates`, `FeeSchedule` (+ fee structs/
`FeeOperation`), `ArkInfoModel`, `ArkConfigModel`. Remaining model files are
either `@Model` stores, app-side bridging extensions, `ActivityKit` infra, or the
deferred balance/service DTOs above.

**Per-type checklist (reaffirms the global risk items):**
- Audit for hidden `WalletManager`/`Persistent*` reach-through before moving;
  push any found coupling into an app-side extension.
- Pull any `FetchDescriptor`/`#Predicate`/`ModelContext` out to app-side bridging.
- Drop unused `import SwiftData`/`import Bark` from the moved pure file.
- Expect a per-target Xcode membership pass for new/deleted `Shared/` files (see
  "Project structure"), then rebuild.

### Phase 3 — Migrate composed, data-driven views

Now that the value types are in `ArkeUI/Models/`, move the **presentational,
data-driven views** that compose `ArkeUI` components over those models and need
neither Bark, `WalletManager`, nor SwiftData. Each gets a sample-data `#Preview`.

**Destination is already seeded.** `ArkeUI/Sources/ArkéUI/Views/` exists with
~19 presentational subviews already moved (e.g. `Send/FeeDisplayView`,
`Balance/FeeEstimateView`, `Contacts/NativeContactLinkBadge`, `Tags/ColorPickerSheet`),
organised by feature folder (`Activity/`, `Balance/`, `Contacts/`, `Data/`,
`Receive/`, `Send/`, `Tags/`, `Exit/`). Phase 3 extends that set.

#### Movability criteria (a file moves only if ALL hold)
1. It is an actual SwiftUI `View` (not console/command logic, a state enum, a
   resolver/validator, or a `*ViewModel`).
2. Its inputs are value types / `ArkeUI` models / primitives / closures — passed
   in via `let`/`@Binding`, **not** an `@EnvironmentObject`/`@Environment`
   `WalletManager`, a `*ViewModel`, or a SwiftData `@Query`.
3. No Bark, no SwiftData (`ModelContext`/`@Query`/`FetchDescriptor`), and no
   `WalletManager` — **including indirect** reach-through such as
   `context.walletManager` or a service singleton (the plain text grep below
   misses these; verify per file).
4. Any localized strings use `bundle: .module` with keys copied into the package
   `Localizable.xcstrings` (see Phase 2b).

Views that fail (2)/(3) **stay app-side** but should be refactored to *receive
their data via `init`* where cheap, so a thin app-side wrapper feeds a moved
presentational subview. Platform screens (`ArkeMobile/Views`, `ArkeDesktop/Views`)
generally stay; harvest movable subviews out of them rather than moving wholesale.

#### Survey (2026-06-30)
`Shared/Views` = 113 files. Coupling: imports Bark = 17; references
`WalletManager` = 41; SwiftData (import/`ModelContext`/`@Query`/`FetchDescriptor`)
= 15. ~58 files trip none of those greps — the candidate pool — **but the grep
has false positives**: e.g. `Console/WalletCommands.swift` (uses
`context.walletManager`, and isn't a View), `Send/RecipientState.swift` (a state
enum), `Console/CommandExecutor.swift`, `Send/SendModalState.swift`,
`Contacts/Editor/ContactValidation.swift`, `Send/LightningAddressResolver.swift`,
`Send/ReceiveQRContentHelper.swift`. Filter those out per criterion (1)/(3).

Confirmed clean movers spot-checked (take model/value inputs, already
`import ArkeUI`): `Balance/BalanceDetailCard` (primitives + color),
`Contacts/Details/ContactHeaderView` (`ContactModel`),
`Send/FeeOptionRow` (`FeePriority` + closure),
`Activity/TransactionStatusBadge` (`TransactionStatusEnum`).

#### Stays app-side (non-exhaustive)
- The 17 Bark-importing + 41 WalletManager-referencing views, the SwiftData
  `@Query` Data debug views (`ArkBalanceView`, `OnchainBalanceView`), and all
  `*ViewModel`s.
- Console command logic, send/receive flow state machines and resolvers.
- Most `ArkeMobile`/`ArkeDesktop` screen-level views (compose app state); move
  their pure subviews instead.

#### Proposed sequencing
- **Phase 3a — proof batch (high-confidence presentational subviews).** A small,
  cohesive set that already imports `ArkeUI` and takes value/model inputs —
  e.g. `TransactionStatusBadge`, `BalanceDetailCard`, `ContactHeaderView`,
  `ContactPreviewCard`, `FeeOptionRow`, `TagPreviewCard`, `Receive/AddressCard`,
  `Data/UTXORowView`. Prove the per-view preview + membership flow end-to-end,
  then settle naming/folder conventions before scaling.
- **Phase 3b… — by feature area**, one folder at a time (Contacts → Tags →
  Receive → Send subviews → Balance → Activity/Data rows). For each: move the
  pure subviews, add sample-data previews, and where a screen is *almost* pure,
  extract its presentational body into a moved subview fed by `init`.
- **Demand-driven model moves (from 2c/2d):** when a moved view needs balance
  data, that's the trigger to move `ArkBalanceResponse`/`OnchainBalanceResponse`
  and to do the `TotalBalanceModel` `@Model` decoupling (rewrite it to wrap the
  `*Response` value types) — now with a concrete view to validate against.
- **Exit criteria (per batch):** preview renders from sample data; both apps
  build (iOS + macOS); no behavior change.

#### Recurring mechanics (same as Phases 1–2)
- Files moved into the package need no project entry; **deleted `Shared/` files
  leave stale references and must be removed in Xcode** (per-target membership
  pass), then rebuild. Never edit `project.pbxproj` by hand.
- Add `import ArkeUI` to app files that referenced a moved view by name.
- Watch for `bundle: .module` on any localized strings.

## Project structure (learned during Phase 1a)
- **`Shared/` now uses default file-system-synchronized membership for all three
  targets** (ArkeMobile, ArkeDesktop, ArkeWidgets). Previously ArkeMobile
  enumerated every `Shared` source file explicitly in its membership-exception
  set, so every add/remove needed a `project.pbxproj` edit. ArkeMobile was
  converted (via the `Shared` folder's Target Membership) to include the whole
  synchronized folder by default, matching Desktop/Widgets. (The conversion also
  added two files that had been missing from ArkeMobile:
  `Models/Extensions/TransactionModel+OnchainAdapter.swift`
  and `Views/Send/Payment destination/PaymentDestinationSelectorExamples.swift`.)
- **Correction (learned in Phase 1b): adding/removing `Shared/` files is NOT
  always pure file I/O.** The `Shared` synchronized root group carries per-target
  `exceptions` lists (one each for ArkeDesktop, ArkeMobile, ArkeWidgets in
  `project.pbxproj`), so synchronization is not blanket. In Phase 1b, **deleting**
  files left stale references (`Build input files cannot be found`) and the two
  **new** `+Persistence.swift` files were not compiled into a target until added
  via Xcode. Budget for a per-target membership/cleanup pass in Xcode after
  adding or deleting `Shared/` files, and re-confirm with a build. **Still never
  edit `project.pbxproj` by hand** — make these changes in Xcode (the user's to
  do).
- **Never edit `project.pbxproj` directly** (it can crash a running Xcode). Files
  moved *into the ArkeUI package* need no project entry (SwiftPM auto-discovers
  `Sources/`). Files added/removed under `Shared/` are auto-synced per the above.
  Any genuinely required project change is the user's to make in Xcode.

## Risks / watch-items
- **Hidden `WalletManager` reach-through.** Some computed properties look pure but
  resolve the static `walletManager`. Audit each before moving.
- **SwiftData `#Predicate` / `FetchDescriptor`** anywhere in a candidate type
  means it is bridging code, not a DTO — pull it out.
- **`defaultLocalization` / `bundle: .module`.** Strings moved into a package
  render raw keys unless they use the package bundle; reuse canonical values from
  `Shared/Localizable.xcstrings`. (See existing ArkeUI localization notes.)
- **Preview target linkage.** Confirm the preview/package target does **not**
  transitively link Bark; that transitive pull-in is the whole problem being
  solved.
- **Scope creep.** This is incremental. Each phase must leave iOS + macOS apps
  building and behavior unchanged before starting the next.

## Out of scope
- Rewriting persistence (`Persistent*` `@Model` classes stay as-is in the app).
- Changing `WalletManager` responsibilities beyond inverting the model lookups.
- Touching `Bark` / FFI integration.
