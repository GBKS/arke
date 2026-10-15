//
//  DeletePhraseConfirmationView.swift
//  Arke
//
//  The step between the Delete wallet screen and the slider sheet on a full
//  wipe: two words of the recovery phrase, asked by position. Proves a
//  written copy exists before the only seed copies are destroyed. Plan:
//  Docs/Features/Wallet_Deletion_Phrase_Confirmation.md.
//
//  The screen owns only the challenge. The slider sheet, the deletion call
//  and the abort handling stay on the Delete wallet screen, which this view
//  tells `onPassed` when the words match.
//

import SwiftUI
import ArkeUI

struct DeletePhraseConfirmationView: View {
    @Environment(WalletManager.self) private var walletManager

    /// The words matched (or there is no phrase left to check). The caller
    /// presents the slider sheet.
    let onPassed: () -> Void

    private enum LoadState: Equatable {
        case loading
        case ready
        /// The keychain holds no phrase on this device (definitive
        /// `.notFound`): a wiped seed, or a secondary whose iCloud Keychain
        /// never delivered it. Either way this device has nothing to check
        /// and nothing its own wipe could destroy, and blocking here would
        /// make the wallet undeletable.
        case missing
        /// Any other failure. Fails closed: the user can retry, not proceed.
        case unreadable(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var challenge: PhraseConfirmation.Challenge?
    @State private var answers = Array(repeating: "", count: PhraseConfirmation.wordCount)
    @State private var showMismatch = false
    /// Counts refusals so the error haptic fires on every one, not only
    /// the first
    @State private var mismatchCount = 0
    @FocusState private var focusedField: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "settings_delete_phrase_title", defaultValue: "Confirm your recovery phrase"))
                        .font(.system(.title, design: .serif))

                    // The previous screen explained the deletion; this one
                    // only says what to do here
                    Text(bodyText)
                        .font(.title3)
                        .lineSpacing(6)
                        .foregroundColor(.secondary)
                }

                switch loadState {
                case .loading:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "status_loading_recovery_phrase", defaultValue: "Loading recovery phrase..."))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                case .ready:
                    if let challenge {
                        wordFields(for: challenge)
                    }
                case .missing:
                    Text(String(localized: "settings_delete_phrase_missing", defaultValue: "No recovery phrase is stored on this device, so there is nothing to confirm."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                case .unreadable(let message):
                    ErrorBox(
                        errorMessage: String(localized: "settings_delete_phrase_unreadable", defaultValue: "Your recovery phrase couldn't be read right now, so the deletion can't continue. Try again in a moment.") + "\n" + message,
                        onRetry: { Task { await loadChallenge() } }
                    )
                }

                Button {
                    continueTapped()
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Color.Arke.gold)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.2), value: canContinue)
                .padding(.top, 15)
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .sensoryFeedback(.error, trigger: mismatchCount)
        .task {
            await loadChallenge()
        }
        .onDisappear {
            // The expected words leave with the screen
            challenge = nil
            answers = Array(repeating: "", count: PhraseConfirmation.wordCount)
            showMismatch = false
        }
    }

    /// One single-line field per asked position. Same input rules as the
    /// import screen's phrase field: no autocapitalization, no autocorrect,
    /// ASCII keyboard.
    private func wordFields(for challenge: PhraseConfirmation.Challenge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(challenge.positions.enumerated()), id: \.offset) { index, position in
                let label = String(format: String(localized: "settings_delete_phrase_word_label %lld", defaultValue: "Word %lld"), Int64(position))
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    // No placeholder: the label above already names the
                    // word, and a verbatim empty label keeps an empty key
                    // out of the catalog
                    TextField(text: $answers[index]) { Text(verbatim: "") }
                        .padding(12)
                        .background(Color.primary.opacity(0.05))
                        .font(.title3)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.Arke.gold.opacity(0.2), lineWidth: 1)
                        )
                        .focused($focusedField, equals: index)
                        .onChange(of: answers[index]) { _, _ in
                            showMismatch = false
                        }
                        .onSubmit {
                            if index + 1 < challenge.positions.count {
                                focusedField = index + 1
                            } else {
                                focusedField = nil
                                continueTapped()
                            }
                        }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(index + 1 < challenge.positions.count ? .next : .done)
                        #endif
                        .accessibilityLabel(label)
                }
            }

            // Sits with the fields, not as its own 25 pt-spaced block
            if showMismatch {
                Text(String(localized: "settings_delete_phrase_mismatch", defaultValue: "That doesn't match your recovery phrase."))
                    .font(.callout)
                    .foregroundColor(.Arke.red)
                    .padding(.top, -6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showMismatch)
        .onAppear {
            // Fields exist now; focusing earlier (in the load) is a no-op
            focusedField = 0
        }
    }

    /// Names the positions once they are known; neutral before that and
    /// when there is no phrase to check.
    private var bodyText: String {
        if case .ready = loadState, let challenge, challenge.positions.count == 2 {
            return String(format: String(localized: "settings_delete_phrase_body_positions %lld %lld", defaultValue: "Enter words %lld and %lld to confirm you have it written down."),
                          Int64(challenge.positions[0]), Int64(challenge.positions[1]))
        }
        return String(localized: "settings_delete_phrase_body", defaultValue: "Two words of your recovery phrase confirm you have it written down before it is removed.")
    }

    /// "Verify" when there are words to check (Christoph, 2026-10-15);
    /// "Continue" when the keychain holds no phrase and there is nothing to
    /// verify.
    private var buttonTitle: String {
        if case .missing = loadState {
            return String(localized: "button_continue", defaultValue: "Continue")
        }
        return String(localized: "button_verify", defaultValue: "Verify")
    }

    private var canContinue: Bool {
        switch loadState {
        case .ready:
            return answers.allSatisfy { !PhraseConfirmation.normalize($0).isEmpty }
        case .missing:
            return true
        case .loading, .unreadable:
            return false
        }
    }

    private func continueTapped() {
        guard canContinue else { return }

        switch loadState {
        case .missing:
            onPassed()
        case .ready:
            guard let challenge, challenge.matches(answers) else {
                // Refuse with a haptic and put the cursor back on the first
                // word; the typed words stay so one typo is easy to fix
                showMismatch = true
                mismatchCount += 1
                focusedField = 0
                return
            }
            focusedField = nil
            onPassed()
        case .loading, .unreadable:
            return
        }
    }

    /// Reads the phrase through the keychain path (no bark handle needed,
    /// so a read-only secondary on the override route is covered), builds
    /// the challenge and drops the full phrase. A read failure fails closed
    /// unless the keychain says definitively that there is no item.
    private func loadChallenge() async {
        loadState = .loading
        showMismatch = false

        do {
            let phrase = try await walletManager.getMnemonic()
            guard let built = PhraseConfirmation.challenge(from: phrase) else {
                loadState = .unreadable(String(localized: "error_recovery_phrase_too_short", defaultValue: "The stored recovery phrase is incomplete."))
                return
            }
            challenge = built
            loadState = .ready
        } catch {
            switch SecurityService.mnemonicKeychainStatus() {
            case .notFound:
                loadState = .missing
            case .found, .unavailable:
                loadState = .unreadable(error.localizedDescription)
            }
        }
    }
}
