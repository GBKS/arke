//
//  ColorExtensions.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

// MARK: - Color Extensions

extension Color {
    // MARK: - Convenience Initializers
    
    /// Initialize Color with RGB values from 0-255 range
    init(r: Double, g: Double, b: Double, opacity: Double = 1.0) {
        self.init(red: r/255.0, green: g/255.0, blue: b/255.0, opacity: opacity)
    }
    
    // MARK: - Custom Colors
    
    static let gold = Color(r: 255, g: 215, b: 0)
    static let arkeGold = Color(r: 248, g: 209, b: 117)
    static let arkeDark = Color(r: 23, g: 11, b: 0)
}

// MARK: - Hex Color Support

extension Color {
    /// Initialize Color from hex string
    /// Supports 3, 6, and 8 character hex strings (RGB, RRGGBB, AARRGGBB)
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    /// Convert Color to hex string representation
    func toHex() -> String {
        let uic = NSColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

// MARK: - System Color Extensions

extension Color {
    /// Secondary label color that adapts to the system appearance
    static var secondary: Color {
        Color(NSColor.secondaryLabelColor)
    }
}
