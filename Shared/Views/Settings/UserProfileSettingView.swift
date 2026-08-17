//
//  UserProfileSettingView.swift
//  Arké
//
//  Created by Christoph on 3/5/26.
//

import SwiftUI
import SwiftData
import ArkeUI

/// User profile editor for personal information
/// Used to customize name and photo for features like Tilt-to-Pay
struct UserProfileSettingView: View {
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
                TextField(String(localized: "profile_name_placeholder", defaultValue: "Enter your name"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.systemControlBackground)
                    .cornerRadius(10)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .onChange(of: name) { _, newValue in
                        // Enforce 50 character limit
                        if newValue.count > 50 {
                            name = String(newValue.prefix(50))
                        }
                    }

                Spacer()
            }
            .padding()
            #if os(macOS)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(Color.systemBackground)
        .navigationTitle(String(localized: "settings_my_profile", defaultValue: "My Profile"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
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

            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        } catch {
            print("❌ [UserProfileSettingView] Error saving profile: \(error)")

            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif
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
