//
//  PhraseExposureCover.swift
//  Arké
//
//  Created by Christoph on 10/28/26.
//

import SwiftUI

/// Covers recovery phrase content whenever someone other than the user may
/// be looking: the scene is not active (expected to render before UIKit
/// takes the app-switcher snapshot, which follows `sceneDidEnterBackground`;
/// assumed until checked on a device) or the screen is being
/// recorded, mirrored or remotely controlled. The covered view keeps its
/// state, so the phrase reappears as it was when the cover lifts
/// (DECIDED 2026-10-28, `Docs/Features/Recovery_Phrase_Exposure.md`).
///
/// Apply it to every view that renders the phrase, including sheet content:
/// a cover on the presenting view sits underneath a sheet. No effect on
/// macOS (desktop is parked).
struct PhraseExposureCover: ViewModifier {
    var cornerRadius: CGFloat

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    private var isCovered: Bool {
        scenePhase != .active || isSceneCaptured
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(isCovered)
            .overlay {
                if isCovered {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(uiColor: .systemGray6))
                        .overlay {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(String(localized: "recovery_phrase_covered", defaultValue: "Recovery phrase hidden"))
                }
            }
    }
    #else
    func body(content: Content) -> some View {
        content
    }
    #endif
}

extension View {
    /// See `PhraseExposureCover`.
    func phraseExposureCover(cornerRadius: CGFloat = 12) -> some View {
        modifier(PhraseExposureCover(cornerRadius: cornerRadius))
    }
}
