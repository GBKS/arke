//
//  RefreshModalErrorView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI

public struct LargeErrorView: View {
    /// The title shown above the error message.
    ///
    /// - Note: A `LocalizedStringKey` is resolved against the caller's bundle
    ///   context (effectively `Bundle.main`), not this package's `.module`
    ///   bundle. Pass keys defined in the app's catalog, or an already-localized
    ///   value. Package-defined string keys will not resolve here — if that's
    ///   needed, change this API to accept a resolved `Text`/`String` plus a bundle.
    let title: LocalizedStringKey
    let errorMessage: String
    let image: String?
    let systemImage: String?
    let systemImageColor: Color?
    let data: [(key: String, value: String)]?
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    public init(
        title: LocalizedStringKey,
        errorMessage: String,
        image: String? = nil,
        systemImage: String? = nil,
        systemImageColor: Color? = nil,
        data: [(key: String, value: String)]? = nil,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.errorMessage = errorMessage
        self.image = image
        self.systemImage = systemImage
        self.systemImageColor = systemImageColor
        self.data = data
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 20) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundStyle(systemImageColor ?? Color.Arke.gold)
                        .accessibilityHidden(true)
                } else if let image = image {
                    Image(image, bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(10)
                        .accessibilityHidden(true)
                }
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let data = data, !data.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.key)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(item.value)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 40)

            VStack(spacing: 20) {
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Text("button_cancel", bundle: .module)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                }
                
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Text("button_retry", bundle: .module)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                }
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 30)
    }
}

#Preview("System image") {
    LargeErrorView(
        title: "Refresh failed",
        errorMessage: "Network connection failed. Please check your internet connection and try again.",
        image: nil,
        systemImage: "exclamationmark.triangle.fill",
        systemImageColor: nil,
        onRetry: {
            print("Retry tapped")
        },
        onDismiss: {
            print("Dismiss tapped")
        }
    )
}

#Preview("Custom image") {
    LargeErrorView(
        title: "Refresh failed",
        errorMessage: "Network connection failed. Please check your internet connection and try again.",
        image: "error",
        systemImage: nil,
        systemImageColor: nil,
        onRetry: {
            print("Retry tapped")
        },
        onDismiss: {
            print("Dismiss tapped")
        }
    )
}

#Preview("With data") {
    LargeErrorView(
        title: "Transaction failed",
        errorMessage: "Unable to complete the transaction. Please review the details below.",
        image: nil,
        systemImage: "exclamationmark.triangle.fill",
        systemImageColor: .red,
        data: [
            (key: "Error Code", value: "ERR_500"),
            (key: "Timestamp", value: "2026-05-04 14:32:15"),
            (key: "Transaction ID", value: "a3f2b9c1")
        ],
        onRetry: {
            print("Retry tapped")
        },
        onDismiss: {
            print("Dismiss tapped")
        }
    )
}
