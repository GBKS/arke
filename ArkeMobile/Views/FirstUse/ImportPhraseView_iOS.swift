//
//  ImportPhraseView_iOS.swift
//  Arké
//
//  First import step: the recovery phrase, typed into a numbered grid laid
//  out like the settings phrase display. Space or Return commits a word and
//  moves on, a prefix that identifies one list word completes on commit, the
//  keyboard bar suggests list words from two letters, the system paste button
//  sits in pill 1 while the grid is empty, and Continue opens only for a
//  phrase bark's own validator accepts. The import itself runs on the next
//  step (ImportBackupFileView_iOS).
//  Plan: Docs/Features/Import_Screen_Split.md §3.
//

import SwiftUI
import ArkeUI
import UIKit

struct ImportPhraseView_iOS: View {
    /// Server and chain chosen on the cover screen.
    let networkConfig: NetworkConfig
    /// Words typed earlier in this flow (coming back from the file step);
    /// empty on first entry.
    let initialWords: [String]
    let onBack: () -> Void
    /// Called with the validated words, in order.
    let onContinue: ([String]) -> Void

    private static let maxWordCount = 24

    /// Always 24 slots; `wordCount` says how many are shown, so flipping the
    /// switch back and forth loses nothing.
    @State private var words: [String] = Array(repeating: "", count: ImportPhraseView_iOS.maxWordCount)
    @State private var wordCount = 12
    @State private var isChecksumValid = false
    @State private var pasteMessage: String?
    /// Measured screen width; the keyboard bar sizes its single item to its
    /// content, so the chip strip is given an explicit width to keep Done at
    /// the trailing edge even when there are no chips.
    @State private var containerWidth: CGFloat = 0
    @FocusState private var focusedIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                    header

                    VStack(spacing: 8) {
                        Text(String(localized: "onboarding_import_phrase_title", defaultValue: "Recovery Phrase"))
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(Color.Arke.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)

                        Text(String(localized: "onboarding_import_phrase_body", defaultValue: "Enter your recovery phrase, one word per field, in order."))
                            .font(.system(.title2))
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Funds live per Ark server: a phrase used on Second restores
                        // as empty on another server, and bark cannot warn about it
                        if networkConfig.serverKind == .custom {
                            Text(String(
                                format: String(localized: "onboarding_restore_custom_server", defaultValue: "Connects to %@. Only funds on that Ark server are recovered."),
                                NetworkConfig.serverHost(networkConfig.arkServerURL) ?? networkConfig.name
                            ))
                            .font(.system(.body))
                            .foregroundStyle(Color.Arke.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(spacing: 12) {
                        wordGrid
                        statusLine
                        wordCountLink
                    }
                    .frame(maxWidth: 400)

                    Spacer(minLength: 10)

                    Button {
                        focusedIndex = nil
                        onContinue(Array(words.prefix(wordCount)))
                    } label: {
                        Text(String(localized: "button_continue", defaultValue: "Continue"))
                            .font(.system(.title2, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    .disabled(!canContinue)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, safeAreaInsets.top)
                .padding(.bottom, safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                // One item: the strip has a fixed width (screen minus Done and
                // the bar's own margins), so chips never run under Done and an
                // empty strip still pushes Done to the trailing edge
                HStack(spacing: 12) {
                    suggestionChips
                        .frame(width: max(0, containerWidth - 130), alignment: .leading)
                    Button {
                        focusedIndex = nil
                    } label: {
                        // The keyboard bar does not inherit the screen's dark
                        // scheme, so the default label came out black on the
                        // dark glass capsule
                        Text(L10n.buttonDone)
                            .foregroundStyle(.white)
                    }
                    .fixedSize()
                }
            }
        }
        .onAppear {
            if !initialWords.isEmpty {
                wordCount = initialWords.count == Self.maxWordCount ? Self.maxWordCount : 12
                for (index, word) in initialWords.prefix(Self.maxWordCount).enumerated() {
                    words[index] = word
                }
                updateChecksum()
            }
            // No automatic focus: the keyboard sliding up over a screen the
            // user has not read yet is too much (Christoph, 2026-11-13)
        }
        .onChange(of: wordCount) { _, _ in
            updateChecksum()
        }
        .onChange(of: focusedIndex) { _, _ in
            // The invalid mark is derived from focus, so VoiceOver and the
            // status line see a committed word as soon as focus leaves it
            updateChecksum()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .accessibilityLabel(L10n.buttonBack)

            Spacer()
        }
        .padding(.top, 10)
    }

    /// Twelve words is the default; the 24-word case is a small link under
    /// the grid rather than a control that competes with it.
    private var wordCountLink: some View {
        HStack {
            Button {
                wordCount = wordCount == 12 ? Self.maxWordCount : 12
            } label: {
                Text(wordCount == 12
                    ? String(localized: "import_phrase_switch_to_24", defaultValue: "Switch to 24 words")
                    : String(localized: "import_phrase_switch_to_12", defaultValue: "Switch to 12 words"))
                    .font(.callout)
                    .foregroundStyle(Color.Arke.gold)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// The system paste button: it enables itself only while the pasteboard
    /// holds text and never shows the paste-permission alert. Shown in pill 1
    /// while nothing has been typed, gone after the first word.
    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            handlePasted(strings.first ?? "")
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .tint(Color.Arke.gold)
        // The system button ignores controlSize here and renders 34 pt tall
        // in a 38 pt pill; scaling it leaves an even inset (hit area scales
        // with it, still about 27 pt)
        .scaleEffect(0.8, anchor: .trailing)
        .accessibilityHint(String(localized: "import_phrase_paste_hint", defaultValue: "Fills the grid with a recovery phrase from the clipboard"))
    }

    /// Two columns of numbered pills, the settings phrase display with a
    /// field in each pill.
    private var wordGrid: some View {
        let half = wordCount / 2
        return HStack(alignment: .top, spacing: 8) {
            wordColumn(0..<half)
            wordColumn(half..<wordCount)
        }
    }

    private func wordColumn(_ indices: Range<Int>) -> some View {
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { index in
                wordPill(index)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func wordPill(_ index: Int) -> some View {
        let invalid = isInvalid(index)
        let label = String(format: String(localized: "import_phrase_word_label %lld %lld", defaultValue: "Word %lld of %lld"), Int64(index + 1), Int64(wordCount))
        return HStack(spacing: 4) {
            Text("\(index + 1)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, alignment: .trailing)

            // No placeholder: the number names the slot, and a verbatim empty
            // label keeps an empty key out of the catalog
            TextField(text: $words[index]) { Text(verbatim: "") }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .submitLabel(index + 1 < wordCount ? .next : .done)
                .focused($focusedIndex, equals: index)
                .onChange(of: words[index]) { _, newValue in
                    handleChange(at: index, newValue)
                }
                .onSubmit {
                    commit(index)
                }
                .accessibilityLabel(label)
                .accessibilityValue(invalid
                    ? String(format: String(localized: "import_phrase_word_invalid_value %@", defaultValue: "%@, not in the recovery word list"), words[index])
                    : words[index])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.Arke.gold4)
        .clipShape(Capsule())
        // An overlay, not a row member: the system button is taller than the
        // text row and would push pill 1 out of line with the right column
        .overlay(alignment: .trailing) {
            if index == 0 && isGridEmpty {
                pasteButton
                    .padding(.trailing, 4)
            }
        }
        .overlay(
            Capsule().stroke(
                invalid ? Color.Arke.red.opacity(0.9)
                    : focusedIndex == index ? Color.Arke.gold.opacity(0.7)
                    : Color.Arke.gold.opacity(0.2),
                lineWidth: 1
            )
        )
        .animation(.easeInOut(duration: 0.15), value: invalid)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let text = statusText {
            Text(text)
                .font(.callout)
                .foregroundStyle(statusIsError ? Color.Arke.red : .white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Chips for the focused pill's prefix; nothing below two letters. Always
    /// a view, even when empty, so the strip keeps its width and Done stays
    /// at the trailing edge instead of centring in an empty bar.
    private var suggestionChips: some View {
        let typed = focusedIndex.map { BIP39WordSuggestions.normalize(words[$0]) } ?? ""
        let found = BIP39WordSuggestions.candidates(forPrefix: typed)
        // A chip that only repeats the complete word adds nothing; "act" keeps
        // its chips because action, actor, actress and actual still match
        let candidates = found == [typed] ? [] : found
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(candidates, id: \.self) { word in
                    Button(word) {
                        fill(word)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.Arke.gold)
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Derived state

    private var visibleWords: [String] {
        Array(words.prefix(wordCount))
    }

    private var isGridEmpty: Bool {
        words.allSatisfy { $0.isEmpty }
    }

    /// A committed word (focus elsewhere) that is not in the list. While the
    /// user is still typing in the pill nothing is marked.
    private func isInvalid(_ index: Int) -> Bool {
        let word = words[index]
        return !word.isEmpty && focusedIndex != index && !BIP39WordSuggestions.contains(word)
    }

    private var canContinue: Bool {
        let visible = visibleWords
        return visible.allSatisfy { !$0.isEmpty && BIP39WordSuggestions.contains($0) } && isChecksumValid
    }

    private var statusText: String? {
        if let pasteMessage {
            return pasteMessage
        }
        if let first = (0..<wordCount).first(where: isInvalid) {
            return String(format: String(localized: "import_phrase_word_not_in_list %lld", defaultValue: "Word %lld isn't in the recovery word list."), Int64(first + 1))
        }
        // No progress counter (Christoph, 2026-11-13): the numbered pills
        // already show how far along the phrase is
        let visible = visibleWords
        let complete = visible.allSatisfy { !$0.isEmpty && BIP39WordSuggestions.contains($0) }
        if complete && !isChecksumValid {
            // No word can be named: a checksum failure says only that the
            // phrase as a whole is not the one that was written down
            return String(localized: "import_phrase_checksum_failed", defaultValue: "Every word is in the list, but one is wrong or out of order. Check each word against your written phrase.")
        }
        return nil
    }

    private var statusIsError: Bool {
        if pasteMessage != nil { return true }
        if (0..<wordCount).contains(where: isInvalid) { return true }
        let visible = visibleWords
        return visible.allSatisfy { !$0.isEmpty && BIP39WordSuggestions.contains($0) } && !isChecksumValid
    }

    // MARK: - Editing

    /// Lowercases and strips anything that is not a letter; a trailing space
    /// commits the word; several words at once (a paste into the pill) are
    /// spread over the following pills.
    private func handleChange(at index: Int, _ newValue: String) {
        pasteMessage = nil
        let tokens = RecoveryPhraseInput.tokens(in: newValue)
        if tokens.count > 1 {
            distribute(tokens, from: index)
            return
        }
        let cleaned = tokens.first ?? ""
        let endsWithSeparator = newValue.last.map { !$0.isLetter } ?? false
        if endsWithSeparator && !cleaned.isEmpty {
            words[index] = BIP39WordSuggestions.uniqueCompletion(for: cleaned) ?? cleaned
            advance(from: index)
        } else if cleaned != newValue {
            words[index] = cleaned
        }
        updateChecksum()
    }

    /// Return key: same as a trailing space.
    private func commit(_ index: Int) {
        let word = words[index]
        if !word.isEmpty {
            words[index] = BIP39WordSuggestions.uniqueCompletion(for: word) ?? word
        }
        advance(from: index)
        updateChecksum()
    }

    /// A tapped suggestion chip.
    private func fill(_ word: String) {
        guard let index = focusedIndex else { return }
        words[index] = word
        advance(from: index)
        updateChecksum()
    }

    private func advance(from index: Int) {
        if index + 1 < wordCount {
            focusedIndex = index + 1
        } else {
            focusedIndex = nil
        }
    }

    /// Several words arrived in one pill. A whole phrase (12 or 24 words)
    /// is taken as the phrase wherever it landed; anything else fills the
    /// following pills up to the shown count.
    private func distribute(_ tokens: [String], from start: Int) {
        if RecoveryPhraseInput.supportedWordCounts.contains(tokens.count) {
            applyPhrase(tokens)
            return
        }
        var next = start
        for token in tokens where next < wordCount {
            words[next] = token
            next += 1
        }
        focusedIndex = (0..<wordCount).first { words[$0].isEmpty }
        updateChecksum()
    }

    private func handlePasted(_ text: String) {
        guard let pasted = RecoveryPhraseInput.words(fromPasted: text) else {
            pasteMessage = String(localized: "import_phrase_paste_not_a_phrase", defaultValue: "The clipboard doesn't hold a recovery phrase.")
            return
        }
        applyPhrase(pasted)
    }

    /// Replaces the grid with a complete 12- or 24-word phrase.
    private func applyPhrase(_ phrase: [String]) {
        wordCount = phrase.count
        for index in 0..<Self.maxWordCount {
            words[index] = index < phrase.count ? phrase[index] : ""
        }
        focusedIndex = nil
        pasteMessage = nil
        updateChecksum()
    }

    /// bark's validator runs only once every shown pill holds a list word;
    /// until then the answer is known without asking.
    private func updateChecksum() {
        let visible = visibleWords
        guard visible.allSatisfy({ !$0.isEmpty && BIP39WordSuggestions.contains($0) }) else {
            isChecksumValid = false
            return
        }
        isChecksumValid = RecoveryPhraseInput.isValidPhrase(words: visible)
    }
}
