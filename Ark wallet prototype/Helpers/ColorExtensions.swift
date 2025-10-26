//
//  ColorExtensions.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

extension Color {
    init(r: Double, g: Double, b: Double) {
        self.init(red: r/255, green: g/255, blue: b/255)
    }
    
    static let gold = Color(r: 255, g: 215, b: 0)
    static let arkeGold = Color(r: 248, g: 209, b: 117)
    static let arkeDark = Color(r: 23, g: 11, b: 0)
}