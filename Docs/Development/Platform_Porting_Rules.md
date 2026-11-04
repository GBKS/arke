# Platform Porting Rules

**Status:** PROPOSED 2026-11-01. Rules for carrying a view or service from
ArkeMobile to ArkeDesktop (or the other way) so that most of the port is
mechanical and an agent can run it from a checklist. Written for the
desktop-parity track (`../Features/Desktop_Parity.md`); the MCP tracks
(`../Features/MCP_Server.md`) depend on that track, not on these rules
directly.

The premise, measured on 2026-11-01: of 77 mobile view files, 26 use no
iOS-only API at all, and the remaining ones lean on about ten recurring
patterns. 65 Shared files already handle those same patterns with `#if os()`
islands. The rules below name the pattern, the island, and the helper that
removes the island where one is worth having.

| iOS-only pattern in `ArkeMobile/` | Files | Hits | Rule |
|---|---|---|---|
| `UIApplication` (open URL, idle timer, scenes) | 14 | 32 | R4 |
| Haptics (`UIImpactFeedbackGenerator`, `sensoryFeedback`) | 13 | 27 | R3 |
| `navigationBarTitleDisplayMode` | 17 | 18 | R2 |
| `UIImage` | 6 | 22 | R4 |
| `presentationDetents` | 8 | 12 | R2 |
| `UIPasteboard` | 5 | 8 | R4 |
| `keyboardType`, `textInputAutocapitalization` | 3 | 8 | R3 |
| `ShareLink`, `UIActivityViewController` | 3 | 4 | R4 |
| `TabView`, tab-bar toolbar | 3 | 4 | R2 |
| `AVAudioSession`, `UIScreen`, `UIDevice` | 4 | 7 | R5 |

## R1 — One Shared view by default

A ported view lives once in `Shared/` with islands, as `CLAUDE.md` already
says. Keep a platform copy (`_iOS` / `_macOS` suffix) only when the
**navigation container or the input modality differs structurally**: a tab
shell versus a sidebar, a swipeable card stack versus a table, a camera
scanner versus a text field. Everything inside the container (rows, cards,
sheets, forms, detail pages) is Shared.

When a mobile view is ported, the desktop copy of the same screen is deleted
in the same change. Two copies of one screen is the state that made desktop
drift in the first place.

## R2 — Layout and navigation mapping

| iOS | macOS |
|---|---|
| `NavigationStack` push | detail column of the existing `NavigationSplitView` in `WalletView`, or a `NavigationStack` inside the column for second-level pages |
| `TabView` | `WalletSidebar` section |
| `.sheet` + `.presentationDetents([.medium])` | `.sheet` + `.frame(width:height:)` from the preset table below |
| `.presentationDetents([.large])`, `fullScreenCover` | `.sheet` at the large preset, or a second window when the content is a workflow |
| `.navigationBarTitleDisplayMode(.inline)` | omitted (island) |
| `.toolbar(.hidden, for: .tabBar)` | omitted |
| Pull to refresh | `.refreshable` works on both; also add a toolbar refresh button on macOS |

Sheet presets (add as `SheetSize` in ArkéUI, values from the existing
islands: `TransactionContactView` uses 400×400, `ContactSelectorSheet` and
the settings detail views cap width):

| Preset | Size | Use |
|---|---|---|
| `.compact` | 400 × 400 | pickers, single-choice sheets |
| `.form` | 480 × 560 | forms with a few fields and a primary button |
| `.page` | 640 × 720 | detail pages, receipts, technical details |

Width caps on macOS stay as they are today: `#if os(macOS) .frame(maxWidth:)`
on content that would otherwise stretch across a wide window.

## R3 — Input

| iOS | macOS |
|---|---|
| Haptic on success / error / selection | nothing. Route every call through a `Haptics` helper in Shared whose macOS body is empty, so the island disappears from the view |
| `keyboardType`, `textInputAutocapitalization`, `scrollDismissesKeyboard` | island, omitted on macOS |
| Swipe actions on rows | `.contextMenu` with the same actions, plus hover-revealed buttons where the row has room; keep `.swipeActions` for iOS in the same view |
| Long press | `.contextMenu` |
| Paste button next to a field | keep the button; macOS also gets ⌘V via the Edit menu for free |
| Camera QR scan, NFC | not ported. The input-method picker shows paste and contacts only; where a mobile flow starts from a scan, the desktop flow starts from the field |
| Drag gestures for dismissal or card navigation | not ported; the container is platform-specific under R1 |
| Pointer | add `.help()` tooltips on icon-only buttons and `.onHover` cursor changes only where the control looks like a link, as `ContactInfoBanner` does |

Keyboard shortcuts are a desktop addition, not a port. Give each main
section and each primary sheet action a `.keyboardShortcut` when the view is
ported; record them in `Desktop_Parity.md` so they stay consistent.

## R4 — Platform API shims

| Need | Use |
|---|---|
| Copy to pasteboard | `copyToClipboard` / `copySecretToClipboard` in `Shared/Helpers/Clipboard.swift` |
| Images | a `PlatformImage` typealias in ArkéUI (`UIImage` / `NSImage`) plus `Image(platformImage:)`; `ProfilePhotoPickerView` already holds the two branches to lift |
| Open a URL | the `openURL` environment action, never `UIApplication.shared.open` |
| Open system settings | `ContactImportSheet` has the two-branch pattern; lift it into a `SystemSettingsOpener` helper if a third site appears |
| Share | `ShareLink` works on both platforms; `ShareHelper` stays iOS-only for the activity-controller cases |
| Colors | ArkéUI `ColorExtensions` shims (`systemBackground`, `systemControlBackground`); no `UIColor.*` in Shared |
| Video players | `LoopingVideoPlayer_iOS` and desktop `LoopingVideoPlayer` keep their names; views pick with an island, as the boarding and refresh modals do |
| Screen brightness, screenshot cover, idle timer | iOS-only islands; macOS body is a no-op, as `PhraseExposureCover` already is |

## R5 — Lifecycle

Mobile's `scenePhase` work (backup on background, exit check-in, relay auth
renewal, VTXO refresh reschedule, journal compaction) and the AppDelegate
push handling belong in one Shared `AppLifecycleCoordinator` with an
`onForeground()` / `onBackground()` surface. Both app entry points call it;
BGTask scheduling and Live Activity stay inside iOS islands in the
coordinator. This is **not** a mechanical port: it is startup-shaped and gets
the full review (trace writer → store → reader, cold-start path, adversarial
pass) and a `Launch_Sequence_Contract.md` rule if a new invariant appears.

Services gated off macOS wholesale today (`WalletManager+Notifications`,
`BackgroundTaskCoordinator`, `ExitProgressionNotifications`) are un-gated one
at a time with the same review depth. `UNUserNotificationCenter` and
`registerForRemoteNotifications` already work on macOS; BGTask does not and
needs a foreground-only or `NSBackgroundActivityScheduler` decision first.

## R6 — Strings, assets, tests

- Strings follow `Localization_Guidelines.md` unchanged. A view moving to
  Shared keeps its keys; the catalog re-extracts on the next IDE build.
- Image sets a ported view needs are added to the desktop asset catalog in
  the same change; the first-use port did this for the intro thumbnails.
- Decision tests stay in `Tests/Shared/` and run on iOS. A view port adds no
  test unless it extracts a decision; the verification is visual (R7).

## R7 — Verification per port

1. `XcodeRefreshCodeIssuesInFile` on every edited file.
2. Build **both** app targets. `xcodebuild` for the desktop target is
   `-scheme "Arké" -destination 'platform=macOS'`; it does not re-extract
   strings, so the IDE build of the mobile target follows.
3. One screenshot per ported screen on macOS at the default window size and
   one at a narrow width, filed under the session index like simulator
   screenshots.
4. Sweep: list every other site that used the deleted desktop copy or the
   moved mobile file as covered / exempt / missed.
5. The macOS test suite is evidence only once the Tier 1 flakiness item is
   closed; until then run the mobile suite once at task end as usual.

## Lint

`Scripts/platform_lint.py` (to write): walks `Shared/` and `ArkeUI/Sources/`
and flags any line matching the iOS-only patterns in the table above that is
not inside an `#if os(iOS)` / `#if canImport(UIKit)` block. Also flags a
`_iOS` file in `ArkeMobile/` that has a same-named file in `ArkeDesktop/`,
which is the drift signal R1 is meant to remove. Runs like
`backlog_stats.py`: by hand, before a commit plan.

## Agent checklist for one port

Hand an agent one mobile file or one area and this list:

1. Classify under R1: Shared with islands, or platform copy with a reason.
2. Move the file to the matching `Shared/Views/<Area>/` folder, drop the
   `_iOS` suffix, apply R2–R4 line by line, prefer the helper over an island.
3. Wire the view into the desktop container (`WalletView` section or settings
   list), delete the desktop copy, and move anything only the desktop copy
   had into the Shared view behind an island.
4. Add the keyboard shortcut and `.help()` text (R3).
5. Run R7 and report: files moved, files deleted, islands added, helpers
   used, sibling sweep, screenshots.

Area batches, review depth and order live in `Desktop_Parity.md`.

## Open calls (Christoph)

- Whether the three sheet presets are the right sizes, or whether sheets on
  macOS should size to content with a minimum.
- Whether keyboard shortcuts are part of the port or a later desktop pass.
- Whether the lint script is worth writing before the first batch or after.
