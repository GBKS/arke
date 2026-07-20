//
//  ForcedMoveUnderwayView.swift
//  Arké
//
//  Created by Christoph on 7/20/26.
//

import SwiftUI

/// Shown when every spendable VTXO is already part of an in-flight forced
/// move, so there is nothing new to start. Progress itself is tracked in the
/// activity view and its transaction details, not here.
public struct ForcedMoveUnderwayView<Media: View>: View {
    let onGoToActivity: (() -> Void)?
    let media: Media

    public init(
        onGoToActivity: (() -> Void)? = nil,
        @ViewBuilder media: () -> Media
    ) {
        self.onGoToActivity = onGoToActivity
        self.media = media()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            media
                .frame(maxWidth: .infinity, maxHeight: 300)
                .cornerRadius(25)
                .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text("forced_move_underway_title", bundle: .module)
                    .font(.system(.title, design: .serif))

                Text("forced_move_all_moving", bundle: .module)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            }

            if let onGoToActivity {
                Button(action: onGoToActivity) {
                    Text("button_view_activity", bundle: .module)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.Arke.gold4)
                        .padding(.horizontal, 4)
                }
                .tint(Color.Arke.gold)
                .buttonStyle(.glassProminent)
            }

            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("With Activity Link") {
    ScrollView {
        ForcedMoveUnderwayView(onGoToActivity: {}) {
            Image("exit")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .padding()
    }
}

#Preview("Without Activity Link") {
    ScrollView {
        ForcedMoveUnderwayView {
            Image("exit")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .padding()
    }
}
