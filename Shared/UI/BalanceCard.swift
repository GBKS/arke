//
//  BalanceCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI
import Combine

struct BalanceCard: View {
    @Environment(WalletManager.self) private var walletManager
    @AppStorage(BitcoinAmountFormat.userDefaultsKey) private var formatPreference: BitcoinAmountFormat = .defaultFormat
    @AppStorage(UserDefaults.appThemeKey) private var theme: AppTheme = .defaultTheme

    let totalBalance: TotalBalanceModel?
    @Binding var isHidden: Bool

    // "Still loading" indicator: the model holds the rules, the view holds
    // the clocks. See BalanceLoadIndicatorModel for the state machine.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadIndicator = BalanceLoadIndicatorModel()
    /// Position of the glyph-opacity trough during a pass, 0 to 1. Both ends
    /// render every glyph at full opacity, so 0 is also the resting value.
    @State private var sweepProgress: Double = 0

    /// Refresh must run this long before anything shows, so a short
    /// pull-to-refresh never flashes.
    private static let armingDelay: Duration = .seconds(1)
    /// Slow and continuous: a three-second pass with no rest reads as
    /// breathing. The short passes with rests tried first (1 s and 0.5 s
    /// with 2 s rests) felt hectic on the device (device looks 2026-10-13).
    private static let sweepPassSeconds: TimeInterval = 3
    private static let sweepRestDuration: Duration = .zero
    /// Reduce Motion only: with no wave, a static dim is the whole signal.
    private static let quietAmountOpacity = 0.75

    private var hiddenImageName: String {
        if isHidden {
            return theme.images.hiddenCard
        } else {
            return theme.images.card
        }
    }

    private var hiddenCardMaskName: String? {
        switch formatPreference {
        case .corn, .unicorn:
            return nil // easter-egg art has no holo mask
        default:
            return theme.images.hiddenCardMask
        }
    }
    
    var body: some View {
        ZStack {
            if isHidden {
                // Privacy mode - show "Arké" text centered with refresh tag in bottom-left
                ZStack(alignment: .bottomLeading) {
                    // Centered "Arké" text
                    Text(L10n.appName)
                        #if os(iOS)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        #else
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        #endif
                        .foregroundColor(theme.textColor)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Bottom-left aligned refresh tag
                    BalanceRefreshTag()
                        .padding(.bottom, 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal mode - show balance details
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "balance_your_balance", defaultValue: "Your Balance"))
                        #if os(iOS)
                        .font(.system(size: 24, weight: .semibold))
                        #else
                        .font(.system(size: 17, weight: .semibold))
                        #endif
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)

                    Spacer()
                    
                    if let totalBalance = totalBalance {
                        BalanceRefreshTag()
                        
                        // Amount and its fiat line sit tight together; the
                        // outer stack's spacing applies to the tag above
                        VStack(alignment: .leading, spacing: 0) {
                            Text(BitcoinFormatter.shared.formatAmount(totalBalance.grandTotalSat))
                                #if os(iOS)
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                #else
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                #endif
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                // The amount is what is stale, so the amount
                                // carries the "still loading" wave: a shallow
                                // per-glyph opacity dip travelling across the
                                // digits, no tint (works on every theme), no
                                // motion of the glyphs themselves. At rest the
                                // renderer draws the plain text.
                                .textRenderer(GlyphWaveTextRenderer(progress: sweepProgress))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                                .contentTransition(.numericText())
                                .animation(.smooth, value: totalBalance.grandTotalSat)
                                // Reduce Motion has no wave, so the quiet state
                                // is the signal there; otherwise the wave is
                                // the only one (DECIDED 2026-10-13, the 75 %
                                // baseline on top of the wave muddled both).
                                .opacity(reduceMotion && loadIndicator.isQuiet ? Self.quietAmountOpacity : 1)
                                .animation(.easeInOut(duration: 0.3), value: loadIndicator.isQuiet)

                            // Fiat is display only — hidden entirely when the
                            // rate is missing or a day old (Fiat_Rates.md §4)
                            FiatAmountText(sats: totalBalance.grandTotalSat)
                                #if os(iOS)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                #else
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                #endif
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                                .animation(.smooth, value: totalBalance.grandTotalSat)
                        }
                    } else {
                        // Empty space to maintain card height
                        Spacer()
                            .frame(height: 40) // Approximate height to match the text + tag
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .aspectRatio(3/2, contentMode: .fit)
        .background {
            if isHidden {
                // Privacy mode - holo when the theme provides a hidden mask (iOS),
                // flat image otherwise (easter eggs, maskless themes, macOS)
                #if os(iOS)
                if let maskName = hiddenCardMaskName {
                    HoloCard_iOS(cardImageName: hiddenImageName, maskImageName: maskName)
                } else {
                    flatHiddenBackground
                }
                #else
                flatHiddenBackground
                #endif
            } else {
                // Normal mode - use HoloCard on iOS, regular card image on macOS
                #if os(iOS)
                HoloCard_iOS(cardImageName: theme.images.card, maskImageName: theme.images.cardMask)
                #else
                RoundedRectangle(cornerRadius: 15)
                    .overlay {
                        Image(theme.images.card)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                #endif
            }
        }
        .cornerRadius(15)
        .onChange(of: reduceMotion, initial: true) { _, reduce in
            loadIndicator.reduceMotion = reduce
        }
        // `isRefreshingWithData` is "a refresh is running and an amount is
        // on the card". Every full `refresh()` sets it: the launch load,
        // pull-to-refresh, and pushes routed through `refresh()`. Partial
        // refreshes (`refreshBalances`, `refreshAfterVTXOChange`) never set
        // `isRefreshing` and are deliberately not indicated.
        .onChange(of: walletManager.isRefreshingWithData, initial: true) { _, running in
            loadIndicator.refreshingWithDataChanged(running)
        }
        .task(id: loadIndicator.phase == .arming) {
            guard loadIndicator.phase == .arming else { return }
            try? await Task.sleep(for: Self.armingDelay)
            guard !Task.isCancelled else { return }
            loadIndicator.armingDelayElapsed()
        }
        .task(id: loadIndicator.wantsSweepLoop) {
            guard loadIndicator.wantsSweepLoop else { return }
            await runSweepLoop()
        }
    }

    /// Pass, rest, repeat, for as long as the model allows another pass. The
    /// model decides whether a refresh that ended mid-pass finishes the pass
    /// (it does) or whether one that ended during the rest starts another
    /// (it does not). Cancellation, e.g. the card leaving the screen, resets
    /// the wave and closes any pass so the model cannot stay in `inPass`.
    private func runSweepLoop() async {
        defer {
            resetSweepWithoutAnimation()
            loadIndicator.passEnded()
        }
        while !Task.isCancelled && loadIndicator.mayStartPass {
            loadIndicator.passStarted()
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

    private var flatHiddenBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .overlay {
                Image(hiddenImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}
