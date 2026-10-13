//
//  BalanceLoadIndicatorModelTests.swift
//  ArkéTests
//
//  The balance card's "still loading" indicator has four guardrails
//  (Open_Follow_Ups, DECIDED 2026-10-12): arm only after a delay, stop at
//  the end of a pass, settle at once during a rest, no sweep under Reduce
//  Motion. These test the guardrails, not the animation.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Balance Load Indicator Model Tests")
struct BalanceLoadIndicatorModelTests {

    /// A refresh that has armed and is drawing its first pass.
    private static func activeMidPass(reduceMotion: Bool = false) -> BalanceLoadIndicatorModel {
        var model = BalanceLoadIndicatorModel(reduceMotion: reduceMotion)
        model.refreshingWithDataChanged(true)
        model.armingDelayElapsed()
        model.passStarted()
        return model
    }

    @Test("A refresh shorter than the arming delay never shows anything, even if its timer fires late")
    func shortRefreshNeverFlashes() {
        var model = BalanceLoadIndicatorModel()
        model.refreshingWithDataChanged(true)
        #expect(!model.isQuiet)
        #expect(!model.wantsSweepLoop)

        model.refreshingWithDataChanged(false)
        // The 1 s timer the view started is still pending; its firing must
        // not resurrect the indicator.
        model.armingDelayElapsed()
        #expect(model.phase == .idle)
        #expect(!model.isQuiet)
    }

    @Test("After the arming delay the amount goes quiet and a pass may start")
    func armingDelayActivates() {
        var model = BalanceLoadIndicatorModel()
        model.refreshingWithDataChanged(true)
        model.armingDelayElapsed()
        #expect(model.isQuiet)
        #expect(model.wantsSweepLoop)
        #expect(model.mayStartPass)
    }

    @Test("A refresh that ends mid-pass finishes the pass, then settles")
    func refreshEndingMidPassFinishesPass() {
        var model = Self.activeMidPass()
        model.refreshingWithDataChanged(false)
        // Still quiet, loop still alive, but no further pass may begin.
        #expect(model.phase == .finishingPass)
        #expect(model.isQuiet)
        #expect(model.wantsSweepLoop)
        #expect(!model.mayStartPass)

        model.passEnded()
        #expect(model.phase == .idle)
        #expect(!model.isQuiet)
        #expect(!model.wantsSweepLoop)
    }

    @Test("A refresh that ends during the rest settles immediately")
    func refreshEndingDuringRestSettlesAtOnce() {
        var model = Self.activeMidPass()
        model.passEnded()
        #expect(model.phase == .active(inPass: false))

        model.refreshingWithDataChanged(false)
        #expect(model.phase == .idle)
        #expect(!model.isQuiet)
        #expect(!model.mayStartPass)
    }

    @Test("While the refresh runs, each finished pass allows the next")
    func passesRepeatWhileRefreshing() {
        var model = Self.activeMidPass()
        model.passEnded()
        #expect(model.mayStartPass)
        model.passStarted()
        #expect(model.phase == .active(inPass: true))
        #expect(!model.mayStartPass)
    }

    @Test("A new refresh overlapping the finishing pass keeps the indicator going")
    func newRefreshDuringFinishingPassContinues() {
        var model = Self.activeMidPass()
        model.refreshingWithDataChanged(false)
        model.refreshingWithDataChanged(true)
        #expect(model.phase == .active(inPass: true))
        model.passEnded()
        #expect(model.mayStartPass)
    }

    @Test("Reduce Motion: quiet amount only, no sweep, immediate settle")
    func reduceMotionIsStaticState() {
        var model = BalanceLoadIndicatorModel(reduceMotion: true)
        model.refreshingWithDataChanged(true)
        model.armingDelayElapsed()
        #expect(model.isQuiet)
        #expect(!model.wantsSweepLoop)
        #expect(!model.mayStartPass)

        model.refreshingWithDataChanged(false)
        #expect(model.phase == .idle)
        #expect(!model.isQuiet)
    }

    @Test("Reduce Motion switched on mid-pass: the loop stops and the end of refresh still settles")
    func reduceMotionToggledMidPassStillSettles() {
        var model = Self.activeMidPass()
        model.reduceMotion = true
        #expect(!model.wantsSweepLoop)
        #expect(model.isQuiet)

        // The view's cancelled loop reports the pass closed, then the refresh ends.
        model.passEnded()
        model.refreshingWithDataChanged(false)
        #expect(model.phase == .idle)
    }

    @Test("Pass events outside an active phase are ignored")
    func strayPassEventsAreIgnored() {
        var model = BalanceLoadIndicatorModel()
        model.passStarted()
        model.passEnded()
        #expect(model.phase == .idle)

        model.refreshingWithDataChanged(true)
        model.passStarted()
        #expect(model.phase == .arming)
    }
}
