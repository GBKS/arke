//
//  TagEditor.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

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
    @Environment(TagService.self) private var tagService
    
    // MARK: - Form State
    
    @State private var name: String = ""
    @State private var selectedColorHex: String = "#4A90E2"
    @State private var selectedEmoji: String = ""
    @State private var isActive: Bool = true
    
    // MARK: - UI State
    
    @State private var showingEmojiPicker: Bool = false
    @State private var showingColorPicker: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    // MARK: - Validation
    
    private var isValidName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        name.count <= 30
    }
    
    private var nameExists: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return tagService.activeTags.contains { existingTag in
            existingTag.name.lowercased() == trimmedName.lowercased() && 
            existingTag.id != editingTag?.id
        }
    }
    
    private var canSave: Bool {
        isValidName && !nameExists && !isLoading
    }
    
    private var isEditing: Bool {
        editingTag != nil
    }
    
    // MARK: - Initialization
    
    init(editingTag: TagModel? = nil, onSave: @escaping (TagModel) -> Void, onCancel: @escaping () -> Void) {
        self.editingTag = editingTag
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Preview Section
                    tagPreviewSection
                    
                    // Form Section
                    formSection
                    
                    // Error Section
                    if let errorMessage = errorMessage {
                        errorSection(errorMessage)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle(isEditing ? "Edit Tag" : "New Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveTag()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
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
        VStack(spacing: 12) {
            Text("Preview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                if !name.isEmpty {
                    TagChip(tag: previewTag)
                } else {
                    Text("Enter a name to see preview")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var formSection: some View {
        VStack(spacing: 20) {
            // Name Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Name")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(name.count)/30")
                        .font(.caption)
                        .foregroundStyle(name.count > 25 ? .orange : .secondary)
                }
                
                TextField("Enter tag name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if canSave {
                            saveTag()
                        }
                    }
                
                if nameExists {
                    Label("A tag with this name already exists", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Emoji Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji (Optional)")
                    .font(.headline)
                
                HStack {
                    Button(action: {
                        showingEmojiPicker.toggle()
                    }) {
                        HStack {
                            if selectedEmoji.isEmpty {
                                Image(systemName: "face.smiling")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(selectedEmoji)
                                    .font(.title2)
                            }
                            
                            Text(selectedEmoji.isEmpty ? "Choose emoji" : "Change emoji")
                                .foregroundStyle(selectedEmoji.isEmpty ? .secondary : .primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    
                    if !selectedEmoji.isEmpty {
                        Button("Clear") {
                            selectedEmoji = ""
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
            }
            
            // Color Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.headline)
                
                Button(action: {
                    showingColorPicker.toggle()
                }) {
                    HStack {
                        Circle()
                            .fill(Color(hex: selectedColorHex) ?? .blue)
                            .frame(width: 24, height: 24)
                        
                        Text("Choose color")
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: nameExists)
    }
    
    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Computed Properties
    
    private var previewTag: TagModel {
        TagModel(
            name: name.isEmpty ? "Sample Tag" : name,
            colorHex: selectedColorHex,
            emoji: selectedEmoji,
            isActive: isActive
        )
    }
    
    // MARK: - Actions
    
    private func setupInitialValues() {
        if let tag = editingTag {
            name = tag.name
            selectedColorHex = tag.colorHex
            selectedEmoji = tag.emoji
            isActive = tag.isActive
        } else {
            // Set up defaults for new tag
            name = ""
            selectedColorHex = suggestRandomColor()
            selectedEmoji = ""
            isActive = true
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
                createdDate: existingTag.createdDate,
                isActive: isActive
            )
        } else {
            // Create new tag
            tagToSave = TagModel(
                name: trimmedName,
                colorHex: selectedColorHex,
                emoji: selectedEmoji,
                isActive: isActive
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
        let colors = [
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

// MARK: - Preview

#Preview("New Tag") {
    TagEditor(
        onSave: { tag in
            print("Saved tag: \(tag)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environment(TagService(taskManager: TaskDeduplicationManager()))
}

#Preview("Edit Tag") {
    TagEditor(
        editingTag: TagModel(name: "Coffee", colorHex: "#8B4513", emoji: "☕"),
        onSave: { tag in
            print("Updated tag: \(tag)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environment(TagService(taskManager: TaskDeduplicationManager()))
}
