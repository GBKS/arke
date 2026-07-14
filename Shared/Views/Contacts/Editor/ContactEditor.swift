//
//  ContactEditor.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/04/25.
//

import SwiftUI
import ArkeUI

// MARK: - Contact Editor

struct ContactEditor: View {
    
    // MARK: - Properties
    
    /// The contact being edited (nil for new contact)
    let editingContact: ContactModel?
    
    /// Callback when contact is saved
    let onSave: (ContactModel) -> Void
    
    /// Callback when editing is cancelled
    let onCancel: () -> Void
    
    /// Callback when contact is deleted
    let onDelete: ((ContactModel) -> Void)?
    
    /// Contact service for validation and operations
    @Environment(\.contactService) private var contactService
    
    // MARK: - Form State
    
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var avatarSelection: ContactAvatarSelection = .none

    // Native contact import state
    @State private var importedNativeID: String? = nil
    @State private var importedNativeSyncDate: Date? = nil

    // MARK: - UI State

    @State private var showingContactImport: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation: Bool = false
    
    // MARK: - Validation
    
    private var allContacts: [ContactModel] {
        contactService.contacts
    }
    
    private var validation: ContactValidation {
        ContactValidation(
            name: name,
            notes: notes.isEmpty ? nil : notes,
            existingContacts: allContacts,
            editingContactId: editingContact?.id
        )
    }
    
    private var canSave: Bool {
        validation.isValid && !isLoading
    }
    
    private var isEditing: Bool {
        editingContact != nil
    }
    
    // MARK: - Initialization
    
    init(editingContact: ContactModel? = nil, onSave: @escaping (ContactModel) -> Void, onCancel: @escaping () -> Void, onDelete: ((ContactModel) -> Void)? = nil) {
        let initID = UUID().uuidString.prefix(8)
        print("👤 [ContactEditor.init] [\(initID)] Initializing with editingContact: \(editingContact?.displayName ?? "nil") (ID: \(editingContact?.id.uuidString ?? "nil"))")
        print("👤 [ContactEditor.init] [\(initID)] Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
        self.editingContact = editingContact
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }
    
    // MARK: - Body
    
    var body: some View {
        let bodyEvalID = UUID().uuidString.prefix(8)
        let _ = print("👤 [ContactEditor.body] [\(bodyEvalID)] Body being evaluated for editingContact: \(editingContact?.displayName ?? "nil")")
        
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Inline avatar editing with large preview
                    ContactAvatarEditor(selection: $avatarSelection)

                    // Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "placeholder_contact_name"), text: $name)
                            .font(.title3)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .onSubmit(saveContact)
                            .padding(12)
                            .background(fieldBackground)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > 50 {
                                    name = String(newValue.prefix(50))
                                }
                            }

                        if validation.nameExists {
                            Label("contacts_name_exists", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.Arke.red)
                        }
                    }

                    // Notes Field
                    TextField(String(localized: "placeholder_add_note"), text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(fieldBackground)
                        .onChange(of: notes) { _, newValue in
                            if newValue.count > 500 {
                                notes = String(newValue.prefix(500))
                            }
                        }

                    // Error Display
                    if let errorMessage = errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundColor(.Arke.red)
                    }
                }
                .padding()
            }
            .navigationTitle(navigationTitle)            
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton
                }
                
                if !isEditing {
                    ToolbarItem(placement: .automatic) {
                        importButton
                    }
                }
                
                if isEditing, onDelete != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        deleteButton
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            .confirmationDialog("button_delete_contact",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("button_delete", role: .destructive) {
                    deleteContact()
                }
                Button(role: .cancel) {
                    
                } label: {
                    Image(systemName: "xmark")
                }
            } message: {
                Text(String(localized: "message_confirm_delete_permanent", defaultValue: "Are you sure you want to delete \(editingContact?.displayName ?? "this contact")? This action cannot be undone."))
            }
        }
        .onAppear {
            let appearID = UUID().uuidString.prefix(8)
            print("👤 [ContactEditor.onAppear] [\(appearID)] onAppear called for editingContact: \(editingContact?.displayName ?? "nil") (ID: \(editingContact?.id.uuidString ?? "nil"))")
            setupInitialValues()
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .sheet(isPresented: $showingContactImport) {
            ContactImportSheet(
                onSelect: { importedData in
                    handleContactImport(importedData)
                    showingContactImport = false
                },
                onCancel: {
                    showingContactImport = false
                }
            )
        }
    }
    
    // MARK: - View Components

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(PlatformColor.systemGray.withAlphaComponent(0.1)))
    }

    @ViewBuilder
    private var importButton: some View {
        Button("button_import") {
            showingContactImport = true
        }
    }
    
    @ViewBuilder
    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("button_cancel")
    }
    
    @ViewBuilder
    private var saveButton: some View {
        //let buttonTitle = isEditing ? "Save" : "Create"
        Button {
            saveContact()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("button_save")
        .disabled(!canSave)
        .fontWeight(.semibold)
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("button_delete", systemImage: "trash")
        }
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
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        isEditing ? String(localized: "button_edit_contact") : "New Contact"
    }
    
    // MARK: - Actions
    
    private func setupInitialValues() {
        print("👤 ContactEditor: setupInitialValues called with editingContact: \(editingContact?.displayName ?? "nil") (ID: \(editingContact?.id.uuidString ?? "nil"))")
        
        if let contact = editingContact {
            name = contact.cachedName
            notes = contact.notes ?? ""
            // Existing avatars are always treated as custom images; no preset matching
            avatarSelection = contact.avatarData.map { .custom($0) } ?? .none
            importedNativeID = contact.nativeContactID
            importedNativeSyncDate = contact.lastSyncedFromNative
            print("👤 ContactEditor: Set form values - name: '\(name)', notes: '\(notes.prefix(50))...', hasAvatar: \(avatarSelection != .none)")
        } else {
            // Set up defaults for new contact
            name = ""
            notes = ""
            avatarSelection = .none
            importedNativeID = nil
            importedNativeSyncDate = nil
            print("👤 ContactEditor: Set default values - name: '\(name)', notes: '\(notes)', hasAvatar: \(avatarSelection != .none)")
        }
        
        errorMessage = nil
    }
    
    private func handleContactImport(_ importedData: ImportedContactData) {
        print("👤 ContactEditor: Importing contact - name: \(importedData.fullName), hasAvatar: \(importedData.imageData != nil)")
        
        // Populate form fields with imported data
        name = importedData.fullName
        avatarSelection = importedData.imageData.map { .custom($0) } ?? .none
        importedNativeID = importedData.identifier
        importedNativeSyncDate = Date()
        
        // Clear any previous error
        errorMessage = nil
    }
    
    private func saveContact() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard canSave else { return }

        let avatarData = avatarSelection.resolvedData()

        let contactToSave: ContactModel
        if let existingContact = editingContact {
            // Update existing contact (preserve native contact link)
            contactToSave = ContactModel(
                id: existingContact.id,
                cachedName: trimmedName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                avatarData: avatarData,
                createdAt: existingContact.createdAt,
                updatedAt: Date(),
                nativeContactID: existingContact.nativeContactID,
                lastSyncedFromNative: existingContact.lastSyncedFromNative
            )
        } else {
            // Create new contact (include native contact link if imported)
            contactToSave = ContactModel(
                cachedName: trimmedName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                avatarData: avatarData,
                createdAt: Date(),
                updatedAt: Date(),
                nativeContactID: importedNativeID,
                lastSyncedFromNative: importedNativeSyncDate
            )
        }
        
        onSave(contactToSave)
    }
    
    private func deleteContact() {
        guard let contact = editingContact, let onDelete = onDelete else { return }
        onDelete(contact)
    }
}

#Preview("New Contact") {
    ContactEditor(
        onSave: { _ in },
        onCancel: { }
    )
}

// MARK: - Presentation Modifiers

extension View {
    /// Present ContactEditor as a sheet
    func contactEditorSheet(
        isPresented: Binding<Bool>,
        editingContact: ContactModel? = nil,
        contactService: ContactService,
        onSave: @escaping (ContactModel) async -> Void,
        onDelete: ((ContactModel) async -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ContactEditor(
                editingContact: editingContact,
                onSave: { contact in
                    Task {
                        await onSave(contact)
                    }
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                },
                onDelete: onDelete.map { deleteHandler in
                    { contact in
                        Task {
                            await deleteHandler(contact)
                        }
                        isPresented.wrappedValue = false
                    }
                }
            )
            .environment(contactService)
        }
    }
    
    /// Present ContactEditor as a popover (optimal for macOS)
    func contactEditorPopover(
        isPresented: Binding<Bool>,
        editingContact: ContactModel? = nil,
        contactService: ContactService,
        onSave: @escaping (ContactModel) async -> Void,
        onDelete: ((ContactModel) async -> Void)? = nil
    ) -> some View {
        self.popover(isPresented: isPresented, arrowEdge: .top) {
            ContactEditor(
                editingContact: editingContact,
                onSave: { contact in
                    Task {
                        await onSave(contact)
                    }
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                },
                onDelete: onDelete.map { deleteHandler in
                    { contact in
                        Task {
                            await deleteHandler(contact)
                        }
                        isPresented.wrappedValue = false
                    }
                }
            )
            .environment(contactService)
            .frame(width: 500, height: 700)
        }
    }
    
    /// Present ContactEditor as a window (best for macOS)
    func contactEditorWindow(
        isPresented: Binding<Bool>,
        editingContact: ContactModel? = nil,
        contactService: ContactService,
        onSave: @escaping (ContactModel) async -> Void,
        onDelete: ((ContactModel) async -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ContactEditor(
                editingContact: editingContact,
                onSave: { contact in
                    Task {
                        await onSave(contact)
                    }
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                },
                onDelete: onDelete.map { deleteHandler in
                    { contact in
                        Task {
                            await deleteHandler(contact)
                        }
                        isPresented.wrappedValue = false
                    }
                }
            )
            .environment(contactService)
            .frame(minWidth: 500, maxWidth: 600, minHeight: 700, maxHeight: 800)
        }
    }
}
