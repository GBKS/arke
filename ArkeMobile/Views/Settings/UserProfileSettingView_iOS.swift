//
//  UserProfileSettingView_iOS.swift
//  Arké
//
//  Created by Christoph on 3/5/26.
//

import SwiftUI
import SwiftData

/// User profile editor for personal information
/// Used to customize name and photo for features like Tilt-to-Pay
struct UserProfileSettingView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var name: String = ""
    @State private var avatarData: Data?
    
    private var profile: UserProfile? {
        profiles.first
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Profile photo picker
                ProfilePhotoPickerView(
                    avatarData: $avatarData,
                    size: 150,
                    showEditButton: true
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                
                // Name field
                TextField("profile_name_placeholder", text: $name)
                    .font(.system(size: 24, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { _, newValue in
                        // Enforce 50 character limit
                        if newValue.count > 50 {
                            name = String(newValue.prefix(50))
                        }
                    }
                
                Spacer()
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("settings_my_profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadProfile()
        }
        .onDisappear {
            saveProfileIfNeeded()
        }
    }
    
    // MARK: - Data Management
    
    private func loadProfile() {
        guard let profile = profile else {
            // No profile exists yet, start with empty fields
            return
        }
        
        name = profile.name
        avatarData = profile.avatarData
    }
    
    private func saveProfileIfNeeded() {
        // Trim whitespace from name
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        // Check if there are any changes to save
        let hasChanges = hasProfileChanged()
        guard hasChanges else { return }
        
        if let existingProfile = profile {
            // Update existing profile
            existingProfile.update(name: trimmedName, avatarData: avatarData)
        } else {
            // Create new profile
            let newProfile = UserProfile(name: trimmedName, avatarData: avatarData)
            modelContext.insert(newProfile)
        }
        
        do {
            try modelContext.save()
            print("✅ [UserProfileSettingView] Profile auto-saved successfully")
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            print("❌ [UserProfileSettingView] Error saving profile: \(error)")
            
            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    private func hasProfileChanged() -> Bool {
        guard let profile = profile else {
            // No existing profile - check if user entered anything
            return !name.isEmpty || avatarData != nil
        }
        
        // Compare current values with saved profile
        return name != profile.name || avatarData != profile.avatarData
    }
}
