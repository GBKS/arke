# Development Setup

What you need to build, run and test Arké as of 2026-10-07. Every value
below was read from the project or the toolchain on that date; when one
drifts, fix it here. The previous guide (macOS app driving the bark CLI) is
in `../Archive/Development/Setup.md`.

## Toolchain

| Item | Value | Source |
|---|---|---|
| Xcode | 27.0 | `xcodebuild -version` |
| iOS deployment target | 26.2 | `IPHONEOS_DEPLOYMENT_TARGET` |
| macOS deployment target | 26.x (mixed 26.0–26.2 across configurations) | `MACOSX_DEPLOYMENT_TARGET` |
| Swift language mode | 5 (`SWIFT_VERSION = 5.0`) in the app targets; ArkéUI package is tools-version 6.2 | `project.pbxproj`, `ArkeUI/Package.swift` |
| Bundle id | `GBKS.Arke` | Info.plist |

No external tools are required. There is no bark CLI; the wallet library
arrives as a binary package (below).

## Open and build

Open `Arke.xcodeproj`. Three shared schemes:

| Scheme | Target | Use |
|---|---|---|
| `Arke mobile` | ArkeMobile (iPhone) | the product; all day-to-day work |
| `Arké` | ArkeDesktop (macOS) | parked; builds, but its test suite is flaky and nothing is verified on it |
| `ArkeWidgetsExtension` | ArkeWidgets | widget extension; only when touching widgets |

Package dependencies resolve on first open. The bark wallet library comes
from `bark-ffi-bindings` (gitlab.com/ark-bitcoin), pinned to an **exact
revision** in the project (Package Dependencies → Revision; since
2026-10-26, tag `v0.26.1+bark-0.8.0` since 2026-10-27). Its `Package.swift`
declares a `binaryTarget` that downloads `BarkFFI.xcframework.zip` for the
matching release. Nothing is built locally; the `.gitignore` entries for
`bark_ffi.swift` and `/BarkFFI.xcframework` are left over from the
hand-vendored era. The resolved binding source, which is the only correct
place to read FFI signatures, lives under
`~/Library/Developer/Xcode/DerivedData/Arke-<hash>/SourcePackages/checkouts/bark-ffi-bindings/`.

The bindings repo holds no Rust. The xcframework is built from the separate
`gitlab.com/ark-bitcoin/bark-ffi` crate, pinned by commit in the bindings'
`swift/rust/Cargo.toml`, which in turn pins `bark-wallet` by git rev in its
`Cargo.lock`. To tell whether a bindings release changes our binary, diff
that `rev` between the two tags; a patch release that only touches the
other language wrappers (v0.26.1 did) keeps the same rev and only the
checksum moves.

Other pins, with their rules and the one file that imports each:
`bdk-swift` ≥ 3.1.1 up to next major (`BDKFeeEstimator.swift`, fee preview
only), `BIP39` exact 3.0.0 (`BIP39Usage.swift`, mnemonic generation and
validation), `qrcode` ≥ 28.1.0 up to next major (`QRCodeGenerator.swift`),
`swift-qrcode-generator` and `SwiftImageReadWrite` (transitive, through
`qrcode`), and `Hallmarks` ≥ 1.0.0 (declared by the local `ArkeUI`
package, which holds the previewable UI components and its own string
catalog). Rules are edited in Xcode's Package Dependencies UI, never in
`project.pbxproj` by hand. "Update to Latest Package Versions" moves a
package only inside its rule, so a major bump is always a deliberate rule
change plus a diff of the upstream tags against our call sites (last done
2026-10-27).

After any bump of a binary package (bark, bdk) the first build fails with
`<Name>FFI.h has been modified since the module file … .pcm was built`,
followed by dozens of `Cannot find 'uniffi_…_checksum_…' in scope` errors
inside the package's generated Swift. Nothing is wrong with the pin: the
Swift compiler is reusing a module precompiled from the old header. Delete
the `<Name>FFI-*.pcm` directories under
`DerivedData/Arke-<hash>/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules/`
(or Clean Build Folder) and build again. Hit on 2026-10-25 (barkFFI) and
2026-10-27 (BitcoinDevKitFFI).

Code layout: `ArkeMobile/`, `ArkeDesktop/`, `ArkeWidgets/` hold the
platform-specific entry points and views; `Shared/` holds everything else
and is a synchronized folder attached to both app targets; `ArkeUI/` is the
local Swift package; `Tests/` is synchronized into both test targets;
`Docs/` is a synchronized folder in no target; `Scripts/` holds the
localization tooling.

## Run

Pick a simulator or a device in the run destination and run `Arke mobile`.
The app defaults to mainnet; signet is selectable from the cover screen and
is the network for all testing. A signet faucet is built into the app.

Watch the run destination before running tests through Xcode's test
tooling: the MCP test runners use the active destination, and a crashed
state-touching test host once left a tombstone in a real phone's app
defaults. Keep a simulator selected when testing.

## Test

The authoritative runner is `xcodebuild` against a simulator; the
`Arke mobile` test plan runs the `ArkeMobileTests` target (Swift Testing).

```bash
# scoped suite while working
xcodebuild test -project Arke.xcodeproj -scheme "Arke mobile" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ArkeMobileTests/<SuiteName>

# whole mobile suite before a commit plan
xcodebuild test -project Arke.xcodeproj -scheme "Arke mobile" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Xcode previews and the code-snippet runner fail on the bark static
archive; visual checks happen in the simulator or on a device. The macOS
suite fails about 68 tests flakily on a clean tree and proves nothing until
that is fixed (`../Open_Follow_Ups.md`, test infrastructure). Patterns and
conventions for writing tests are in `Testing_Patterns.md`.

## Logs

Services log through `os.Logger` with subsystem `GBKS.Arke`. On a
simulator:

```bash
xcrun simctl spawn booted log show --last 15m --info --debug --style compact \
  --predicate 'subsystem == "GBKS.Arke"'
```

`--info --debug` is mandatory or info-level lines are dropped. Simulator
logs show private interpolations in full; device logs redact them. Do not
use `log stream`; it wedges the simulator. Device logs are exported from
the X-Ray screen in the app. The build number is not bumped per build, so
identify a device build by distinctive log lines plus `git log -S`.

## Localization tooling

`Scripts/` (Python 3, no dependencies):

- `translation_lint.py` — empty translated values and format-specifier
  mismatches, the same checks as `LocalizationCatalogTests` but naming the
  keys.
- `apply_translations.py` — writes a JSON of `{key: {lang: value}}` into
  every catalog that has the key.
- `localization_audit.py`, `migrate_defaultvalue.py` — the completed
  `defaultValue:` migration; kept for reruns.

Rules for strings are in `../Localization/Localization_Guidelines.md`.

## Related source checkouts

- `~/workspace/bark` — Ark server and library source; confirm the tag
  matches the deployed version before relying on it.
- `~/workspace/arke-apns-relay-node` — the push relay.
- `~/workspace/bark-ffi-bindings` — stale checkout; do not read signatures
  from it.
- `~/workspace/noah` — a different project's server.
