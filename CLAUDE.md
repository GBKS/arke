# Arké — working rules for AI sessions

Arké is a native Bitcoin wallet for iPhone built on the Ark protocol through
the bark FFI bindings, with a parked macOS target and a widget extension.
`Docs/README.md` is the map of the documentation. This file is the short list
of rules that are not derivable from the code and that every session must
follow. When a rule here changes, change it here first; the assistant's
private memory is a cache of this file, not the source.

The project runs a plan → build → review → compound loop. The parts of it
that live in documents:

| Step | Where |
|---|---|
| What to work on | `Docs/Open_Follow_Ups.md` (priority tiers; the "Current train" block names this cycle's picks) |
| Cadence and definition of done per tier | `Docs/Development/Release_Train.md` |
| How to plan and review a change | `Docs/Development/Change_Review_Playbook.md` (claim labels, the sweep, the five fault classes, area contracts) |
| Startup and multi-device invariants | `Docs/Initialization/Launch_Sequence_Contract.md`, `Docs/Architecture/Multi_Device_Design.md` |
| What generated code got wrong before | `Docs/Development/Rework_Ledger.md` |
| Closed items with their write-ups | `Docs/Open_Follow_Ups_Done.md` |
| Strings and translation rules | `Docs/Localization/Localization_Guidelines.md` |

`Docs/Development/Setup.md` (toolchain, schemes, test command, log recipes)
and `Testing_Patterns.md` (how the suite is organised) were rewritten from
the project on 2026-10-07 and are current. Anything under `Docs/Archive/`
is history and loses to a living doc.

## How Christoph works

- **Questions are not decisions.** "Could X work?" or "we may want to…" asks
  for a written PROPOSAL. Only explicit approval ("do it", "yes") becomes a
  decision in a doc, labelled DECIDED with the date. Keep PROPOSED items
  marked as such and end replies with the calls he still owns.
- **Git.** Stay on the checked-out branch, normally `main`. Never create a
  branch or push. Leave finished work unstaged so he reviews the diff in
  Xcode's Changes navigator, then propose a commit plan (files per commit,
  messages). If he asks for commits, commit on the current branch. Xcode
  silently pre-stages files, so when splitting commits run `git reset -q`
  first or commit by path.
- **Project settings live in Xcode's UI.** Never edit
  `Arke.xcodeproj/project.pbxproj` by any means while Xcode is open; a hook
  blocks it and it can crash Xcode. Describe the exact change (target
  membership, localization, scheme, build setting) and ask him to make it.
- **Open work is recorded in the backlog, not in chat or memory.** New
  findings go into `Docs/Open_Follow_Ups.md` in the tier they belong to.
  Closing an item: tick it with the date, later move it to the Done log. His
  Reminders app is capture-only; sweep new entries into the backlog.
- **Every confirmed rework** (generated code that had to be revisited) gets
  one line in `Docs/Development/Rework_Ledger.md` with its fault class.

## Plan, build, review, compound

- **Plan first for anything non-trivial.** Label every factual claim the
  plan rests on as **verified** (executed, traced to file:line, or read at
  the bindings tag), **derived**, or **assumed**. An assumed claim about
  bark, CloudKit or the keychain blocks building on it until verified.
- **Sweep sibling sites before "done".** Grep every other call site, store
  or path the pattern touches and list each as covered / exempt-because /
  missed. Three of the worst ledger incidents were a second site nobody
  looked for.
- **Review by risk.** Mechanical edits and view tweaks need no drill. For
  derived signals, guards, caches, money paths, startup ordering, seed
  handling and the bark FFI boundary: trace writer → store → reader, walk
  error, concurrent and cold-start paths, verify any doc claim relied on,
  build and test every affected target. Doc claims are hypotheses; about a
  third were wrong in the last audit.
- **Tier 0 and Tier 1 changes get a fresh-context adversarial pass** by the
  `fault-class-reviewer` agent (`.claude/agents/`), handed only the commit
  range. It reports CONFIRMED / PLAUSIBLE per fault class and ends with what
  it did not verify. Fix or file every finding before the device day.
- **"Verified" means something was executed.** Never report a target, test
  or log line as verified without having run or read it. Say plainly what
  was not checked.
- **Seed-touching changes are not done on green tests.** Anything touching
  the mnemonic keychain item, the iCloud KVS wallet hash, deletion,
  registration or exits needs the on-device check, two devices where the
  scenario involves them, before it is recorded as done anywhere. Prefer
  invariants as typed errors and coverage tests over comments.

## Building and testing

- **Fast loop:** `XcodeRefreshCodeIssuesInFile` per edited file, one
  `BuildProject` per work step. IDE builds also re-extract string catalogs;
  `xcodebuild` builds extract for the built target only and never for
  ArkeDesktop.
- **Tests:** scoped suites while working, the full mobile suite once at task
  end or before a commit plan. The only authoritative runner is:

  ```bash
  xcodebuild test -project Arke.xcodeproj -scheme "Arke mobile" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:ArkeMobileTests/<Suite>
  ```

  The MCP test runners execute on the **active run destination**, which may
  be the physical phone, and their test host is sandboxed. A crashed
  state-touching test once left a tombstone in the real app's defaults.
  Switch the destination to a simulator before any MCP test run, and only
  trust MCP results for pure-logic suites.
- **Desktop is parked.** No desktop builds or test runs unless asked. The
  macOS suite fails ~68 tests flakily on a clean tree, so a red desktop run
  proves nothing; the same Shared tests are green on iOS.
- **Simulator log checks** need `log show --info --debug` or info-level
  lines vanish. Simulator logs do not redact private data; device logs do.
  Avoid `log stream`, it wedges the simulator. Bundle id is `GBKS.Arke`.
- **Build numbers are not bumped per build.** Fingerprint a device build by
  distinctive log lines plus `git log -S`, not the version header.
- **Xcode write tools can report success without persisting**, especially
  for package files. Grep the disk after a batch of `XcodeUpdate` or
  `XcodeWrite` edits.

## Project layout rules

- **`Shared/` is attached to both app targets** as a synchronized folder;
  new Shared files compile into Mobile and Desktop automatically. Only
  `ArkeWidgets` is opt-in and needs a tick in the File Inspector. Never rely
  on per-file target exceptions for platform exclusion; Xcode rewrites those
  sets wholesale. Use `#if canImport(X) && os(iOS)` islands in the file.
- **One Shared view with `#if os()` islands**, not a desktop copy of an
  `_iOS` view, when only small API islands differ (pasteboard, haptics,
  `navigationBarTitleDisplayMode`, `UIImage`/`NSImage`).
- **`Docs/` is a synchronized folder outside every target.** New files
  appear in the navigator on their own. Xcode-scoped tools cannot read it;
  use Read, Grep and Bash. Filenames are `Title_Case_With_Underscores.md`;
  `README.md`, `Archive/` and the numbered Migrations files are exempt.
  Plans carry a `**Status:**` line.
- **ArkéUI package** (`ArkeUI/Sources/ArkéUI/`) is auto-discovered by
  SwiftPM; no project entry needed. Previewable value models live there.
- **`MockBarkWallet` is a DEBUG-only stub** for two test suites and the
  skip-wallet-open launch path. Do not make it realistic or wire it into
  more views; demo data belongs at the service layer.

## Strings

- Every new user-facing string uses `defaultValue:` at the call site, or an
  `L10n` accessor (`Shared/Helpers/L10n.swift`) when reused three or more
  times. Components take localized `String` parameters, never
  `LocalizedStringKey`. Each ternary branch is localized separately.
  Hand-built plurals use `^[…](inflect: true)` inside the default value;
  plural-variation keys stay catalog-managed.
- In the ArkéUI package every string passes `bundle: .module`, including
  accessibility labels (`Text("key", bundle: .module)`), or the raw key
  renders. When a package key already exists in `Shared/Localizable.xcstrings`,
  copy that value verbatim.
- Building rewrites the catalogs: keys are re-sorted, orphans dropped,
  hand-added values can come back empty. Re-read after a build before
  editing an `.xcstrings` file again, and re-check values once at the end.
- Logger output and debug-only text are deliberately unlocalized.
- Translations (de, ja, zh-Hant) never gate a release; new keys go through
  `Scripts/apply_translations.py` and `Scripts/translation_lint.py`.

## bark and the FFI boundary

- **Read binding signatures from DerivedData**, under
  `SourcePackages/checkouts/bark-ffi-bindings/`, never from the stale
  checkout at `~/workspace/bark-ffi-bindings`. Server and library source is
  at `~/workspace/bark` (check `git log -1` matches the deployed tag);
  `~/workspace/noah` is a different project. The push relay is at
  `~/workspace/arke-apns-relay-node`.
- In any file that imports Bark, the package's error type is literally
  `Error`. Write `Swift.Error` for the protocol and `Bark.Error` for the
  package type.
- `BarkWalletProtocol` mirrors the FFI surface. No app-policy parameters or
  app helpers on it; typed errors are classified at the FFI boundary and
  policy lives in `WalletManager`.
- **Never recreate a wallet from seed to fix a database problem.** The bark
  db holds offchain state the seed cannot reproduce. Fresh wallets write
  `db.sqlite`, not `bark.sqlite`.
- `nil` fee rate in `progressExits` / `drainExits` means bark's own
  estimation and is correct on mainnet only. Off mainnet pass the capped
  app-side fast rate. `BlockTimeFormatter.secondsPerBlock` is the single
  block-time source for all networks.
- Bark facts B1–B6 in the playbook are verified at a bindings tag and
  re-verified on every bump; each bump also updates
  `Docs/Bark_Bindings_Unadopted_API.md` and adds a `Docs/Migrations/` folder.

## SwiftData, CloudKit and devices

- **Never read element properties off a cached to-many relationship array.**
  CloudKit imports delete rows under it and the app traps. Use the `live*`
  accessors (`liveTagAssignments`, `liveContactAssignments`,
  `liveAssignments`, `liveAddresses`), which fetch and read in one
  main-actor pass; lists build a `TransactionMetadataSnapshot` per render.
- **Read-only services on a secondary device must observe**
  `.cloudKitDataDidChange` and re-read, or they show launch-time state all
  session. Singleton rows need `sortBy: lastUpdated desc`; CloudKit has no
  unique constraints.
- **Network config is the only account-authoritative state class**, and only
  before the wallet opens. Payment data is device-local. Do not generalize
  "the account wins" to anything else. Shared keys and their scopes are
  inventoried in `SharedStateWipeCoverage` in `WalletDataCleanupService.swift`.
- **Every delete names its scope**, `.localOnly` or `.everywhere`, and only
  `WalletDataCleanupService` deletes CloudKit-mirrored rows or synchronizable
  keychain items. The seed is deleted only on a last-device full wipe.
- Nothing that needs bark runs before the handle is open; it skips with a
  log line.

## UI conventions

- `TransactionIconView(transaction:size:onDark:)` is the one transaction
  icon. `FiatAmountText` is the one fiat line; it owns currency resolution,
  the "None" choice, staleness and zero hiding.
- Four app themes share `Media.xcassets`; theme views live in Shared.
- Model types in Shared that cross actors need explicit `nonisolated` under
  the main-actor default isolation.
- Swift Testing for unit tests, async/await over Combine, no force unwraps,
  4-space indentation.
