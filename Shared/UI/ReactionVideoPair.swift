//
//  ReactionVideoPair.swift
//  Arké
//
//  Created by Claude on 8/4/26.
//

import Foundation

/// A matching idle/thumbs-up video pair featuring the same character.
/// Modals pick one pair at random when they load so the character stays
/// consistent across their in-progress and success states.
struct ReactionVideoPair {
    let idle: String
    let thumbsUp: String

    static let all: [ReactionVideoPair] = [
        ReactionVideoPair(idle: "puppy-idle", thumbsUp: "puppy-thumbs-up"),
        ReactionVideoPair(idle: "xerxes", thumbsUp: "thumbs-up-animation"),
        ReactionVideoPair(idle: "nigerian-lady-idle-small", thumbsUp: "nigerian-lady-thumbs-up-small"),
        ReactionVideoPair(idle: "chilean-lad-idle-small", thumbsUp: "chilean-lad-thumbs-up-small"),
    ]

    static func random() -> ReactionVideoPair {
        all.randomElement()!
    }
}
