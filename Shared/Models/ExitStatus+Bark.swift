//
//  ExitStatus+Bark.swift
//  Ark wallet prototype
//
//  The `ExitStatus` value type lives in the ArkéUI package as a pure,
//  previewable model. This file maps Bark's `ExitVtxo` into it at the app
//  boundary, keeping the model free of Bark/FFI (which breaks previews).
//

import Foundation
import Bark
import ArkeUI

extension ExitStatus {
    /// Map a Bark `ExitVtxo` into the pure `ExitStatus` value type.
    init(from exitVtxo: ExitVtxo) {
        self.init(
            isClaimed: exitVtxo.isClaimed,
            isClaimable: exitVtxo.isClaimable,
            stateDisplayName: exitVtxo.stateDisplayName
        )
    }
}
