# Testing Patterns

How the test suite is organised and the patterns it actually uses, read from
`Tests/` on 2026-10-07. What to test for a given change is decided by the
tier rules in `Release_Train.md`; how to review it is in
`Change_Review_Playbook.md`. The earlier template-style guide is in
`../Archive/Development/Testing_Patterns.md`.

## Shape of the suite

| | |
|---|---|
| Framework | Swift Testing only (`@Suite`, `@Test`, `#expect`, `#require`); no XCTest |
| Size | 35 files, 67 suites, about 450 tests |
| Targets | `ArkeMobileTests` (run by the `Arke mobile` test plan) and `ArkeDesktopTests`; both see the whole `Tests/` folder |
| Layout | `Tests/Shared/` holds nearly everything; `Tests/Mobile/` and `Tests/Desktop/` hold the two placeholder files and the iOS-only `AddressValidatorTests` |
| UI tests | none |
| Runner | `xcodebuild` against a simulator, see `Setup.md`; the MCP runners are sandboxed and use the active destination |

Tests import the app module, not a shared framework. Files that must compile
in both test targets use:

```swift
#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif
```

Shared tests are green on iOS; the macOS run fails about 68 of them flakily
on a clean tree, so a red desktop suite is not evidence about a change.

## What gets a test

The suite is dominated by **decision tests**: pure functions or small
structs extracted from a service so the policy can be pinned without a
wallet. Examples: `DefaultDataSeedingDecisionTests`,
`NetworkConfigReconciliationTests`, `PrimaryDeviceReconciliationTests`,
`ImportRecoveryLogicTests`, `RefreshExclusionTests`, `AmountEntryStateTests`.
When a fix changes *when* something is true, extract the decision and pin
it; do not test it through the service that owns a bark handle.

**Parsers and mappers** get fixture-driven tests with real captured data:
`ExitStatusParserTests` and `ExitProgressTests` use real bark state strings,
`OnchainTransactionMapperTests` real signet transactions,
`LightningInvoiceParserTests` and `LNURLResolverTests` real payloads. Raw
dumps used as fixtures live in `../Data samples/`.

**Coverage tests** enumerate a surface so that adding to it without a
decision fails a test. `WalletWipeCoverageTests` asserts that the three
lists in `WalletWipeCoverage` (directly wiped, cascade wiped, exempt)
exactly cover the SwiftData schema; `TransactionDeletionBlastRadiusTests`
pins what a transaction delete may and may not touch. This is the preferred
form for an invariant: a typed list plus a test, not a comment.

**Guard tests** read the repository itself. `LocalizationCatalogTests`
parses both string catalogs via `#filePath` and fails on empty translations
or format-specifier mismatches; `Scripts/translation_lint.py` prints the
same offenders by key.

## Patterns

**In-memory SwiftData.** Persistence tests build a `ModelContainer` with
the full schema and `isStoredInMemoryOnly: true` (ten suites do this; see
`TransactionBridgingEquivalenceTests.makeContainer()`). Use the full schema,
not a subset; relationship resolution depends on it. Two-context tests
(`TransactionMetadataWritePathTests`) delete through a second context to
reproduce what a CloudKit import does to cached relationship arrays.

**Injected fetchers and clocks.** Network-facing services take a fetcher
closure and a clock; tests pass canned responses and a `TestClock`
(`RatesServiceTests`, `FeeRateServiceTests`). No test hits the network.

**`MockBarkWallet` is a DEBUG stub**, used by four transaction suites that
need a `BarkWalletProtocol` to construct a service. Do not add realistic
behaviour to it; put the logic under test behind a decision type instead.

**Scratch `UserDefaults`.** State-touching tests use
`UserDefaults(suiteName:)` with a per-test name
(`RelayRegistrationFreshnessTests`). Nothing in `Tests/` writes to
`UserDefaults.standard`. Keep it that way; a crashed test host once left a
tombstone in a real phone's app defaults.

**Process-wide state is serialised.** `WalletDeletionRejoinTests` marks its
tombstone suite `.serialized` because it touches the keychain and iCloud
KVS. Suites that mutate keychain, KVS or defaults need `.serialized` or a
scratch scope; the flaky macOS run is most likely this class of leak
across parallel test hosts.

**Main actor.** Seventeen files annotate suites or tests `@MainActor`
because the services and SwiftData contexts under test are main-actor
isolated. Model types in `Shared/` that cross actors carry explicit
`nonisolated`.

## Conventions

- Suite names are plain phrases (`"Default Data Seeding Decision"`); test
  names are sentences describing the behaviour.
- One file per subject, named `<Subject>Tests.swift`, in `Tests/Shared/`
  unless it imports a platform-only API.
- A fix that produced a contract rule (`../Initialization/Launch_Sequence_Contract.md`,
  the area contracts in the playbook) names its pinning test in the rule's
  Test column. A rule with "Test: none" is a gap, not a style choice.
- New Shared source files compile into both app targets automatically; new
  test files need nothing.

## Running

```bash
# one suite
xcodebuild test -project Arke.xcodeproj -scheme "Arke mobile" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ArkeMobileTests/DefaultDataSeedingDecisionTests

# everything, before a commit plan
xcodebuild test -project Arke.xcodeproj -scheme "Arke mobile" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Scope runs while working and batch the full suite once at the end. Pure
logic suites also run fine through the MCP runner; anything touching the
filesystem, SwiftData or the catalogs fails bogusly there.
