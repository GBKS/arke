//
//  TagEditor.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI
import ArkeUI

// MARK: - Tag Editor

struct TagEditor: View {
    
    // MARK: - Properties
    
    /// The tag being edited (nil for new tag)
    let editingTag: TagModel?
    
    /// Callback when tag is saved
    let onSave: (TagModel) -> Void
    
    /// Callback when editing is cancelled
    let onCancel: () -> Void
    
    /// Tag service for validation and operations
    @Environment(\.tagService) private var tagService
    
    // MARK: - Form State
    
    @State private var name: String = ""
    @State private var selectedColorHex: String = "#4A90E2"
    @State private var selectedEmoji: String = ""
    
    // MARK: - UI State
    
    @State private var showingEmojiPicker: Bool = false
    @State private var showingColorPicker: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    // MARK: - Validation
    
    private var validation: TagValidation {
        TagValidation(
            name: name,
            existingTags: tagService.tags,
            editingTagId: editingTag?.id
        )
    }
    
    private var nameExists: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return tagService.tags.contains { existingTag in
            existingTag.name.lowercased() == trimmedName.lowercased() && 
            existingTag.id != editingTag?.id
        }
    }
    
    private var isValidName: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && name.count <= 30
    }
    
    private var canSave: Bool {
        isValidName && !nameExists && !isLoading
    }
    
    private var isEditing: Bool {
        editingTag != nil
    }
    
    // MARK: - Initialization
    
    init(editingTag: TagModel? = nil, onSave: @escaping (TagModel) -> Void, onCancel: @escaping () -> Void) {
        print("🔧 TagEditor: Initializing with editingTag: \(editingTag?.name ?? "nil") (ID: \(editingTag?.id.uuidString ?? "nil"))")
        self.editingTag = editingTag
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Preview Section
                    // tagPreviewSection
                    
                    // Form Section
                    TagFormFields(
                        name: $name,
                        selectedEmoji: $selectedEmoji,
                        selectedColorHex: $selectedColorHex,
                        showingEmojiPicker: $showingEmojiPicker,
                        showingColorPicker: $showingColorPicker,
                        nameExists: nameExists,
                        onSubmit: saveTag
                    )
                    
                    // Error Section
                    if let errorMessage = errorMessage {
                        errorSection(errorMessage)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
        }
        .onAppear {
            print("🔧 TagEditor: onAppear called")
            setupInitialValues()
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerSheet(selectedEmoji: $selectedEmoji)
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(selectedColorHex: $selectedColorHex)
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var tagPreviewSection: some View {
        TagPreviewCard(tag: previewTag, isEmpty: name.isEmpty)
    }
    
    @ViewBuilder
    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Image(systemName: "xmark")
        }
    }
    
    @ViewBuilder
    private var saveButton: some View {
        Button {
            saveTag()
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        Color.black.opacity(0.1)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .scaleEffect(1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .frame(width: 80, height: 80)
                    )
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
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        isEditing ? "Edit Tag" : "New Tag"
    }
    
    private var previewTag: TagModel {
        let displayName = name.isEmpty ? "Sample Tag" : name
        return TagModel(
            name: displayName,
            colorHex: selectedColorHex,
            emoji: selectedEmoji
        )
    }
    
    // MARK: - Actions
    
    private func setupInitialValues() {
        print("🔧 TagEditor: setupInitialValues called with editingTag: \(editingTag?.name ?? "nil") (ID: \(editingTag?.id.uuidString ?? "nil"))")
        
        if let tag = editingTag {
            name = tag.name
            selectedColorHex = tag.colorHex
            selectedEmoji = tag.emoji
            print("🔧 TagEditor: Set form values - name: '\(name)', color: '\(selectedColorHex)', emoji: '\(selectedEmoji)'")
        } else {
            // Set up defaults for new tag
            name = ""
            selectedColorHex = suggestRandomColor()
            selectedEmoji = ""
            print("🔧 TagEditor: Set default values - name: '\(name)', color: '\(selectedColorHex)', emoji: '\(selectedEmoji)'")
        }
        
        errorMessage = nil
    }
    
    private func saveTag() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard canSave else { return }
        
        isLoading = true
        errorMessage = nil
        
        let tagToSave: TagModel
        if let existingTag = editingTag {
            // Update existing tag
            tagToSave = TagModel(
                id: existingTag.id,
                name: trimmedName,
                colorHex: selectedColorHex,
                emoji: selectedEmoji,
                createdDate: existingTag.createdDate
            )
        } else {
            // Create new tag
            tagToSave = TagModel(
                name: trimmedName,
                colorHex: selectedColorHex,
                emoji: selectedEmoji
            )
        }
        
        // Simulate async operation
        Task {
            do {
                // Add small delay for better UX
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await MainActor.run {
                    isLoading = false
                    onSave(tagToSave)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to save tag: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func suggestRandomColor() -> String {
        let colors: [String] = [
            "#FF6B35", "#4A90E2", "#7B68EE", "#32CD32", 
            "#FFD700", "#FF69B4", "#8B4513", "#FF4444",
            "#9370DB", "#20B2AA", "#FF8C00", "#6495ED"
        ]
        return colors.randomElement() ?? "#4A90E2"
    }
}

// MARK: - Presentation Modifiers

extension View {
    /// Present TagEditor as a sheet
    func tagEditorSheet(
        isPresented: Binding<Bool>,
        editingTag: TagModel? = nil,
        tagService: TagService,
        onSave: @escaping (TagModel) async -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            TagEditor(
                editingTag: editingTag,
                onSave: { tag in
                    Task {
                        await onSave(tag)
                    }
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                }
            )
            .environment(tagService)
        }
    }
    
    /// Present TagEditor as a popover (iPad)
    func tagEditorPopover(
        isPresented: Binding<Bool>,
        editingTag: TagModel? = nil,
        tagService: TagService,
        onSave: @escaping (TagModel) async -> Void
    ) -> some View {
        self.popover(isPresented: isPresented, arrowEdge: .top) {
            TagEditor(
                editingTag: editingTag,
                onSave: { tag in
                    Task {
                        await onSave(tag)
                    }
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                }
            )
            .environment(tagService)
            .frame(width: 400, height: 600)
        }
    }
}
