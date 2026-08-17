//
//  QRCodeView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// Type aliases for cross-platform compatibility
#if os(macOS)
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#else
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

public struct ArkeQRCodeView: View {
    let content: String
    let title: String
    let onClose: () -> Void

    @State private var qrImage: PlatformImage?

    public init(content: String, title: String, onClose: @escaping () -> Void) {
        self.content = content
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 20) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                if let qrImage = qrImage {
                    #if canImport(AppKit)
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                    #elseif canImport(UIKit)
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                    #endif
                } else {
                    SkeletonLoader(
                        itemCount: 1,
                        itemHeight: 200,
                        spacing: 10,
                        cornerRadius: 15
                    )
                    .frame(width: 200, height: 200)
                }
                
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding()
            
            // Close button in top-right corner
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .accessibilityLabel(L10n.buttonClose)
        }
        .task {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = content.data(using: .utf8) else { return }
        
        filter.message = data
        
        if let outputImage = filter.outputImage {
            // Scale up the QR code for better quality
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                #if canImport(AppKit)
                qrImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
                #elseif canImport(UIKit)
                qrImage = UIImage(cgImage: cgImage)
                #endif
            }
        }
    }
}

#Preview("Generated QR Code") {
    ArkeQRCodeView(
        content: "bitcoin:tb1pdne86phvh597ztahnm58sdh6kwxqzkwcmarg2fa7rzzam4p7rfmqryhv5h?label=Ark%20Wallet&message=Test%20payment",
        title: "Scan QR code to pay",
        onClose: { print("Close tapped") }
    )
    .frame(width: 400, height: 400)
}
