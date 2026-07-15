//
//  ExitStatus.swift
//  ArkéUI
//
//  Pure value type describing the current status of a unilateral exit.
//  Mapping from Bark's `ExitVtxo` lives app-side in `ExitStatus+Bark.swift`,
//  keeping this type free of Bark so it stays previewable.
//

import Foundation

/// Represents the current status of a unilateral exit
public struct ExitStatus: Hashable, Sendable {
    public let isClaimed: Bool
    public let isClaimable: Bool
    public let isClaimInProgress: Bool
    public let stateDisplayName: String

    public init(isClaimed: Bool, isClaimable: Bool, isClaimInProgress: Bool = false, stateDisplayName: String) {
        self.isClaimed = isClaimed
        self.isClaimable = isClaimable
        self.isClaimInProgress = isClaimInProgress
        self.stateDisplayName = stateDisplayName
    }
}
