//
//  GlyphWaveRenderTests.swift
//  ArkéTests
//
//  The first load-indicator sweep shipped without anyone having seen it,
//  and it turned out never to draw (2026-10-13). This rasterises the label
//  through the renderer and checks the one thing that matters: at rest the
//  glyphs are untouched, mid-pass some of them are visibly dimmer.
//

import SwiftUI
import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Glyph Wave Render Tests")
@MainActor
struct GlyphWaveRenderTests {

    /// White label on black; the luminance of each pixel is then the
    /// rendered glyph opacity.
    private static func render(_ renderer: GlyphWaveTextRenderer?) -> [UInt8]? {
        let label = Text("Your Balance")
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black)
        let imageRenderer: ImageRenderer<AnyView>
        if let renderer {
            imageRenderer = ImageRenderer(content: AnyView(label.textRenderer(renderer)))
        } else {
            imageRenderer = ImageRenderer(content: AnyView(label))
        }
        imageRenderer.scale = 2
        guard let image = imageRenderer.cgImage else { return nil }
        return grayPixels(of: image)
    }

    private static func grayPixels(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Pixels bright enough to count as "glyph at full opacity".
    private static func brightCount(_ pixels: [UInt8]) -> Int {
        pixels.filter { $0 > 230 }.count
    }

    @Test("At rest (progress 0 or 1) the renderer is invisible")
    func restIsIdentity() throws {
        let plain = try #require(Self.render(nil))
        let atStart = try #require(Self.render(GlyphWaveTextRenderer(progress: 0)))
        let atEnd = try #require(Self.render(GlyphWaveTextRenderer(progress: 1)))
        #expect(Self.brightCount(plain) > 0)
        #expect(Self.brightCount(atStart) == Self.brightCount(plain))
        #expect(Self.brightCount(atEnd) == Self.brightCount(plain))
    }

    @Test("Mid-pass, a visible share of the glyph pixels is dimmed but none vanish")
    func midPassDimsSomeGlyphs() throws {
        let plain = try #require(Self.render(nil))
        let midPass = try #require(Self.render(GlyphWaveTextRenderer(progress: 0.5)))
        let plainBright = Self.brightCount(plain)
        let midBright = Self.brightCount(midPass)
        // The trough is ten glyph-widths of twelve, so most glyph pixels
        // should drop below full mid-pass; demand at least a tenth so the
        // test survives width, depth, font and anti-aliasing changes.
        #expect(midBright < plainBright - plainBright / 10)
        // Trough opacity is 60 %, not 0: dimmed glyphs stay legible.
        let dimmedButVisible = midPass.filter { $0 > 40 && $0 <= 230 }.count
        #expect(dimmedButVisible > 0)
    }
}
