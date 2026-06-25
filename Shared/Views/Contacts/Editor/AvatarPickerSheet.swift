//
//  AvatarPickerSheet.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/04/25.
//

import SwiftUI
import UniformTypeIdentifiers
import ArkeUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AvatarPickerSheet: View {
    @Binding var selectedAvatarData: Data?
    @Environment(\.dismiss) private var dismiss
    
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    
    // Pre-defined avatar options
    private let systemAvatars = [
        "avatar-female-1",
        "avatar-female-2",
        "avatar-female-3",
        "avatar-female-4",
        "avatar-male-1",
        "avatar-male-2",
        "avatar-male-3",
        "avatar-male-4"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current Avatar Preview
                    currentAvatarPreview
                    
                    // System Avatars
                    systemAvatarSection
                    
                    // Custom Avatar Options
                    customAvatarSection
                    
                    // Error Display
                    if let errorMessage = errorMessage {
                        errorSection(errorMessage)
                    }
                }
                .padding()
            }
            .navigationTitle("button_choose_avatar")
            .toolbar {
                if selectedAvatarData != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("button_clear") {
                            selectedAvatarData = nil
                            errorMessage = nil
                        }
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("button_cancel")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("button_done")
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 500)
        #endif
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var currentAvatarPreview: some View {
        VStack(spacing: 12) {
            Text("label_current_avatar")
                .font(.headline)
            
            ContactAvatarView(avatarData: selectedAvatarData, size: 80)
        }
    }
    
    @ViewBuilder
    private var systemAvatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("contacts_preset_avatars")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(systemAvatars, id: \.self) { imageName in
                    Button {
                        createSystemAvatar(imageName: imageName)
                    } label: {
                        if let avatarData = loadSystemAvatarData(imageName: imageName) {
                            ContactAvatarView(avatarData: avatarData, size: 60)
                        } else {
                            // Fallback to direct image loading
                            Image(imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    private var customAvatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("label_custom_avatar")
                .font(.headline)
            
            Button {
                isShowingFilePicker = true
                errorMessage = nil
            } label: {
                HStack {
                    Image(systemName: "photo")
                        .font(.title2)
                    
                    Text(String(localized: "action_choose_from_files"))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(PlatformColor.systemGray.withAlphaComponent(0.1)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.Arke.red)
            .padding()
            .background(Color.Arke.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Actions
    
    private func loadSystemAvatarData(imageName: String) -> Data? {
        #if os(macOS)
        guard let image = NSImage(named: imageName) else { return nil }
        #else
        guard let image = UIImage(named: imageName) else { return nil }
        #endif
        
        return resizeImage(image, maxSize: 60)
    }
    
    private func createSystemAvatar(imageName: String) {
        // Load the image from assets
        #if canImport(AppKit)
        guard let image = NSImage(named: imageName) else {
            errorMessage = "Failed to load avatar image"
            return
        }
        #else
        guard let image = UIImage(named: imageName) else {
            errorMessage = "Failed to load avatar image"
            return
        }
        #endif
        
        // Convert to Data using the resizeImage helper
        if let data = resizeImage(image, maxSize: 300) {
            selectedAvatarData = data
            errorMessage = nil
        } else {
            errorMessage = "Failed to process avatar image"
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        print("handleFileImport: \(result)")
        switch result {
        case .success(let urls):
            print(String(localized: "format_zero"))
            guard let url = urls.first else { return }
            
            // Request access to the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file."
                return
            }
            
            // Make sure to stop accessing when done
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                print("0.5")
                let data = try Data(contentsOf: url)
                print("1")
                
                // Validate image size (limit to 2MB)
                if data.count > 2_000_000 {
                    errorMessage = "Image file is too large. Please choose an image under 2MB."
                    return
                }
                print("2")
                
                // Validate that it's actually an image
                guard let platformImage = PlatformImage(data: data) else {
                    errorMessage = "Selected file is not a valid image."
                    return
                }
                print("3")
                
                // Resize if needed (max 300x300)
                let resizedData = resizeImage(platformImage, maxSize: 300)
                selectedAvatarData = resizedData
                errorMessage = nil
                print("selectedAvatarData")
                
            } catch {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            errorMessage = "Failed to select image: \(error.localizedDescription)"
        }
    }
    
    private func resizeImage(_ image: PlatformImage, maxSize: CGFloat) -> Data? {
        #if canImport(AppKit)
        let originalSize = image.size
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
        
        // Don't upscale
        let scaleFactor = min(scale, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )
        
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: Int(newSize.width),
                                    pixelsHigh: Int(newSize.height),
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .calibratedRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0)
        
        guard let bitmap = bitmap else { return nil }
        
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        image.draw(in: NSRect(origin: .zero, size: newSize))
        
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmap.representation(using: .png, properties: [:])
        #else
        let originalSize = image.size
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
        
        // Don't upscale
        let scaleFactor = min(scale, 1.0)
        let newSize = CGSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage.pngData()
        #endif
    }
}
