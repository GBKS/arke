//
//  ThemeSettingView.swift
//  Arké
//
//  Settings sub-page with a two-column grid of themes. The selected theme
//  drives the background images used across the app (see AppTheme).
//

import SwiftUI
import ArkeUI

struct ThemeSettingView: View {
    @AppStorage(UserDefaults.appThemeKey)
    private var selectedThemeRawValue: String = AppTheme.defaultTheme.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .defaultTheme
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.settingsTheme)
                    .font(.system(.title, design: .serif))

                Text(String(localized: "settings_theme_help", defaultValue: "Choose the look of the balance card and backgrounds throughout the app."))
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeGridCell(
                            theme: theme,
                            isSelected: theme == selectedTheme,
                            onSelect: { selectedThemeRawValue = theme.rawValue }
                        )
                    }
                }
            }
            .padding()
            #if os(macOS)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            #endif
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

private struct ThemeGridCell: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Color.clear
                .aspectRatio(3/2, contentMode: .fit)
                .overlay {
                    Image(theme.thumbnailImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.Arke.gold : Color.secondary.opacity(0.2),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.Arke.gold)
                            .padding(8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ThemeSettingView()
}
