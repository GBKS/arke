//
//  QRCodeView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let content: String
    let title: String
    let onClose: () -> Void
    
    @State private var qrImage: NSImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 20) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                if let qrImage = qrImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
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
            }
            .padding()
            
            // Close button in top-right corner
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(ArkeIconButtonStyle(size: .small, variant: .ghost))
            .padding(.top, 20)
            .padding(.trailing, 20)
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
                qrImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
            }
        }
    }
}

#Preview("Generated QR Code") {
    QRCodeView(
        content: "bitcoin:tb1pdne86phvh597ztahnm58sdh6kwxqzkwcmarg2fa7rzzam4p7rfmqryhv5h?label=Ark%20Wallet&message=Test%20payment",
        title: "Scan QR code to pay",
        onClose: { print("Close tapped") }
    )
    .frame(width: 400, height: 400)
}
