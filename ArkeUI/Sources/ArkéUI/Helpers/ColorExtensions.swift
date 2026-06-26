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
    public init(r: Double, g: Double, b: Double, opacity: Double = 1.0) {
        self.init(red: r/255.0, green: g/255.0, blue: b/255.0, opacity: opacity)
    }
    
    // MARK: - Custom Colors - DEPRECATED

    //public static let gold = Color(r: 255, g: 215, b: 0) // Arke.gold
    //public static let arkeGold = Color(r: 248, g: 209, b: 117) // Arke.gold
    //public static let arkeDarker = Color(r: 192, g: 159, b: 88) // .Arke.gold2
    //public static let arkeDark = Color(r: 23, g: 11, b: 0) // .Arke.gold4
}

extension Color {
    public enum Arke {
        public static let gold = Color("ArkeGold", bundle: .module)
        public static let gold2 = Color("ArkeGold2", bundle: .module)
        public static let gold3 = Color("ArkeGold3", bundle: .module)
        public static let gold4 = Color("ArkeGold4", bundle: .module)
        public static let green = Color("ArkeGreen", bundle: .module)
        public static let blue = Color("ArkeBlue", bundle: .module)
        public static let orange = Color("ArkeOrange", bundle: .module)
        public static let red = Color("ArkeRed", bundle: .module)
        public static let yellow = Color("ArkeYellow", bundle: .module)
        public static let purple = Color("ArkePurple", bundle: .module)
        public static let teal = Color("ArkeTeal", bundle: .module)
        public static let pink = Color("ArkePink", bundle: .module)
        public static let indigo = Color("ArkeIndigo", bundle: .module)
    }
}

// MARK: - Hex Color Support

extension Color {
    /// Initialize Color from hex string
    /// Supports 3, 6, and 8 character hex strings (RGB, RRGGBB, AARRGGBB)
    public init?(hex: String) {
        // Filter to only valid hex characters (0-9, A-F, a-f)
        let hex = hex.filter { "0123456789ABCDEFabcdef".contains($0) }
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
    public func toHex() -> String {
        #if canImport(AppKit)
        let uic = NSColor(self)
        #elseif canImport(UIKit)
        let uic = UIColor(self)
        #endif
        
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
    public static var arkeSecondary: Color {
        #if canImport(AppKit)
        Color(NSColor.secondaryLabelColor)
        #elseif canImport(UIKit)
        Color(UIColor.secondaryLabel)
        #else
        Color.gray
        #endif
    }
    
    /// Separator color that adapts to the platform
    public static var arkeSeparatorColor: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }
}

extension Color {
    public static var systemBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

extension Color {
    #if os(macOS)
    public static var systemControlBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    public static var systemSeparator: Color {
        Color(NSColor.separatorColor)
    }
    #else
    public static var systemControlBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }
    
    public static var systemSeparator: Color {
        Color(UIColor.separator)
    }
    #endif
}
