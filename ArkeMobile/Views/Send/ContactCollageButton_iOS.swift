//
//  ContactCollageButton.swift
//  Arké
//
//  Created by Assistant on 12/15/25.
//

import SwiftUI
import ArkeUI

/// A compact button that displays a collage of contact avatars and triggers contact selection
/// Shows up to 3 contact avatars in a grid, with a count badge for additional contacts
struct ContactCollageButton_iOS: View {
    let contacts: [ContactModel]
    let action: () -> Void
    
    private let buttonSize: CGFloat = 64
    private let avatarSize: CGFloat = 26
    private let spacing: CGFloat = 2
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Glass effect background
                /*
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    }
                    .frame(width: buttonSize, height: buttonSize)
                */
                
                // Avatar collage or fallback
                if contacts.isEmpty {
                    emptyStateView
                } else {
                    avatarCollageView
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(String(localized: "send_contact_picker_hint", defaultValue: "Opens contact picker to select a recipient"))
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: buttonSize, height: buttonSize)
            
            Image(systemName: "person.2")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }
    
    // MARK: - Avatar Collage
    
    @ViewBuilder
    private var avatarCollageView: some View {
        switch contacts.count {
        case 1:
            singleAvatarLayout
        case 2:
            twoAvatarLayout
        case 3:
            threeAvatarLayout
        case 4:
            fourAvatarLayout
        case 5...:
            fivePlusAvatarLayout
        default:
            emptyStateView
        }
    }
    
    // MARK: - Layout Variants
    
    // Single centered avatar (larger)
    @ViewBuilder
    private var singleAvatarLayout: some View {
        ContactAvatarView(
            avatarData: contacts[0].avatarData,
            size: buttonSize, // Larger for single avatar
            fallbackText: contacts[0].cachedName
        )
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
    
    // Two avatars overlapping at an angle
    @ViewBuilder
    private var twoAvatarLayout: some View {
        ZStack {
            // Back avatar (slightly smaller, offset left and up)
            ContactAvatarView(
                avatarData: contacts[0].avatarData,
                size: avatarSize * 1.4,
                fallbackText: contacts[0].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            .offset(x: -12, y: -8)
            .zIndex(0)
            
            // Front avatar (larger, offset right and down)
            ContactAvatarView(
                avatarData: contacts[1].avatarData,
                size: avatarSize * 1.6,
                fallbackText: contacts[1].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .offset(x: 10, y: 6)
            .zIndex(1)
        }
    }
    
    // Three avatars in an organic cluster
    @ViewBuilder
    private var threeAvatarLayout: some View {
        ZStack {
            // Bottom left avatar (smallest)
            ContactAvatarView(
                avatarData: contacts[0].avatarData,
                size: avatarSize * 1.2,
                fallbackText: contacts[0].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .offset(x: -15, y: 4)
            .zIndex(0)
            
            // Top right avatar (medium)
            ContactAvatarView(
                avatarData: contacts[1].avatarData,
                size: avatarSize * 1.3,
                fallbackText: contacts[1].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .offset(x: 8, y: -12)
            .zIndex(1)
            
            // Center front avatar (largest)
            ContactAvatarView(
                avatarData: contacts[2].avatarData,
                size: avatarSize * 1.4,
                fallbackText: contacts[2].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .offset(x: 12, y: 8)
            .zIndex(2)
        }
    }
    
    // Four avatars in an organic cluster (all showing)
    @ViewBuilder
    private var fourAvatarLayout: some View {
        ZStack {
            // Bottom left avatar
            ContactAvatarView(
                avatarData: contacts[0].avatarData,
                size: avatarSize * 1.0,
                fallbackText: contacts[0].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .offset(x: -12, y: 8)
            .zIndex(0)
            
            // Top left avatar
            ContactAvatarView(
                avatarData: contacts[1].avatarData,
                size: avatarSize * 1.1,
                fallbackText: contacts[1].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .offset(x: -12, y: -8)
            .zIndex(1)
            
            // Top right avatar
            ContactAvatarView(
                avatarData: contacts[2].avatarData,
                size: avatarSize * 1.2,
                fallbackText: contacts[2].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .offset(x: 10, y: -12)
            .zIndex(2)
            
            // Bottom right avatar (fourth contact)
            ContactAvatarView(
                avatarData: contacts[3].avatarData,
                size: avatarSize * 1.3,
                fallbackText: contacts[3].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .offset(x: 12, y: 8)
            .zIndex(3)
        }
    }
    
    // Five+ avatars in an organic pile with count badge
    @ViewBuilder
    private var fivePlusAvatarLayout: some View {
        ZStack {
            // Bottom left avatar
            ContactAvatarView(
                avatarData: contacts[0].avatarData,
                size: avatarSize * 1.0,
                fallbackText: contacts[0].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .offset(x: -12, y: 8)
            .zIndex(0)
            
            // Top left avatar
            ContactAvatarView(
                avatarData: contacts[1].avatarData,
                size: avatarSize * 1.1,
                fallbackText: contacts[1].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .offset(x: -12, y: -8)
            .zIndex(1)
            
            // Top right avatar
            ContactAvatarView(
                avatarData: contacts[2].avatarData,
                size: avatarSize * 1.2,
                fallbackText: contacts[2].cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .offset(x: 10, y: -12)
            .zIndex(2)
            
            // Count badge - front right
            ZStack {
                Circle()
                    .fill(Color.Arke.gold.gradient)
                    .frame(width: avatarSize * 1.3, height: avatarSize * 1.3)
                
                Text("+\(max(0, contacts.count - 3))")
                    .font(.system(size: contacts.count > 12 ? 10 : 12, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .offset(x: 12, y: 8)
            .zIndex(3)
        }
    }
    
    @ViewBuilder
    private func avatarAtIndex(_ index: Int) -> some View {
        if index < contacts.count {
            let contact = contacts[index]
            ContactAvatarView(
                avatarData: contact.avatarData,
                size: avatarSize,
                fallbackText: contact.cachedName
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            }
        } else {
            // Empty placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: avatarSize, height: avatarSize)
        }
    }
    
    @ViewBuilder
    private var countBadge: some View {
        let remainingCount = max(0, contacts.count - 3)
        
        if remainingCount > 0 {
            ZStack {
                Circle()
                    .fill(Color.Arke.gold.gradient)
                    .frame(width: avatarSize, height: avatarSize)
                
                Text("+\(remainingCount)")
                    .font(.system(size: remainingCount > 9 ? 9 : 11, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            }
        } else if contacts.count == 3 {
            // Show the third contact's avatar instead of a count badge
            avatarAtIndex(3)
        } else {
            // Empty placeholder for fewer than 3 contacts
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: avatarSize, height: avatarSize)
        }
    }
    
    // MARK: - Accessibility
    
    private var accessibilityLabelText: String {
        if contacts.isEmpty {
            return "No contacts"
        } else if contacts.count == 1 {
            return "1 contact available"
        } else {
            return "\(contacts.count) contacts available"
        }
    }
}

// MARK: - Button Style

/// A button style that scales down on press with haptic feedback
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    // Haptic feedback on press
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                }
            }
    }
}
