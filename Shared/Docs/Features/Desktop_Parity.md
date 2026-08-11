# Desktop Parity

Bringing ArkeDesktop up to parity with the mobile app after the July 2026
mobile-focused push. Based on a full parity review on 2026-08-11 comparing
views, service wiring, and git history since desktop's last substantive
feature work (June 25 – July 10).

## Status

| Phase | Scope | Status |
|---|---|---|
| Onboarding parameters | Network selection, backup-file restore, non-blocking import | ✅ Done (`9180d67`) |
| Network-mismatch recovery | Stale wallet data from another network wiped on seed-only import | ✅ Done (`3ef99b9`) |
| Settings Phase 1 | Three-column settings, shared detail views | ✅ Done (`d0748af`) |
| First-use flow | Intro videos, cinematic create-with-retry, mobile flow order | ✅ Done (2026-08-11) |
| Settings Phase 2 | Exit / Force Move view | ⬜ Next |
| Settings Phase 3 | Notifications page + relay service un-gating | ⬜ |
| Exit UI on transaction detail | Blocked-state banner, exit status views | ⬜ |
| Activity polish | Technical details, receipt, connection status | ⬜ |

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

## Remaining work

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
