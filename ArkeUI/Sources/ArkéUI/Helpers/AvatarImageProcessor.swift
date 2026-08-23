//
//  AvatarImageProcessor.swift
//  ArkéUI
//
//  Single recipe for avatar image data: downscale to a bounded pixel size and
//  encode as JPEG. Every site that writes avatarData (contact editor, profile
//  photo picker, native contact import, default contacts) routes through this
//  so avatars stay small in SwiftData, CloudKit payloads, and metadata exports.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum AvatarImageProcessor {

    /// Maximum pixel dimension of a stored avatar
    public static let maxDimension: CGFloat = 512

    /// JPEG encoding quality for stored avatars
    public static let jpegQuality: CGFloat = 0.8

    /// Stored avatars above this byte count are considered oversized and get
    /// re-encoded by the one-time cleanup pass (a 512px JPEG stays well below it)
    public static let oversizedThresholdBytes = 150_000

    /// Decode, downscale, and re-encode arbitrary image data as an avatar-sized JPEG.
    /// Returns nil if the data is not a decodable image.
    public static func processedData(from data: Data) -> Data? {
        guard let image = PlatformImage(data: data) else { return nil }
        return processedData(from: image)
    }

    /// Downscale and encode a platform image as an avatar-sized JPEG.
    /// Transparent regions are flattened onto white (JPEG has no alpha).
    public static func processedData(from image: PlatformImage) -> Data? {
        #if canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let pixelSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let scale = min(maxDimension / pixelSize.width, maxDimension / pixelSize.height, 1.0)
        let targetWidth = Int((pixelSize.width * scale).rounded())
        let targetHeight = Int((pixelSize.height * scale).rounded())

        guard targetWidth > 0, targetHeight > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: targetWidth,
                                            pixelsHigh: targetHeight,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .calibratedRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0) else { return nil }

        // Match point size to pixel size so draw(in:) maps 1:1 onto pixels
        bitmap.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high

        let targetRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        NSColor.white.setFill()
        targetRect.fill()
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
        #else
        // UIImage.size is in points; work in pixels and render at scale 1 so
        // the output isn't silently multiplied by the device's screen scale
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let scale = min(maxDimension / pixelSize.width, maxDimension / pixelSize.height, 1.0)
        let targetSize = CGSize(width: (pixelSize.width * scale).rounded(), height: (pixelSize.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { context in
            let targetRect = CGRect(origin: .zero, size: targetSize)
            UIColor.white.setFill()
            context.fill(targetRect)
            image.draw(in: targetRect)
        }

        return resized.jpegData(compressionQuality: jpegQuality)
        #endif
    }
}
