//
//  FeeTierGroupTests.swift
//  ArkéTests
//
//  Tiers at the same rate are one choice; the fastest member names and
//  times the group; a single group means no choice at all.
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Fee tier groups")
struct FeeTierGroupTests {

    @Test("Three distinct rates stay three choices, fastest first")
    func distinctRatesStayDistinct() {
        let groups = FeeTierGroup.groups(from: OnchainFeeRates(fast: 50, medium: 20, slow: 5))
        #expect(groups.map(\.representative) == [.fast, .medium, .slow])
        #expect(groups.map(\.members) == [[.fast], [.medium], [.slow]])
    }

    @Test("A quiet mempool collapses to one choice named Fast")
    func quietMempoolIsOneChoice() {
        let groups = FeeTierGroup.groups(from: OnchainFeeRates(fast: 1, medium: 1, slow: 1))
        #expect(groups.count == 1)
        #expect(groups[0].representative == .fast)
        #expect(groups[0].members == [.fast, .medium, .slow])
        #expect(groups[0].rateSatPerVb == 1)
    }

    @Test("Medium and Slow at the same rate merge under Medium, Fast stays apart")
    func slowerTiersMergeUnderTheirFastest() {
        let groups = FeeTierGroup.groups(from: OnchainFeeRates(fast: 2, medium: 1, slow: 1))
        #expect(groups.map(\.representative) == [.fast, .medium])
        #expect(groups[1].members == [.medium, .slow])
    }

    @Test("A selected tier is found in its group, so the merged row shows as selected")
    func selectionMapsToGroup() {
        let rates = OnchainFeeRates(fast: 2, medium: 1, slow: 1)
        let group = FeeTierGroup.group(containing: .slow, in: rates)
        #expect(group?.representative == .medium)
        #expect(group?.contains(.slow) == true)
        #expect(group?.contains(.fast) == false)
    }

    @Test("Durations come from the block targets, one block-time source")
    func durationsDeriveFromTargets() {
        #expect(FeePriority.fast.confirmationTargetBlocks == 1)
        #expect(FeePriority.medium.confirmationTargetBlocks == 3)
        #expect(FeePriority.slow.confirmationTargetBlocks == 6)
        // Three different targets, three different labels, each starting with the tilde
        let labels = FeePriority.allCases.map(\.estimatedConfirmationTime)
        #expect(Set(labels).count == 3)
        #expect(labels.allSatisfy { $0.hasPrefix("~") })
    }
}
