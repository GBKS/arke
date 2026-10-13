//
//  BalanceLoadIndicatorModel.swift
//  Arké
//
//  The balance card's "still loading" indicator decides four things, and
//  this type holds all four so they can be tested without a view: when the
//  indicator may start, whether the amount is in its quiet state, whether a
//  highlight sweep may run, and when a sweep is allowed to stop. The view
//  owns the clocks (arming delay, pass length, rest length) and reports the
//  boundaries here; this type owns the rules.
//
//  Rules (Open_Follow_Ups "Nothing on screen says the launch load is still
//  running", DECIDED 2026-10-12):
//  - Start only after the refresh has run for the arming delay, so a short
//    pull-to-refresh never flashes.
//  - Stop at the end of a pass, never mid-sweep. A refresh that ends during
//    the rest between passes settles immediately.
//  - Reduce Motion: quiet amount only, no sweep, settle immediately.
//

import Foundation

// `nonisolated`: a value type with no UI dependencies, mutated from the
// main actor by the card and constructed freely by tests.
nonisolated struct BalanceLoadIndicatorModel: Equatable {

    enum Phase: Equatable {
        /// Nothing running, amount at full strength.
        case idle
        /// A refresh with data on screen has started; waiting out the arming
        /// delay before showing anything.
        case arming
        /// Indicator showing. `inPass` is true while a sweep pass is drawn,
        /// false during the rest between passes.
        case active(inPass: Bool)
        /// The refresh ended mid-pass; the pass completes, then the card
        /// settles.
        case finishingPass
    }

    private(set) var phase: Phase = .idle

    /// Mirrors the accessibility setting. The view keeps it current.
    var reduceMotion: Bool

    init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    // MARK: - Outputs

    /// Amount at reduced opacity. True from arming-complete until settle.
    var isQuiet: Bool {
        switch phase {
        case .idle, .arming:
            return false
        case .active, .finishingPass:
            return true
        }
    }

    /// Whether the view should keep its sweep loop alive. Includes the
    /// finishing pass so the loop is not cancelled mid-sweep.
    var wantsSweepLoop: Bool {
        guard !reduceMotion else { return false }
        switch phase {
        case .idle, .arming:
            return false
        case .active, .finishingPass:
            return true
        }
    }

    /// Whether the loop may begin another pass right now. Only while the
    /// refresh is still running and no pass is in flight.
    var mayStartPass: Bool {
        !reduceMotion && phase == .active(inPass: false)
    }

    // MARK: - Events

    /// The combined "refresh running and a balance is on screen" signal.
    mutating func refreshingWithDataChanged(_ running: Bool) {
        if running {
            switch phase {
            case .idle:
                phase = .arming
            case .finishingPass:
                // A new refresh overlapped the settle: keep going; the pass
                // already in flight simply continues as an active pass.
                phase = .active(inPass: true)
            case .arming, .active:
                break
            }
        } else {
            switch phase {
            case .idle:
                break
            case .arming:
                // Ended before anything was shown: nothing to settle.
                phase = .idle
            case .active(let inPass):
                // Mid-pass finishes the pass; a rest settles at once. With
                // Reduce Motion there is never a pass to finish.
                phase = (inPass && !reduceMotion) ? .finishingPass : .idle
            case .finishingPass:
                break
            }
        }
    }

    /// The arming delay elapsed. Ignored unless still arming, so a late
    /// timer after a short refresh cannot start the indicator.
    mutating func armingDelayElapsed() {
        guard phase == .arming else { return }
        phase = .active(inPass: false)
    }

    /// The view started drawing a pass. Only meaningful while active.
    mutating func passStarted() {
        guard phase == .active(inPass: false) else { return }
        phase = .active(inPass: true)
    }

    /// The pass finished drawing. Settles if the refresh ended meanwhile.
    mutating func passEnded() {
        switch phase {
        case .active(inPass: true):
            phase = .active(inPass: false)
        case .finishingPass:
            phase = .idle
        case .idle, .arming, .active(inPass: false):
            break
        }
    }
}
