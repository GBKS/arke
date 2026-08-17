//
//  FaucetModalView_iOS.swift
//  Arké
//
//  Created by Christoph on 01/21/26.
//

import SwiftUI
import ArkeUI

struct FaucetModalView_iOS: View {
    @Environment(WalletManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    let onNavigateToContact: ((ContactModel) -> Void)?
    
    private let testingGuideURL = "https://arke.cash/test"
    private let discordURL = "https://discord.gg/THhNW5H26H"
    
    init(onNavigateToContact: ((ContactModel) -> Void)? = nil) {
        self.onNavigateToContact = onNavigateToContact
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero Section
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.Arke.gold)
                        
                        Text(String(localized: "onboarding_thanks_testing", defaultValue: "Thanks for helping test Arké"))
                            .font(.system(size: 28, design: .serif))
                        
                        Text(String(localized: "onboarding_tester_welcome", defaultValue: "As a tester, you'll be using test bitcoin that has no real-world value. Let's get you set up with some test coins so you can start exploring."))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "onboarding_how_test_bitcoin", defaultValue: "How to get test bitcoin"))
                            .font(.system(.title3, weight: .semibold))
                        
                        // Faucetto Signetto Contact Card
                        Button {
                            // TODO: Replace with actual contact lookup
                            // For now, you'll need to find the Faucetto Signetto contact from your ContactService
                            if let faucetContact = manager.contactServiceForEnvironment.contacts.first(where: { 
                                $0.displayName == "Faucetto Signetto" 
                            }) {
                                onNavigateToContact?(faucetContact)
                            } else {
                                // Handle case where contact doesn't exist yet
                                print("⚠️ Faucetto Signetto contact not found")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image("faucetto-signetto")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "onboarding_faucet_name", defaultValue: "Faucetto Signetto"))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    
                                    Text(String(localized: "action_tap_view_contact", defaultValue: "Tap to view contact"))
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        
                        FaucetInstructionRow(
                            number: 1,
                            text: "Find \"Faucetto Signetto\" in your contacts"
                        )
                        
                        FaucetInstructionRow(
                            number: 2,
                            text: "Tap \"Request test bitcoin\" on their contact card"
                        )
                        
                        FaucetInstructionRow(
                            number: 3,
                            text: "Wait a few minutes for the transaction to complete"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Testing Guide Button
                    Button {
                        if let url = URL(string: testingGuideURL) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "book.pages")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                            Text(String(localized: "button_view_test_guide", defaultValue: "View Test Guide"))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    .padding(.top, 15)
                    
                    // Discord Button
                    Button {
                        if let url = URL(string: discordURL) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                            Text(String(localized: "action_chat_discord", defaultValue: "Chat on Discord"))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    
                    // Note
                    Text(String(localized: "onboarding_faucet_disclaimer", defaultValue: "Faucetto has rate limits to ensure fair access. Please don't drain them, and return test coins when you're done."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Instruction Row Component
private struct FaucetInstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Color.Arke.gold4)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
