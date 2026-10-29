# Recovery Phrase Exposure: Hide Toggle, Capture Cover, Clipboard Expiry

**Status: DONE 2026-10-29, all six device steps (§3) checked by
Christoph (Tier 0 "phrase exposure" cluster plus two Lugano UI notes,
Train 2). F1 and F2 settled by that check. F3: import screen stays
uncovered and the delete confirmation kept as is (both DECIDED
2026-10-29). Rulings DECIDED
2026-10-28: cover only while the app is not active and restore on return;
clipboard expiry 180 s. Adversarial pass done (§4); full mobile suite green
after it (TEST SUCCEEDED, no failures). No new tests: the change is view
wiring and a constant, and a test would restate it.**

## 1. Scope

Two commits in one session.

**A — UI (no review drill).**

1. The eye button on the recovery phrase screen stays visible and toggles:
   `eye` reveals all words, `eye.slash` covers them again. Covering again
   clears the scratch marks and brings back the hand icon, so the grid
   returns to its first-open state.
2. The backup sheet card swaps its lines: "Print and write your phrase"
   becomes the title, "Download backup sheet" the subtitle. Keys unchanged,
   so existing translations still apply. A user read the old card as "the
   sheet already holds the phrase".

**B — phrase exposure (Tier 0).**

3. The word grid and the QR sheet are covered by an opaque card while the
   scene is not `.active` (app switcher, Control Center, incoming call UI)
   or while it is captured (recording, mirroring, remote control). The
   reveal and scratch state is untouched, so returning shows what was
   there before.
4. The QR sheet's phrase text is no longer selectable (closes the
   long-press Copy bypass from the 2026-10-07 fault-class review).
5. `copySecretToClipboard` default lifetime 60 s → 180 s.

Out of scope: desktop (`ManualBackupView` on macOS, the macOS clipboard
path). Desktop is parked; the backlog entries keep the desktop half.

## 2. Claims

- **verified** (SDK interface, iPhoneSimulator27.1): SwiftUI
  `EnvironmentValues.isSceneCaptured` is `@available(iOS 17.0, *)` and
  `macOS, unavailable`, so it needs an `os(iOS)` island. Deployment target
  is iOS 26.2. Apple's article "Protecting sensitive content when screen
  sharing and remote control are active" names it the signal for
  recording, AirPlay mirroring and remote control, without distinguishing
  them.
- **verified** (read): the stored phrase is displayed only by
  `RecoveryPhraseSettingView` (grid via `ScratchableMnemonicGrid_iOS` /
  `MnemonicGrid`, and the `ArkeQRCodeView` sheet). The other
  `getMnemonic()` reader, `DeletePhraseConfirmationView.loadChallenge`,
  builds a two-word challenge and does not display the phrase. *Corrected
  by the review (§4, F3):* phrases the user types are shown on two more
  screens, which this change does not cover.
  `copySecretToClipboard` has one caller.
- **verified** (read): `ArkeQRCodeView` has one other caller, the desktop
  Receive QR; the new selection parameter defaults to today's behaviour.
- **derived**: a sheet inherits the presenting scene's `scenePhase` and
  `isSceneCaptured`, so the cover must be applied inside the sheet content
  as well as on the grid; a cover on the presenting view sits under the
  sheet.
- **assumed until the device check**: SwiftUI renders the `.inactive`
  update before UIKit takes the app-switcher snapshot. Apple's guidance
  says the snapshot follows `sceneDidEnterBackground`, which comes after
  `.inactive`, so the order is expected; only the phone proves it.

## 3. Device check (passed 2026-10-29, simulator does not count)

1. Open the phrase, reveal all, swipe to the app switcher: the card shows
   the cover, not words. Return: words still revealed.
2. Same with the QR sheet open.
3. Start a screen recording from Control Center, return to the app: cover
   shown while recording; stop recording: words back.
4. Eye toggle: reveal, hide (fully covered, hand icon back), scratch again.
5. QR sheet: long-press the phrase text, no Copy menu.
6. Copy, paste into Notes at ~170 s (pastes), check again at ~190 s
   (empty). Handoff paste on a second device within the window: nothing.

## 4. Adversarial pass (2026-10-28, fault-class-reviewer on the working tree)

No defect found on the covered paths. Findings and disposition:

- **F1 PLAUSIBLE (classes 4, 5):** the cover may not render before the
  app-switcher snapshot. The code comment stated the order as fact; it now
  says assumed. Settled by device check steps 1–2 (fast swipe home, slow
  switcher gesture, lock button). If it fails, the fallback is a UIKit
  window overlay in `sceneWillResignActive`.
- **F2 PLAUSIBLE (class 4):** the QR sheet's cover relies on the sheet
  seeing the scene's `scenePhase` and `isSceneCaptured`. Settled by device
  check steps 2–3 at the `.large` detent.
- **F3 CONFIRMED (classes 1, 5), filed, not fixed:** typed phrases are
  uncovered on `ImportWalletView_iOS` (the whole phrase in the text field)
  and `DeletePhraseConfirmationView` (two words with their positions).
  Missed siblings outside the backlog's surface list; filed under the
  screen-capture entry for a ruling.
- **F4 CONFIRMED (low, class 2), accepted:** while the screen is captured
  the QR sheet's cover also covers its close button. Swipe-down dismissal
  still works (no `interactiveDismissDisabled`), as does the VoiceOver
  escape gesture. Nothing leaks.
- Noted, pre-existing: VoiceOver can read `MnemonicGrid` under the scratch
  surface and reads the QR text aloud.

Not verified by anyone: the desktop build (parked, not built), and
whether "Designed for iPad on Mac" is enabled (`os(iOS)` is true there).
