//
//  GlyphWaveTextRenderer.swift
//  Arké
//
//  A "still loading" wave for text that is already white on busy art: each
//  glyph dips in opacity as a soft trough travels across the line from the
//  leading to the trailing edge. No tint, so it works on every theme; no
//  motion, so the glyphs stay put. The Text stays one view, so kerning,
//  localisation and VoiceOver are untouched.
//
//  Purely presentational: the caller animates `progress` from 0 to 1 for
//  one pass. At 0 and at 1 the trough is entirely off the text and every
//  glyph is at full opacity, so leaving the renderer installed between
//  passes costs nothing and avoids view-identity changes. Timing and the
//  decision to sweep live in `BalanceLoadIndicatorModel`.
//

import SwiftUI

// `nonisolated`: a value type with no UI state, used by views on the
// main actor and constructible from previews and tests.
nonisolated struct GlyphWaveTextRenderer: TextRenderer {
    /// 0 puts the trough just before the first glyph, 1 just after the last.
    var progress: Double
    /// Opacity at the centre of the trough. 1 disables the effect. 35 % was
    /// too hard a dip on the device; 60 % keeps it a breath, not a blink
    /// (device looks 2026-10-13).
    var troughOpacity: Double = 0.6
    /// Width of the trough measured in average glyph widths. Three read as
    /// a few glyphs flickering, six still stepped; ten, nearly the whole
    /// label, so neighbouring glyphs differ little and the wave reads as
    /// continuous (device looks 2026-10-13).
    var waveWidthInGlyphs: Double = 10

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { line in line.flatMap { run in run.map { $0 } } }
        guard !slices.isEmpty else { return }

        // Position-based, not index-based, so the trough moves at a steady
        // speed across proportional glyphs and spaces.
        let rects = slices.map { $0.typographicBounds.rect }
        let minX = rects.map(\.minX).min() ?? 0
        let maxX = rects.map(\.maxX).max() ?? 0
        let averageGlyphWidth = max((maxX - minX) / CGFloat(slices.count), 1)
        let halfWave = CGFloat(waveWidthInGlyphs) * averageGlyphWidth / 2
        // Travel from entirely before the first glyph to entirely after the last.
        let start = minX - halfWave
        let end = maxX + halfWave
        let centre = start + CGFloat(progress) * (end - start)

        for (slice, rect) in zip(slices, rects) {
            let distance = abs(rect.midX - centre)
            let weight = max(0, 1 - distance / halfWave)
            // Smoothstep so the dip has no visible edges.
            let eased = weight * weight * (3 - 2 * weight)
            var glyphContext = context
            glyphContext.opacity = 1 - (1 - troughOpacity) * Double(eased)
            glyphContext.draw(slice)
        }
    }
}

// MARK: - Previews

/// Loops three-second passes back to back, the card's cadence.
private struct GlyphWavePreview: View {
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            label.background(Color.black)
            label.background(Color(white: 0.85))
            label.background(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
        }
        .padding()
        .task {
            while !Task.isCancelled {
                progress = 0
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.linear(duration: 3)) { progress = 1 }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var label: some View {
        Text(verbatim: "1,234,567 sats") // preview only; keeps the catalog clean
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .textRenderer(GlyphWaveTextRenderer(progress: progress))
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Glyph wave") {
    GlyphWavePreview()
}

/// Frozen mid-pass so the dip itself can be inspected and rendered.
#Preview("Glyph wave, mid-pass") {
    Text("Your Balance")
        .font(.system(size: 24, weight: .semibold))
        .foregroundColor(.white)
        .textRenderer(GlyphWaveTextRenderer(progress: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
        .padding(16)
        .background(Color.black)
}
