//
//  ProfilePhotoPickerView.swift
//  Arké
//
//  Created by Christoph on 3/5/26.
//

import SwiftUI
import PhotosUI
import ArkeUI

/// Reusable profile photo picker with edit/remove functionality
struct ProfilePhotoPickerView: View {
    @Binding var avatarData: Data?
    let size: CGFloat
    let showEditButton: Bool

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingRemoveConfirmation = false

    init(avatarData: Binding<Data?>, size: CGFloat = 120, showEditButton: Bool = true) {
        self._avatarData = avatarData
        self.size = size
        self.showEditButton = showEditButton
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar display
            avatarImage
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                )

            // Action buttons
            if showEditButton {
                if avatarData != nil {
                    removeButton
                } else {
                    addButton
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await loadPhoto(from: newItem)
            }
        }
    }

    // MARK: - Avatar Display

    @ViewBuilder
    private var avatarImage: some View {
        if let avatarData = avatarData,
           let image = platformImage(from: avatarData) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Randomly select between male and female silhouette
            let defaultAvatar = Bool.random() ? "avatar-silhouette-male" : "avatar-silhouette-female"

            ZStack {
                Image(defaultAvatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }

    // MARK: - Action Buttons

    private var addButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 36, height: 36)

                Image(systemName: "camera.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: 4)
    }

    private var removeButton: some View {
        Button {
            showingRemoveConfirmation = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 36, height: 36)

                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: 4)
        .confirmationDialog(String(localized: "action_remove_photo", defaultValue: "Remove Photo"),
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.actionRemove, role: .destructive) {
                withAnimation {
                    avatarData = nil
                }
            }
            Button(L10n.buttonCancel, role: .cancel) {}
        } message: {
            Text(String(localized: "profile_remove_photo_confirm", defaultValue: "Are you sure you want to remove your profile photo?"))
        }
    }

    // MARK: - Photo Loading

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            // Load transferable data
            if let data = try await item.loadTransferable(type: Data.self) {
                // Compress and resize if needed
                if let processedData = processImageData(data) {
                    await MainActor.run {
                        withAnimation {
                            avatarData = processedData
                        }
                    }
                }
            }
        } catch {
            print("❌ [ProfilePhotoPickerView] Error loading photo: \(error)")
        }
    }

    /// Process image to reasonable size and quality (max 512px, JPEG 80%)
    private func processImageData(_ data: Data) -> Data? {
        let maxDimension: CGFloat = 512

        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.8)
        #else
        guard let image = NSImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        let newSize = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #endif
    }
}
