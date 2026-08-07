//
//  TransactionCardStackView_iOS.swift
//  Arké
//
//  Created by Christoph on 7/27/26.
//

import SwiftUI
import SwiftData
import UIKit
import ArkeUI

/// Prototype: card-stack overlay for browsing transactions without navigation.
/// Swipe up commits to the next (older) transaction, swipe down brings back the
/// previous (newer) one. Swiping down on the first card dismisses the overlay,
/// as do the close button and a tap on the dimmed background.
///
/// The presenting fullScreenCover has its transition disabled; entrance and
/// exit are choreographed here so the backdrop and close button fade while
/// only the cards slide in from below.
struct TransactionCardStackView_iOS: View {
    let transactions: [PersistentTransaction]

    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var walletManager

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var backdropVisible = false
    @State private var cardsVisible = false
    @State private var detailTransaction: TransactionModel?
    @State private var showDetailSheet = false
    // Keeps the previous card rendered while it animates back offscreen after
    // a released (uncommitted) downward drag — the dragOffset state value
    // jumps to 0 immediately, which would otherwise remove it mid-screen
    @State private var returningPreviousCard = false
    // Touch-down state for the press feedback on the top card; GestureState
    // resets automatically on release or cancellation
    @GestureState private var isCardPressed = false
    // While the top card's note field is focused, the keyboard-shortened top
    // card would sit smaller than the full-height peeks behind it, so those
    // fade out for the duration of editing
    @State private var isEditingNote = false

    // Drag distance over which cards behind fully promote to their next slot
    private let promoteDistance: CGFloat = 300
    // Drag distance that commits an advance/return on release
    private let commitThreshold: CGFloat = 120
    // Vertical offset between stacked cards
    private let peekOffset: CGFloat = 18
    // Scale reduction per depth level
    private let depthScale: CGFloat = 0.05
    // Top card scale while a touch is down — kept above the first peek's 0.95
    // so the press reads as tactile rather than the card receding into the stack
    private let pressedScale: CGFloat = 0.98

    // Converted models for the rendered window, keyed by index. Conversion
    // reads SwiftData properties, so doing it in the card builder would redo
    // that work on every drag frame; instead the cache is rebuilt only when
    // the index moves or the wallet data changes.
    @State private var modelCache: [Int: TransactionModel]

    init(transactions: [PersistentTransaction], initialIndex: Int) {
        self.transactions = transactions
        let clampedIndex = min(max(initialIndex, 0), max(transactions.count - 1, 0))
        self._currentIndex = State(initialValue: clampedIndex)
        self._modelCache = State(initialValue: Self.buildModelCache(around: clampedIndex, from: transactions))
    }

    private static func buildModelCache(around index: Int, from transactions: [PersistentTransaction]) -> [Int: TransactionModel] {
        var cache: [Int: TransactionModel] = [:]
        for i in (index - 1)...(index + 3) where transactions.indices.contains(i) {
            cache[i] = TransactionModel(from: transactions[i])
        }
        return cache
    }

    private func model(at index: Int) -> TransactionModel {
        modelCache[index] ?? TransactionModel(from: transactions[index])
    }

    private var hasNext: Bool {
        currentIndex + 1 < transactions.count
    }

    private var hasPrevious: Bool {
        currentIndex > 0
    }

    // Rendered window around the current card: the top card, two visible
    // peeks, and one extra card that fades in during promotion so it doesn't
    // pop when the stack advances. The previous card is only rendered while a
    // downward drag/return is in progress — at rest it sits offscreen above,
    // and rendering it there would make it ride down across the screen when
    // the whole stack slides out on dismissal.
    private var visibleIndices: [Int] {
        let showPrevious = dragOffset > 0 || returningPreviousCard
        let lowerBound = showPrevious ? currentIndex - 1 : currentIndex
        return (lowerBound...(currentIndex + 3)).filter { transactions.indices.contains($0) }
    }

    // 0...1 while dragging up: how far cards behind have moved toward their next slot
    private var promotion: CGFloat {
        guard dragOffset < 0 else { return 0 }
        return min(1, -dragOffset / promoteDistance)
    }

    // 0...1 while dragging down with a previous card incoming
    private var demotion: CGFloat {
        guard dragOffset > 0, hasPrevious else { return 0 }
        return min(1, dragOffset / promoteDistance)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Blurred, dimmed backdrop; tap to dismiss. SwiftUI materials
                // can't sample through the cover's presentation boundary (they
                // render solid), so a UIKit visual effect view does the blur
                BackdropBlurView(isActive: backdropVisible)
                    .overlay(Color.systemBackground.opacity(backdropVisible ? 0.15 : 0))
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissOverlay()
                    }

                if transactions.isEmpty {
                    Color.clear
                        .onAppear { dismiss() }
                } else {
                    cardStack(in: geo)
                        .offset(y: cardsVisible ? 0 : geo.size.height)
                }

                // Close button
                VStack {
                    HStack {
                        Button {
                            dismissOverlay()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .tint(Color.Arke.gold)
                        .accessibilityLabel("button_close")

                        Spacer()
                        
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .opacity(backdropVisible ? 1 : 0)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: currentIndex)
        .onChange(of: currentIndex) { _, newIndex in
            modelCache = Self.buildModelCache(around: newIndex, from: transactions)
        }
        .onChange(of: walletManager.dataVersion) {
            modelCache = Self.buildModelCache(around: currentIndex, from: transactions)
        }
        .onAppear {
            // The presenting side disabled UIView animations to skip the
            // cover's slide-up; restore them before the entrance choreography
            UIView.setAnimationsEnabled(true)
            withAnimation(.easeOut(duration: 0.25)) {
                backdropVisible = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                cardsVisible = true
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            if let detailTransaction {
                TransactionReceiptSheet(transaction: detailTransaction)
            }
        }
    }

    /// Reverse of the entrance: cards slide out below while the backdrop and
    /// close button fade, then the cover is removed without its own transition.
    private func dismissOverlay() {
        hideKeyboard()
        withAnimation(.easeIn(duration: 0.2)) {
            backdropVisible = false
        }
        withAnimation(.spring(duration: 0.35, bounce: 0)) {
            cardsVisible = false
        } completion: {
            // Skip the cover's slide-down as well; the presenting side
            // re-enables UIView animations in onDismiss
            UIView.setAnimationsEnabled(false)
            dismiss()
        }
    }

    // MARK: - Card Stack

    private func cardStack(in geo: GeometryProxy) -> some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { index in
                let depth = index - currentIndex

                TransactionSwipeCard(
                    transaction: model(at: index),
                    onShowDetails: {
                        detailTransaction = model(at: index)
                        showDetailSheet = true
                    },
                    onNoteFocusChange: { focused in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isEditingNote = focused
                        }
                    }
                )
                .equatable()
                .frame(
                    width: max(geo.size.width - 48, 0),
                    height: min(geo.size.height * 0.72, 640)
                )
                // Depth cues in place of a drop shadow: cards behind darken
                // and get a faint rim, both easing off as a card promotes
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.black.opacity(cardDim(depth: depth)))
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(cardRim(depth: depth)), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                }
                // Press feedback: the top card dips slightly on touch-down,
                // filling the dead zone before the drag's minimumDistance is
                // reached. Scoped by the .animation's value so nothing else
                // picks up this transition.
                .scaleEffect(depth == 0 && isCardPressed ? pressedScale : 1, anchor: .bottom)
                .animation(
                    isCardPressed
                        ? .easeOut(duration: 0.15)
                        : .spring(duration: 0.3, bounce: 0.3),
                    value: isCardPressed
                )
                // Anchoring at the bottom keeps the full peekOffset visible
                // below the card in front instead of losing most of it to
                // center-anchored shrinking
                .scaleEffect(cardScale(depth: depth), anchor: .bottom)
                .offset(y: cardOffset(depth: depth, height: geo.size.height))
                .opacity(isEditingNote && depth != 0 ? 0 : cardOpacity(depth: depth))
                .zIndex(Double(-depth))
                .allowsHitTesting(depth == 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 56)
        .gesture(dragGesture(height: geo.size.height))
        .simultaneousGesture(pressGesture)
    }

    private func effectiveDepth(_ depth: Int) -> CGFloat {
        CGFloat(depth) - promotion + demotion
    }

    private func cardOffset(depth: Int, height: CGFloat) -> CGFloat {
        if depth == -1 {
            // Previous card waits offscreen above and follows a downward drag in
            return -height - 60 + max(0, dragOffset)
        }
        if depth == 0 {
            if dragOffset < 0 {
                // Top card follows an upward drag directly
                return dragOffset
            }
            if !hasPrevious {
                // No previous card: downward drag pulls the whole card (dismiss gesture)
                return dragOffset
            }
            // Previous card incoming: top card settles back into the stack
            return effectiveDepth(0) * peekOffset
        }
        return effectiveDepth(depth) * peekOffset
    }

    private func cardScale(depth: Int) -> CGFloat {
        if depth <= 0 && demotion == 0 {
            return 1
        }
        return 1 - max(0, effectiveDepth(depth)) * depthScale
    }

    private func cardOpacity(depth: Int) -> Double {
        guard depth > 0 else { return 1 }
        // Fade out beyond the second peek so the extra card eases in during promotion
        let d = effectiveDepth(depth)
        return Double(min(1, max(0, (2.7 - d) / 0.7)))
    }

    // Black scrim per depth level — provides the boundary contrast a drop
    // shadow would, at the cost of a flat fill
    private func cardDim(depth: Int) -> Double {
        let d = max(0, effectiveDepth(depth))
        return Double(min(0.45, d * 0.15))
    }

    // Faint rim on cards behind, separating their edges from the card in
    // front and the backdrop; gone by the time a card reaches the top, where
    // the header's own edge highlight takes over
    private func cardRim(depth: Int) -> Double {
        Double(min(0.2, max(0, effectiveDepth(depth)) * 0.2))
    }

    // MARK: - Gesture

    // The main drag gesture only fires after minimumDistance, so touch-down
    // needs its own zero-distance gesture running simultaneously
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isCardPressed) { _, state, _ in
                state = true
            }
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                if dragOffset == 0 {
                    hideKeyboard()
                }
                let translation = value.translation.height
                if translation < 0 {
                    // Rubber-band when there is no next card
                    dragOffset = hasNext ? translation : translation * 0.25
                } else {
                    dragOffset = translation
                }
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height

                if translation < 0 {
                    if hasNext && (translation < -commitThreshold || predicted < -commitThreshold * 2.5) {
                        advance(height: height)
                    } else {
                        snapBack()
                    }
                } else {
                    if hasPrevious && (translation > commitThreshold || predicted > commitThreshold * 2.5) {
                        goBack(height: height)
                    } else if !hasPrevious && (translation > 180 || predicted > 400) {
                        dismissOverlay()
                    } else {
                        snapBack()
                    }
                }
            }
    }

    private func advance(height: CGFloat) {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            dragOffset = -(height + 100)
        } completion: {
            // At full promotion the cards behind already sit in their new
            // slots, so swapping the index and resetting the offset is seamless
            currentIndex += 1
            dragOffset = 0
        }
    }

    private func goBack(height: CGFloat) {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            dragOffset = height + 60
        } completion: {
            currentIndex -= 1
            dragOffset = 0
        }
    }

    private func snapBack() {
        if dragOffset > 0 && hasPrevious {
            returningPreviousCard = true
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                dragOffset = 0
            } completion: {
                returningPreviousCard = false
            }
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                dragOffset = 0
            }
        }
    }
}

/// Blurs the window content beneath it — including the presenting screen
/// behind a clear fullScreenCover, which SwiftUI materials can't reach.
/// Toggling isActive animates the blur radius in and out.
private struct BackdropBlurView: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: nil)
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        let hasBlur = view.effect != nil
        guard isActive != hasBlur else { return }
        UIView.animate(withDuration: 0.25) {
            view.effect = isActive ? UIBlurEffect(style: .systemThinMaterial) : nil
        }
    }
}

