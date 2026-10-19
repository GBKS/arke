//
//  ScreenBrightnessBooster.swift
//  Arké
//
//  Created by Assistant on 10/19/26.
//

import SwiftUI
import UIKit
import os

/// Raises the screen to full brightness while a QR code is on screen and
/// puts the user's own level back afterwards, so a dim phone still scans at a
/// counter.
///
/// `boost()` and `restore()` are idempotent: the user's level is captured on
/// the first boost and cleared on restore, so repeated calls from view
/// lifecycle events are safe. iOS itself resets brightness when the device
/// locks, so a missed restore never outlives the session.
@MainActor
final class ScreenBrightnessBooster {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ScreenBrightness")

    /// The user's brightness before the boost; nil while not boosted
    private var savedBrightness: CGFloat?

    /// The ramp in flight, if any; a new boost or restore replaces it
    private var ramp: Task<Void, Never>?

    /// How long a change takes. `UIScreen.brightness` has no animation of
    /// its own, so the value is stepped over this duration; an instant jump
    /// to full brightness read as a flash (Christoph, 2026-10-19).
    private static let rampDuration: Duration = .milliseconds(500)
    private static let rampSteps = 25

    /// Screen of the foreground window scene; brightness is only supported on
    /// the main screen, which is the one every window scene reports on iPhone
    private var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    func boost() {
        guard savedBrightness == nil, let screen else { return }
        let userLevel = screen.brightness
        savedBrightness = userLevel
        rampBrightness(of: screen, to: 1.0)
        Self.logger.info("🔆 Screen brightness boosted for QR display (was \(userLevel, privacy: .public))")
    }

    func restore() {
        guard let savedBrightness, let screen else { return }
        self.savedBrightness = nil
        rampBrightness(of: screen, to: savedBrightness)
        Self.logger.info("🔅 Screen brightness restored to \(savedBrightness, privacy: .public)")
    }

    /// Eases the screen from its current level to `target` over `rampDuration`.
    /// Cancels any ramp still running so boost-then-restore in quick
    /// succession ends at the last requested level, never mid-way.
    private func rampBrightness(of screen: UIScreen, to target: CGFloat) {
        ramp?.cancel()
        let start = screen.brightness
        guard abs(target - start) > 0.001 else { return }
        let steps = Self.rampSteps
        let stepDuration = Self.rampDuration / steps
        ramp = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(for: stepDuration)
                guard !Task.isCancelled else { return }
                // Ease in-out so the change starts and ends gently
                let t = CGFloat(step) / CGFloat(steps)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                screen.brightness = start + (target - start) * eased
            }
        }
    }
}

/// Keeps the screen at full brightness while the modified view is on screen
/// and the app is in the foreground. Attach to the root of any view that
/// shows a QR code.
///
/// Presentation and dismissal call the booster directly from `onAppear` /
/// `onDisappear`: a dismissed sheet's view tree is gone, so a state write in
/// `onDisappear` never reaches an `onChange` on the same view (the first cut
/// did that and left the screen bright after "Done", simulator log
/// 2026-10-19). Backgrounding is handled through the scene phase while the
/// view is still mounted.
private struct BrightScreenWhileVisible: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var booster = ScreenBrightnessBooster()
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                if scenePhase == .active {
                    booster.boost()
                }
            }
            .onDisappear {
                isVisible = false
                booster.restore()
            }
            .onChange(of: scenePhase) { _, phase in
                guard isVisible else { return }
                if phase == .active {
                    booster.boost()
                } else {
                    booster.restore()
                }
            }
    }
}

extension View {
    /// Full screen brightness while this view is visible and the app is
    /// active; the user's level comes back when it goes away.
    func brightScreenWhileVisible() -> some View {
        modifier(BrightScreenWhileVisible())
    }
}
