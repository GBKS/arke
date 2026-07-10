//
//  ContactAvatarEditor.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/07/26.
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Avatar Selection

/// The avatar chosen in the editor. Only the editor distinguishes preset from custom;
/// the selection collapses to `Data?` at save time via `resolvedData()`.
public enum ContactAvatarSelection: Equatable {
    case none
    case preset(String)
    case custom(Data)

    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    public var presetName: String? {
        if case .preset(let name) = self { return name }
        return nil
    }

    public func resolvedData() -> Data? {
        switch self {
        case .none:
            return nil
        case .custom(let data):
            return data
        case .preset(let name):
            return ContactAvatarEditor.presetAvatarData(imageName: name)
        }
    }
}

// MARK: - Contact Avatar Editor

/// Inline avatar editing: a large preview with two overlaid controls.
/// The left circle toggles the preset tray (tap the selected preset again to deselect it),
/// the right circle picks a custom image file, or clears it once one is set.
public struct ContactAvatarEditor: View {
    @Binding var selection: ContactAvatarSelection

    @State private var showingPresets = false
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?

    /// Picked once per editor instance so the placeholder doesn't flip between renders
    @State private var silhouetteName: String = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"

    public static let presetAvatars = [
        "avatar-female-1",
        "avatar-female-2",
        "avatar-female-3",
        "avatar-female-4",
        "avatar-male-1",
        "avatar-male-2",
        "avatar-male-3",
        "avatar-male-4"
    ]

    private let previewSize: CGFloat = 110
    private let controlSize: CGFloat = 44

    public init(selection: Binding<ContactAvatarSelection>) {
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 16) {
            preview
                .overlay(alignment: .bottom) {
                    controls
                        .offset(y: controlSize / 2)
                }
                .padding(.bottom, controlSize / 2)

            if showingPresets {
                presetGrid
            }

            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.Arke.red)
            }
        }
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
    private var preview: some View {
        switch selection {
        case .preset(let name):
            circleImage(name, size: previewSize)
        case .custom(let data):
            ContactAvatarView(avatarData: data, size: previewSize)
        case .none:
            circleImage(silhouetteName, size: previewSize)
        }
    }

    private func circleImage(_ name: String, size: CGFloat) -> some View {
        Image(name, bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )
    }

    private var controls: some View {
        HStack(spacing: 32) {
            presetToggleButton
            customFileButton
        }
    }

    private var presetToggleButton: some View {
        Button {
            withAnimation(.snappy) {
                showingPresets.toggle()
            }
        } label: {
            circleImage(Self.presetAvatars[0], size: controlSize)
                .padding(3)
                .overlay(
                    Circle()
                        .stroke(Color.Arke.gold2, lineWidth: 2)
                        .opacity(showingPresets ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("contacts_preset_avatars", bundle: .module))
    }

    private var customFileButton: some View {
        Button {
            if selection.isCustom {
                selection = .none
                errorMessage = nil
            } else {
                errorMessage = nil
                isShowingFilePicker = true
            }
        } label: {
            Circle()
                .fill(Color.Arke.gold)
                .frame(width: controlSize, height: controlSize)
                .overlay {
                    Image(systemName: selection.isCustom ? "xmark" : "photo")
                        .font(.system(size: controlSize * 0.4, weight: .medium))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection.isCustom
            ? Text("button_clear", bundle: .module)
            : Text("action_choose_from_files", bundle: .module))
    }

    private var presetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            ForEach(Self.presetAvatars, id: \.self) { imageName in
                let isSelected = selection.presetName == imageName
                Button {
                    selection = isSelected ? .none : .preset(imageName)
                } label: {
                    circleImage(imageName, size: 48)
                        .padding(3)
                        .overlay(
                            Circle()
                                .stroke(Color.Arke.gold2, lineWidth: 2.5)
                                .opacity(isSelected ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding()
        .background(Color(PlatformColor.systemGray.withAlphaComponent(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    static func presetAvatarData(imageName: String) -> Data? {
        guard let image = platformImage(named: imageName) else { return nil }
        return resizeImage(image, maxSize: 300)
    }

    private static func platformImage(named name: String) -> PlatformImage? {
        #if canImport(AppKit)
        return Bundle.module.image(forResource: name)
        #else
        return UIImage(named: name, in: .module, with: nil)
        #endif
    }

    private func handleFileImport(_ result: Result<[URL], Swift.Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Request access to the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file."
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let data = try Data(contentsOf: url)

                // Validate image size (limit to 2MB)
                if data.count > 2_000_000 {
                    errorMessage = "Image file is too large. Please choose an image under 2MB."
                    return
                }

                // Validate that it's actually an image
                guard let platformImage = PlatformImage(data: data) else {
                    errorMessage = "Selected file is not a valid image."
                    return
                }

                // Resize if needed (max 300x300)
                guard let resizedData = Self.resizeImage(platformImage, maxSize: 300) else {
                    errorMessage = "Failed to process the selected image."
                    return
                }

                selection = .custom(resizedData)
                errorMessage = nil

            } catch {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Failed to select image: \(error.localizedDescription)"
        }
    }

    private static func resizeImage(_ image: PlatformImage, maxSize: CGFloat) -> Data? {
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

// MARK: - Previews

#Preview("Empty") {
    @Previewable @State var selection: ContactAvatarSelection = .none
    ContactAvatarEditor(selection: $selection)
        .padding()
}

#Preview("Preset Selected") {
    @Previewable @State var selection: ContactAvatarSelection = .preset("avatar-female-1")
    ContactAvatarEditor(selection: $selection)
        .padding()
}
