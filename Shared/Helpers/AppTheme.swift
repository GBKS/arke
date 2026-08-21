//
//  AppTheme.swift
//  Arké
//
//  A visual theme bundling the background images used across the app:
//  the balance card (activity screen), the tilt-to-share overlay, the
//  receive keypad texture, the receive QR sheet, and the balance view —
//  plus the card's text color. Full color palettes may follow.
//

import SwiftUI
import ArkeUI

enum AppTheme: String, CaseIterable, Identifiable {
    case classic
    case ginkgo
    case purpleLines
    case floralPattern

    static let defaultTheme: AppTheme = .classic

    var id: String { rawValue }

    /// The active theme read from UserDefaults. For non-View code paths;
    /// views should use @AppStorage(UserDefaults.appThemeKey) so they update live.
    static var current: AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: UserDefaults.appThemeKey),
              let theme = AppTheme(rawValue: raw) else {
            return defaultTheme
        }
        return theme
    }

    var displayName: String {
        switch self {
        case .classic:
            return String(localized: "theme_name_classic", defaultValue: "Classic")
        case .ginkgo:
            return String(localized: "theme_name_ginkgo", defaultValue: "Ginkgo")
        case .purpleLines:
            return String(localized: "theme_name_purple_lines", defaultValue: "Purple lines")
        case .floralPattern:
            return String(localized: "theme_name_floral_pattern", defaultValue: "Floral pattern")
        }
    }

    /// Image representing this theme in the settings grid.
    var thumbnailImageName: String { images.card }

    /// Color of the "Arké" wordmark on the hidden balance card.
    var textColor: Color {
        textColorHex.flatMap { Color(hex: $0) } ?? .Arke.gold
    }

    /// Per-theme hex override for textColor; nil falls back to Arké gold.
    private var textColorHex: String? {
        switch self {
        case .classic:
            return nil
        case .floralPattern:
            return "FFFFCD"
        case .ginkgo:
            return "F3F4F2"
        case .purpleLines:
            return "FBE8EF"
        }
    }

    /// Asset catalog names for every themed surface.
    var images: ThemeImages {
        switch self {
        case .classic:
            return ThemeImages(
                card: "card",
                cardMask: "card-mask",
                hiddenCard: "tuscan-villa",
                hiddenCardMask: nil,
                tiltBackground: "tuscan-villa-portrait",
                keypadTexture: "black-marble",
                qrBackground: "card-big",
                balanceBackground: "card-big"
            )
        case .ginkgo:
            return ThemeImages(
                card: "ginkgo-card",
                cardMask: "ginkgo-card-mask",
                hiddenCard: "ginkgo-card-hidden",
                hiddenCardMask: "ginkgo-card-hidden-mask",
                tiltBackground: "ginkgo-tilt-back",
                keypadTexture: "ginkgo-keypad",
                qrBackground: "ginkgo-invoice-back",
                balanceBackground: "ginkgo-balance-back"
            )
        case .purpleLines:
            return ThemeImages(
                card: "purple-lines-card",
                cardMask: "purple-lines-card-mask",
                hiddenCard: "purple-lines-card-hidden",
                hiddenCardMask: "purple-lines-card-hidden-mask",
                tiltBackground: "purple-lines-tilt-back",
                keypadTexture: "purple-lines-keypad",
                qrBackground: "purple-lines-invoice-back",
                balanceBackground: "purple-lines-balance-back"
            )
        case .floralPattern:
            return ThemeImages(
                card: "floral-pattern-card",
                cardMask: "floral-pattern-card-mask",
                hiddenCard: "floral-pattern-card-hidden",
                hiddenCardMask: "floral-pattern-card-hidden-mask",
                tiltBackground: "floral-pattern-tilt-back",
                keypadTexture: "floral-pattern-keypad",
                qrBackground: "floral-pattern-invoice-back",
                balanceBackground: "floral-pattern-balance-back"
            )
        }
    }
}

struct ThemeImages {
    /// Balance card on the activity screen (also the HoloCard base image).
    let card: String
    /// Mask driving the holographic effect on the balance card.
    let cardMask: String
    /// Balance card while the balance is hidden (privacy mode).
    let hiddenCard: String
    /// Holo mask for the hidden card; nil renders it flat (no holo effect).
    let hiddenCardMask: String?
    /// Full-screen background of the tilt-to-share overlay.
    let tiltBackground: String
    /// Texture behind the numeric keypad in the receive flow.
    let keypadTexture: String
    /// Full-screen background behind the receive QR (invoice sheet).
    let qrBackground: String
    /// Full-screen background of the balance view.
    let balanceBackground: String
}
