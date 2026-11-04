# Desktop Parity

**Status:** PROPOSED plan (2026-11-01 inventory) on top of the DONE phases
below. Track 1 of three (`MCP_Server.md` holds Tracks 2 and 3). Porting
rules live in `../Development/Platform_Porting_Rules.md`; this doc holds the
inventory, the batches and their order.

Bringing ArkeDesktop up to parity with the mobile app after the July 2026
mobile-focused push. Based on a full parity review on 2026-08-11 comparing
views, service wiring, and git history since desktop's last substantive
feature work (June 25 – July 10), refreshed 2026-11-01.

## Status

| Phase | Scope | Status |
|---|---|---|
| Onboarding parameters | Network selection, backup-file restore, non-blocking import | ✅ Done (`9180d67`) |
| Network-mismatch recovery | Stale wallet data from another network wiped on seed-only import | ✅ Done (`3ef99b9`) |
| Settings Phase 1 | Three-column settings, shared detail views | ✅ Done (`d0748af`) |
| First-use flow | Intro videos, cinematic create-with-retry, mobile flow order | ✅ Done (2026-08-11) |
| Batch 0 | macOS test suite trustworthy | ⬜ gates everything (Tier 1) |
| Batch 1 | Porting rules, helpers, lint | ⬜ |
| Batch 2 | Lifecycle parity (`MainView`, scene phase) | ⬜ gates MCP Track 2 |
| Batch 3 | Exits and X-Ray | ⬜ |
| Batch 4 | Activity | ⬜ gates MCP Track 2 |
| Batch 5 | Settings leftovers | ⬜ |
| Batch 6 | Contacts, onboarding server sheet | ⬜ |
| Batch 7 | Notifications end to end | ⬜ needs a design call |

## 2026-11-01 inventory

Measured on main at `7c8f8b7` plus the uncommitted Ark-server-selection
work. The desktop target **builds clean** (`xcodebuild -scheme "Arké"`,
one harmless framework-symlink warning). Shared-wide refactors kept it
compiling through 2026-10-28, including the send fee quotes and the "Pay
from" picker; the desktop-only views froze around 2026-08-17.

| Target | Files | Lines |
|---|---|---|
| ArkeMobile | 77 | 19,900 |
| ArkeDesktop | 49 | 8,400 |
| Shared | 304 | 67,500 |
| ArkéUI | 81 | 13,700 |

Mobile view code by class:

| Class | What | Lines |
|---|---|---|
| Missing on desktop, portable (no or few iOS-only APIs) | `ExitView_iOS`, `UnilateralExitListView_iOS`, `ExitStatusDetailView_iOS`, `ExitVtxoRowView_iOS`, `ExitOnchainInfoRows` | ~1,860 |
| | `PendingRoundsListView_iOS` | 272 |
| | `TransactionTechnicalDetailsView`, `TransactionReceiptSheet`, `TransactionClaimExitBanner` | ~480 |
| | `PaymentInfoReceivedSheet` | 411 |
| | `DeviceAssignmentSheets_iOS` (promote / demote) | 174 |
| | `BalanceInfoSheet`, `DebugLogExportButton_iOS`, `SendInputMethodPicker_iOS`, `PasteButton_iOS` | ~330 |
| | `CurrencySettingView`, `FeeRatesSectionView`, `FiatRatesSectionView` wiring | one line each |
| Stale desktop copy | `MainView` (no foreground re-check, no protected-data re-check, no CloudKit stop or `setActive(false)` on delete, none of the scene-phase foreground work); `ActivityView`, `TransactionList`, `TransactionDetailView`; `ContactsView`, `ContactRow`, `ContactDetailView`; `LinkedDevicesView`; `DataView`; `BitcoinFormatSettingView`; `SendView.quickModeView` does not pass `sendViewModel`, so quick mode lacks fiat entry and the live funding-source ranking | — |
| Needs a design call | `LightningInvoiceSheet_iOS` (788; owner view portable, rotated recipient view and brightness are mobile-only); `NotificationsSettingView_iOS` plus un-gating `WalletManager+Notifications`, `RelayRegistrationService`, `ExitProgressionNotifications`, and an `AppDelegate` equivalent | ~960 + plumbing |
| Mobile-only by nature, not ported | QR scanner, NFC, `ProximityExchangeManager`, tilt share, `ScreenBrightnessBooster`, `TransactionCardStackView_iOS`, `TransactionSwipeCard`, `BackgroundActivityView_iOS`, Live Activity, BGTask | ~2,500 |
| Desktop debt to delete | `FirstUse/Server/*` (dormant usage-profile flow), replaceable by the Shared `ArkServerSelectionSheet` | ~1,390 |

Already at parity through Shared views: Balance (board, offboard, refresh
modals), Send flows and fee UI, Receive core, Tags (desktop is richer),
Settings detail pages, Delete wallet, Recovery phrase, Rejoin, VTXO and UTXO
lists.

Shared services on macOS: `RelayRegistrationService` compiles but is never
created; `WalletManager+Notifications`, `BackgroundTaskCoordinator` and
`ExitProgressionNotifications` are compiled out and every caller is
wrapped in `#if os(iOS)`; `MotionManager` logs and does nothing;
`DebugLogExporter` and `BackgroundActivityAssertion` degrade gracefully.

## Batches

Each batch is one agent run per area with the checklist in
`Platform_Porting_Rules.md`, a both-target build, screenshots, and the
sibling sweep. Sizes are files and lines, not time.

**Batch 0 — Trustworthy macOS suite.** Backlog Tier 1 item. First step is
one diagnostic run with `-parallel-testing-enabled NO`; the `Arké` scheme
has both test bundles `parallelizable = "YES"` and the mobile runner already
needed parallel testing off. If serial is green, the fix is the scheme
setting plus `.serialized` where state is shared; if not, scratch-scoped
keychain and defaults in the test host. Nothing below counts as verified on
macOS until this closes. **Do not run the suite casually:** the test host
shares the Mac's preferences domain and keychain group with the real desktop
app.

**Batch 1 — Rules, helpers, lint.** Adopt `Platform_Porting_Rules.md`; add
`Haptics`, `PlatformImage`, `SheetSize` helpers; write
`Scripts/platform_lint.py`. One session, no behavior change.

**Batch 2 — Lifecycle parity.** `AppLifecycleCoordinator` (rule R5) with the
four missing MainView pieces and the scene-phase foreground work. Tier 1
review depth, adversarial pass, two-device check (a Mac that is a
secondary must pick up the seed and the promotion). Gates MCP Track 2.

**Batch 3 — Exits and X-Ray.** The exit view into Settings' danger zone,
unilateral exit list, exit status detail, pending rounds, fee-rate and
fiat-rate sections, log export, claim-exit banner on the detail page. About
2,300 lines moving to Shared; backing services already run on desktop. No
check-in reminders in v1.

**Batch 4 — Activity.** Filter chips, empty state, technical details,
receipt, fiat line, connection-info sheet, the never-cleared banner,
`PaymentInfoReceivedSheet`, and the quick-mode `sendViewModel` fix. Mobile's
card stack stays mobile (R1); the desktop list stays a table with context
menus. Gates MCP Track 2 (agent payments must be visible and attributable).

**Batch 5 — Settings leftovers.** Currency page wiring, promote / demote
sheets, bitcoin-format page, intro-video replay row, hide-balance toggle once
the desktop balance card honors it, testing views behind DEBUG.

**Batch 6 — Contacts and onboarding.** Contact list search and empty state,
detail summary and signet-faucet section, and the swap of the dormant
`FirstUse/Server/*` suite for the Shared `ArkServerSelectionSheet` (deletes
about 1,390 lines).

**Batch 7 — Notifications end to end.** Un-gate the relay stack on macOS,
port the notifications page, decide foreground-only versus
`NSBackgroundActivityScheduler` for refresh. Needs the design call first;
touches the relay registration path, so Tier 1 depth.

Protect during all batches: tags graph and net-change bar, contact editor
auto-assign, `TransactionLinkedOnchainView_macOS`.

## Done (2026-08-11)

- **Onboarding**: mainnet/signet toggle (testtube button on `FirstUseView`),
  optional backup-file restore via `importWalletWithBackup`, no blocking
  `sync()` after import. Desktop onboarding now matches mobile's flow.
- **Seed-only import resilience**: leftover wallet data from another network
  (common on macOS — the container survives reinstalls) is surfaced by the
  FFI as `BarkWalletFFIError.networkMismatch`; `WalletManager.importWallet`
  wipes it and retries once. Backup restores deliberately do NOT wipe —
  a mismatch there means the wrong network was selected for the backup file.
- **Settings**: `WalletView` gained a three-column settings branch (sidebar |
  settings list | detail), matching the activity/contacts/X-Ray pattern. The
  middle column mirrors mobile's section order. Platform-clean detail views
  live once in `Shared/Views/Settings/` with `#if os()` islands
  (fee summary/schedule + analytics model, address history, address patterns,
  profile editor + photo picker); `RecoveryPhraseSettingView` was already
  shared. Desktop-specific: `SettingsView` (selection list vs mobile's
  NavigationStack), `ManualBackupView` (flattened page, `NSSavePanel` export).
  Verified: both builds green, 155/155 mobile tests, iOS rendering unchanged
  (ArkeUI color shims; width caps gated to macOS).
- **First-use flow**: desktop `OnboardingFlow` now mirrors mobile — firstUse →
  introVideos → createWallet → straight into the wallet; usage-pattern /
  server-selection screens dormant (enum cases kept, view code commented, same
  as mobile). New desktop ports: `IntroVideoView` + `IntroVideoPlayer`
  (NSViewRepresentable, no audio session); `CreateWalletView` rewritten to run
  creation in parallel with the play-once `magic-wallet-creation` video, with
  mobile's categorized retry loop and Retry/Go-back alert. Playlist data
  (titles, asset names, subtitle timings) extracted to
  `Shared/Models/IntroVideoLibrary.swift`, consumed by both platforms.
  `LoopingVideoPlayer` (desktop) gained `loops:`/`onCompletion:`. Onboarding
  screens adopt `.glass`/`.glassProminent`. Thumbnails + `bitcoin-wallet`
  imagesets copied into the desktop asset catalog; signet intro mp4s added to
  the desktop target. All onboarding video assets are portrait (intro videos
  720x1280; cover/create videos 464x832), so every video screen uses the
  cover screen's two-column layout: video left, content right. On the intro
  screen the playlist mobile hides behind a hamburger overlay is permanent
  right-column content (no scrim/pause-on-open); on the create screen the
  spinner and "Step in" reveal live in the right column.

## Remaining work (2026-08-11 notes, superseded by the batches above)

### Settings Phase 2 — Exit / Force Move view

Port `ArkeMobile/Views/Settings/Exit/ExitView_iOS.swift` (~440 lines): cost
estimation, in-flight exit tracking, uncovered VTXO listing, confirmation
flow. Backing services (ExitProgressionService, ExitStore) are shared and
already run on desktop. Ship v1 **without** check-in reminders — that
machinery lives in the iOS-gated Live Activity file and matters less on a
foregrounded desktop app. `IntroVideoPlayer_iOS` usage can map to the desktop
`IntroVideoPlayer` (ported for the first-use flow) or `LoopingVideoPlayer`.

### Settings Phase 3 — Notifications page + relay un-gating

The UI port is easy; the point is the plumbing: `WalletManager+Notifications`
and `RelayRegistrationService` are `#if os(iOS)` but the underlying APIs work
on macOS (`UNUserNotificationCenter` is cross-platform;
`NSApplication.shared.registerForRemoteNotifications()` is already called in
`ArkeDesktop/Views/MainView.swift`; `aps-environment` is in the
entitlements). Un-gating closes desktop's "no mailbox push, no relay auth
refresh" gap. Design needed for background refresh (no BGTask on macOS —
consider `NSBackgroundActivityScheduler` or foreground-only).

### Exit UI on transaction detail

Explicitly deferred in `Exit_Blocked_State.md`: desktop
`TransactionDetailView` has no exit section. Mobile pieces to mirror:
`TransactionClaimExitBanner` (segmented progress, blocked-fee explanations),
`ExitStatusDetailView_iOS`, `ExitVtxoRowView_iOS`, `ExitOnchainInfoRows`,
`UnilateralExitListView_iOS`, `PendingRoundsListView_iOS`. All backing data
comes from shared services (ExitStore, PersistentExitCache, fee attribution).

### Activity polish

- Expandable technical details (`TransactionTechnicalDetailsView`)
- Connection status / read-only indicator in the toolbar
- Interactive filter chips, transaction receipt, balance info sheet

### Deliberately skipped (revisit when relevant)

- **Hide-balance toggle**: `balancePrivacyKey` is consumed by no desktop
  view; add the toggle when the desktop balance card honors it.
- **Linked-devices promote/demote**: mobile's `LinkedDevicesView_iOS` has
  role-change sheets; desktop's view lacks them. Reconciliation is its own
  task.
- **Proximity sharing, tilt share, NFC, QR camera, card-stack navigation,
  Live Activities, BGTask**: iOS-only by nature.
- **Intro-video replay row**: no longer blocked — desktop now has
  `IntroVideoView`/`IntroVideoPlayer` and the video assets; add the settings
  row when wanted.

### Desktop-only features to protect during parity work

Server-selection onboarding suite (`FirstUse/Server/` — dormant since the
first-use parity pass: enum cases kept, flow routes around it), tags graph +
net-change bar, contact editor auto-assign UI. None exist on mobile.

## Working notes

- **Shared file membership**: ArkeMobile receives `Shared/` files only via a
  whitelist (`membershipExceptions`) in `project.pbxproj`. New Shared files
  need a manual Target Membership tick for ArkeMobile in Xcode; desktop syncs
  all of `Shared/` automatically. Never edit `project.pbxproj` directly.
- **View sharing rule**: one Shared view with `#if os()` islands beats
  per-platform copies whenever only small APIs differ (pasteboard, haptics,
  image types, `navigationBarTitleDisplayMode`). Keep views platform-specific
  only for genuinely different structure. ArkeUI's `ColorExtensions` has
  cross-platform shims (`systemBackground`, `systemControlBackground`) —
  prefer them over UIKit-only colors.
