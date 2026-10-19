//
//  LoadingWaveModifier.swift
//  Arké
//
//  The "still loading" wave on an amount: a shallow per-glyph opacity dip
//  travelling across the digits while `isLoading` is true, no tint (works
//  on every theme), no motion of the glyphs themselves. Extracted from
//  BalanceCard on 2026-10-19 so the balance details view's two totals can
//  carry the same wave, each driven by its own source (Open_Follow_Ups
//  "Loading wave on the balance details totals", DECIDED 2026-10-19).
//
//  BalanceLoadIndicatorModel holds the rules (arming delay, finish the
//  pass, Reduce Motion); this modifier owns the clocks. Apply it directly
//  to the Text that shows the amount.
//

import SwiftUI
import os

struct LoadingWave: ViewModifier {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "LoadingWave")

    /// The source's "still loading and an amount is on screen" signal.
    let isLoading: Bool
    /// Names the amount in debug logs only ("card", "payments", "savings").
    var label: String = "amount"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadIndicator = BalanceLoadIndicatorModel()
    /// Position of the glyph-opacity trough during a pass, 0 to 1. Both ends
    /// render every glyph at full opacity, so 0 is also the resting value.
    @State private var sweepProgress: Double = 0

    /// Loading must run this long before anything shows, so a short
    /// pull-to-refresh never flashes.
    private static let armingDelay: Duration = .seconds(1)
    /// Slow and continuous: a three-second pass with no rest reads as
    /// breathing. The short passes with rests tried first (1 s and 0.5 s
    /// with 2 s rests) felt hectic on the device (device looks 2026-10-13).
    private static let sweepPassSeconds: TimeInterval = 3
    private static let sweepRestDuration: Duration = .zero
    /// Reduce Motion only: with no wave, a static dim is the whole signal
    /// (DECIDED 2026-10-13, the 75 % baseline on top of the wave muddled
    /// both).
    private static let quietAmountOpacity = 0.75

    func body(content: Content) -> some View {
        content
            .textRenderer(GlyphWaveTextRenderer(progress: sweepProgress))
            .opacity(reduceMotion && loadIndicator.isQuiet ? Self.quietAmountOpacity : 1)
            .animation(.easeInOut(duration: 0.3), value: loadIndicator.isQuiet)
            .onChange(of: reduceMotion, initial: true) { _, reduce in
                loadIndicator.reduceMotion = reduce
            }
            .onChange(of: isLoading, initial: true) { _, running in
                loadIndicator.refreshingWithDataChanged(running)
                Self.logger.info("〰️ [\(self.label, privacy: .public)] loading=\(running) → \(String(describing: self.loadIndicator.phase), privacy: .public)")
            }
            .task(id: loadIndicator.phase == .arming) {
                guard loadIndicator.phase == .arming else { return }
                try? await Task.sleep(for: Self.armingDelay)
                guard !Task.isCancelled else { return }
                loadIndicator.armingDelayElapsed()
                Self.logger.info("〰️ [\(self.label, privacy: .public)] armed → \(String(describing: self.loadIndicator.phase), privacy: .public)")
            }
            .task(id: loadIndicator.wantsSweepLoop) {
                guard loadIndicator.wantsSweepLoop else { return }
                await runSweepLoop()
            }
    }

    /// Pass, rest, repeat, for as long as the model allows another pass. The
    /// model decides whether loading that ended mid-pass finishes the pass
    /// (it does) or whether one that ended during the rest starts another
    /// (it does not). Cancellation, e.g. the view leaving the screen, resets
    /// the wave and closes any pass so the model cannot stay in `inPass`.
    private func runSweepLoop() async {
        defer {
            resetSweepWithoutAnimation()
            loadIndicator.passEnded()
        }
        while !Task.isCancelled && loadIndicator.mayStartPass {
            loadIndicator.passStarted()
            Self.logger.info("〰️ [\(self.label, privacy: .public)] pass started")
            // Park the trough before the first glyph and let SwiftUI commit
            // that frame before animating. Written in the same turn as the
            // animated write, the two writes would collapse to "no change"
            // and nothing would sweep (review finding 2026-10-13).
            resetSweepWithoutAnimation()
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: Self.sweepPassSeconds)) {
                sweepProgress = 1
            }
            try? await Task.sleep(for: .seconds(Self.sweepPassSeconds))
            guard !Task.isCancelled else { return }
            loadIndicator.passEnded()
            guard loadIndicator.mayStartPass else { return }
            try? await Task.sleep(for: Self.sweepRestDuration)
        }
    }

    /// 1 → 0 is visually a no-op (the trough is off the text at both ends),
    /// but when it lands in the same update as the settle, the amount's
    /// `.animation(value: isQuiet)` would interpolate it and draw a quick
    /// wave running backwards (device look 2026-10-13). Disable animation
    /// for the reset explicitly.
    private func resetSweepWithoutAnimation() {
        // `SwiftUI.` because the app has its own `Transaction` model type.
        var transaction = SwiftUI.Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sweepProgress = 0
        }
    }
}

extension View {
    /// The "still loading" glyph wave while `isLoading` is true. Apply to
    /// the amount's Text; see `LoadingWave`.
    func loadingWave(isLoading: Bool, label: String = "amount") -> some View {
        modifier(LoadingWave(isLoading: isLoading, label: label))
    }
}
