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
Once the transaction graph (Phase 1a–1c) is done, move the other genuinely pure
models and enums: balance/fee value types, etc., plus any not pulled in by the
transaction graph. Leave every `Persistent*` `@Model` class in the app. Apply the
boundary pattern to any that touch Bark (`VTXOModel`) or SwiftData.

### Phase 3 — Migrate composed, data-driven views
Move views that compose `ArkeUI` components over the now-pure models and don't
need Bark/WalletManager. Add previews backed by sample data. Views that
genuinely need app logic stay in the app and receive data via their inits.

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
