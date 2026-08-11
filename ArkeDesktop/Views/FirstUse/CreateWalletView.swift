//
//  CreateWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//
//  macOS port of CreateWalletView_iOS: wallet creation runs in parallel with
//  a play-once video; the continue button appears when both are complete.
//

import SwiftUI
import ArkeUI
import Accessibility
import AVFoundation
import OSLog

struct CreateWalletView: View {
    // MARK: - Logging

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "CreateWalletView")

    // MARK: - Properties

    let isMainnet: Bool
    let onBack: () -> Void
    let onWalletCreated: () -> Void
    let walletManager: WalletManager

    @State private var walletCreationComplete = false
    @State private var walletCreationInProgress = false
    @State private var showGetStartedButton = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var videoComplete = false
    @State private var showImage = false
    @State private var hasNavigated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isGetStartedFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Left column - portrait video (plays once), then the wallet image
            ZStack {
                LoopingVideoPlayer(
                    videoName: "magic-wallet-creation",
                    videoExtension: "mp4",
                    videoGravity: .resizeAspectFill,
                    autoPlay: true,
                    showErrorIndicator: true,
                    loops: false,
                    onCompletion: {
                        videoComplete = true
                        // Fade in the image after video completes
                        if reduceMotion {
                            showImage = true
                        } else {
                            withAnimation(.easeIn(duration: 0.2)) {
                                showImage = true
                            }
                        }
                    }
                )

                if showImage {
                    Color.clear
                        .overlay(
                            Image("bitcoin-wallet")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)

            // Right column - creation progress, then the reveal
            VStack(spacing: 30) {
                Spacer()

                if showGetStartedButton {
                    // Get Started button
                    VStack(spacing: 30) {
                        Text("onboarding_wallet_awaits")
                            .font(.system(.title, design: .serif))
                            .foregroundStyle(Color.Arke.gold)
                            .accessibilityAddTraits(.isHeader)

                        Button {
                            guard !hasNavigated else { return }
                            hasNavigated = true
                            onWalletCreated()
                        } label: {
                            Text("onboarding_step_in")
                                .font(.system(.title2, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .tint(Color.Arke.gold)
                        .disabled(hasNavigated)
                        .accessibilityLabel("button_get_started")
                        .accessibilityHint(Text("accessibility_continue_new_wallet"))
                        .accessibilityFocused($isGetStartedFocused)
                    }
                    .accessibilityElement(children: .contain)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                } else if walletCreationInProgress && videoComplete {
                    // Show loading indicator if video finished but wallet creation still in progress
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.Arke.gold)
                            .scaleEffect(1.5)

                        Text("onboarding_creating_wallet")
                            .font(.system(.headline, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("onboarding_creating_wallet")
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .task {
            // Announce wallet creation start for VoiceOver users
            AccessibilityNotification.Announcement(String(localized: "accessibility_wallet_creation_started")).post()

            // Start wallet creation immediately in parallel with video playback
            Task {
                await startWalletCreation()
            }
        }
        .onChange(of: walletCreationComplete) { _, isComplete in
            // Show button when both video AND wallet creation are complete
            if isComplete && videoComplete {
                revealGetStartedButton()
            }
        }
        .onChange(of: videoComplete) { _, isComplete in
            // Show button when both video AND wallet creation are complete
            if isComplete && walletCreationComplete {
                revealGetStartedButton()
            }
        }
        .alert(Text("alert_wallet_creation_failed"), isPresented: $showingError) {
            Button("button_retry") {
                Task {
                    await startWalletCreation()
                }
            }
            Button("button_go_back", role: .cancel) {
                onBack()
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func revealGetStartedButton() {
        if reduceMotion {
            showGetStartedButton = true
            isGetStartedFocused = true
            AccessibilityNotification.Announcement(String(localized: "accessibility_wallet_ready")).post()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                showGetStartedButton = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isGetStartedFocused = true
                AccessibilityNotification.Announcement(String(localized: "accessibility_wallet_ready")).post()
            }
        }
    }

    @MainActor
    private func startWalletCreation() async {
        let overallStartTime = CFAbsoluteTimeGetCurrent()
        Self.logger.info("⏱️ [PROFILE] CreateWalletView: Starting wallet creation flow (parallel with video)")

        // Reset states
        walletCreationComplete = false
        walletCreationInProgress = true
        showGetStartedButton = false
        showingError = false

        // Ensure cancel button and loading indicator can appear
        defer {
            walletCreationInProgress = false
        }

        // Track retry attempts
        var retryCount = 0
        let maxRetries = 2

        while retryCount <= maxRetries {
            do {
                print("🔧 Wallet creation attempt \(retryCount + 1)/\(maxRetries + 1)")
                print("   Network: \(isMainnet ? "mainnet" : "signet")")

                // Add small delay before retry (not on first attempt)
                if retryCount > 0 {
                    print("   ⏳ Waiting before retry...")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }

                let attemptStartTime = CFAbsoluteTimeGetCurrent()

                // Select network configuration based on isMainnet flag
                let networkConfig = isMainnet ? NetworkConfig.mainnet : NetworkConfig.signet
                let result = try await walletManager.createWallet(
                    networkConfig: networkConfig
                )

                let attemptTime = CFAbsoluteTimeGetCurrent() - attemptStartTime
                Self.logger.info("⏱️ [PROFILE] Wallet creation attempt took \(String(format: "%.3f", attemptTime))s")
                Self.logger.info("✅ Wallet created on \(networkConfig.name): \(result)")

                let totalTime = CFAbsoluteTimeGetCurrent() - overallStartTime
                Self.logger.info("⏱️ [PROFILE] CreateWalletView: Total wallet creation took \(String(format: "%.3f", totalTime))s")

                walletCreationComplete = true
                break // Success - exit retry loop

            } catch {
                Self.logger.error("❌ Attempt \(retryCount + 1) failed: \(error.localizedDescription)")

                let errorString = error.localizedDescription

                // Categorize errors for better retry logic
                let isDatabaseError = errorString.contains("bark_properties") ||
                                     errorString.contains("database") ||
                                     errorString.contains("SQL")

                let isNetworkError = errorString.contains("network") ||
                                    errorString.contains("connection") ||
                                    errorString.contains("timeout") ||
                                    errorString.contains("timed out") ||
                                    errorString.contains("unreachable") ||
                                    errorString.contains("URLError")

                let isServerError = errorString.contains("server") ||
                                   errorString.contains("401") ||
                                   errorString.contains("403") ||
                                   errorString.contains("unauthorized") ||
                                   errorString.contains("forbidden") ||
                                   errorString.contains("access token") ||
                                   errorString.contains("authentication")

                // Retry on database or network errors, but not server auth errors
                let shouldRetry = (isDatabaseError || isNetworkError) && retryCount < maxRetries

                if shouldRetry {
                    if isDatabaseError {
                        print("💡 Database error detected, will retry after cleanup")
                    } else if isNetworkError {
                        print("💡 Network error detected, will retry")
                    }
                    retryCount += 1
                    continue // Retry
                } else {
                    // Non-retryable error or max retries reached
                    print("❌ Failed to create wallet: \(error)")

                    // Provide more helpful error messages
                    if isServerError {
                        errorMessage = String(localized: "error_ark_server_connection")
                    } else if isNetworkError && retryCount >= maxRetries {
                        errorMessage = String(localized: "error_network_multiple_attempts")
                    } else {
                        errorMessage = errorString
                    }

                    showingError = true
                    break // Exit retry loop
                }
            }
        }
    }
}
