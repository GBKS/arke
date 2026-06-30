//
//  TagModel+Persistence.swift
//  Ark wallet prototype
//
//  The `TagModel` value type itself now lives in the ArkéUI package as a pure,
//  previewable presentation model. This file holds the app-side bridging between
//  that value type and the SwiftData `PersistentTag` store, kept here so the
//  model stays free of SwiftData and remains previewable in isolation.
//

import Foundation
import ArkeUI

extension TagModel {
    /// Initialize from persistent tag
    init(from persistentTag: PersistentTag) {
        self.init(
            id: persistentTag.id,
            name: persistentTag.name,
            colorHex: persistentTag.colorHex,
            emoji: persistentTag.emoji,
            createdDate: persistentTag.createdDate,
            isSystemTag: persistentTag.isSystemTag
        )
    }

    /// Convert to persistent model
    func toPersistentTag() -> PersistentTag {
        return PersistentTag(
            id: self.id,
            name: self.name,
            colorHex: self.colorHex,
            emoji: self.emoji,
            createdDate: self.createdDate,
            isSystemTag: self.isSystemTag
        )
    }
}
