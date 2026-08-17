//
//  UsagePatternView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct UsagePatternView: View {
    let onBack: () -> Void
    let onContinue: (ServerUsageProfile) -> Void
    let usagePattern: ServerUsageProfile
    
    @State private var averageBalance: Double = 100_000 // in sats
    @State private var transactionsPerMonth: Double = 10
    @State private var monthlyVolume: Double = 50_000 // in sats
    
    // Track the last custom values set by user
    @State private var lastCustomBalance: Double?
    @State private var lastCustomTransactions: Double?
    @State private var lastCustomVolume: Double?
    @State private var isApplyingPreset = false
    
    // For custom input mode
    @State private var showCustomInput = false
    @State private var balanceText: String = ""
    @State private var transactionsText: String = ""
    @State private var volumeText: String = ""
    
    // Computed property to determine which preset matches current values
    private var currentPreset: ServerUsageProfile? {
        let currentBalance = Int(averageBalance)
        let currentVolume = Int(monthlyVolume)
        let currentTransactions = Int(transactionsPerMonth)
        
        if matchesPreset(.casual, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
            return .casual
        } else if matchesPreset(.spender, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
            return .spender
        } else if matchesPreset(.saver, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
            return .saver
        }
        
        return nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top navigation area
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.Arke.gold)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    Text(String(localized: "onboarding_how_do_you_use_bitcoin", defaultValue: "How do you use bitcoin?"))
                        .font(.system(size: 30, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text(String(localized: "onboarding_usage_pattern_help", defaultValue: "We will use this in the next step to optimize your expected fees."))
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 10)
                
                // Quick presets using ServerUsageProfilePicker
                ServerUsageProfilePicker(
                    selectedProfile: Binding(
                        get: { 
                            // If current values don't match a preset, return the custom profile
                            // This will cause the picker to select "Custom"
                            currentPreset ?? buildCurrentProfile()
                        },
                        set: { newProfile in
                            applyPreset(profile: newProfile)
                        }
                    ),
                    customProfile: buildCurrentProfile(),
                    showExpandableDetails: false
                )
                .frame(maxWidth: 600)
                
                // Custom sliders
                VStack(alignment: .leading, spacing: 15) {
                    // Average Balance
                    UsageSlider(
                        title: "Average Balance",
                        value: $averageBalance,
                        range: 10_000...1_000_000,
                        formatter: { sats in
                            formatSats(sats)
                        },
                        step: 10_000
                    )
                    .onChange(of: averageBalance) { _, _ in
                        saveCustomValues()
                    }
                    
                    // Transactions per month
                    UsageSlider(
                        title: "Transactions per Month",
                        value: $transactionsPerMonth,
                        range: 1...50,
                        formatter: { count in
                            String(format: "%.0f transactions", count)
                        },
                        step: 5
                    )
                    .onChange(of: transactionsPerMonth) { _, _ in
                        saveCustomValues()
                    }
                    
                    // Monthly volume
                    UsageSlider(
                        title: "Monthly Transaction Volume",
                        value: $monthlyVolume,
                        range: 10_000...1_000_000,
                        formatter: { sats in
                            formatSats(sats)
                        },
                        step: 10_000
                    )
                    .onChange(of: monthlyVolume) { _, _ in
                        saveCustomValues()
                    }
                }
                .frame(maxWidth: 600)
                
                Button(String(localized: "onboarding_continue", defaultValue: "Continue")) {
                    // Check if current values match any preset
                    let currentBalance = Int(averageBalance)
                    let currentVolume = Int(monthlyVolume)
                    let currentTransactions = Int(transactionsPerMonth)
                    
                    // Check casual preset
                    if matchesPreset(.casual, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
                        onContinue(.casual)
                        return
                    }
                    
                    // Check spender preset
                    if matchesPreset(.spender, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
                        onContinue(.spender)
                        return
                    }
                    
                    // Check saver preset
                    if matchesPreset(.saver, balance: currentBalance, volume: currentVolume, transactions: currentTransactions) {
                        onContinue(.saver)
                        return
                    }
                    
                    // No match - create custom profile
                    let totalTransactions = currentTransactions
                    
                    // Estimate split between on-Ark and Lightning (60/40 split as a reasonable default)
                    let onArkPayments = Int(Double(totalTransactions) * 0.6)
                    let lightningPayments = Int(Double(totalTransactions) * 0.4)
                    
                    // Calculate refreshes per month based on typical 30-day expiry
                    // Assume users refresh once per expiry period
                    let refreshesPerMonth = 1
                    
                    // VTXO count: estimate based on balance and typical UTXO fragmentation
                    // Larger balances and more transactions = more VTXOs
                    let vtxoCount = max(1, min(5, Int(averageBalance) / 100_000 + totalTransactions / 20))
                    
                    let profile = ServerUsageProfile(
                        averageBalance: currentBalance,
                        monthlyVolume: currentVolume,
                        onArkPayments: onArkPayments,
                        lightningPayments: lightningPayments,
                        refreshesPerMonth: refreshesPerMonth,
                        vtxoCount: vtxoCount
                    )
                    onContinue(profile)
                }
                .buttonStyle(ArkeButtonStyle(size: .large))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Arke.gold4)
        .onAppear {
            // Initialize state from the provided usage pattern
            averageBalance = Double(usagePattern.averageBalance)
            transactionsPerMonth = Double(usagePattern.onArkPayments + usagePattern.lightningPayments)
            monthlyVolume = Double(usagePattern.monthlyVolume)
        }
    }
    
    private func applyPreset(profile: ServerUsageProfile) {
        // Check if this profile matches any of the presets
        let isPreset = profile.isPreset
        
        if !isPreset {
            // User clicked "Custom" - restore their last custom values if available
            if let customBalance = lastCustomBalance,
               let customTransactions = lastCustomTransactions,
               let customVolume = lastCustomVolume {
                isApplyingPreset = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    averageBalance = customBalance
                    transactionsPerMonth = customTransactions
                    monthlyVolume = customVolume
                }
                // Reset flag after a brief delay to allow onChange to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isApplyingPreset = false
                }
                return
            }
            // If no saved custom values, the current values are already the custom ones
            return
        }
        
        // User selected a preset - apply values without triggering custom save
        isApplyingPreset = true
        
        // Apply preset values
        withAnimation(.easeInOut(duration: 0.3)) {
            averageBalance = Double(profile.averageBalance)
            transactionsPerMonth = Double(profile.onArkPayments + profile.lightningPayments)
            monthlyVolume = Double(profile.monthlyVolume)
        }
        
        // Reset flag after a brief delay to allow onChange to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isApplyingPreset = false
        }
    }
    
    private func saveCustomValues() {
        // Don't save if we're programmatically applying a preset
        guard !isApplyingPreset else { return }
        
        // Always save the current values as custom values
        lastCustomBalance = averageBalance
        lastCustomTransactions = transactionsPerMonth
        lastCustomVolume = monthlyVolume
    }
    
    private func buildCurrentProfile() -> ServerUsageProfile {
        let currentBalance = Int(averageBalance)
        let currentVolume = Int(monthlyVolume)
        let currentTransactions = Int(transactionsPerMonth)
        
        let onArkPayments = Int(Double(currentTransactions) * 0.6)
        let lightningPayments = Int(Double(currentTransactions) * 0.4)
        let refreshesPerMonth = 1
        let vtxoCount = max(1, min(5, currentBalance / 100_000 + currentTransactions / 20))
        
        return ServerUsageProfile(
            averageBalance: currentBalance,
            monthlyVolume: currentVolume,
            onArkPayments: onArkPayments,
            lightningPayments: lightningPayments,
            refreshesPerMonth: refreshesPerMonth,
            vtxoCount: vtxoCount
        )
    }
    
    private func matchesPreset(_ preset: ServerUsageProfile, balance: Int, volume: Int, transactions: Int) -> Bool {
        return preset.averageBalance == balance &&
               preset.monthlyVolume == volume &&
               (preset.onArkPayments + preset.lightningPayments) == transactions
    }
    
    private func formatSats(_ sats: Double) -> String {
        return BitcoinFormatter.shared.formatAmount(Int(sats))
        /*
        let value = Int(sats)
        if value >= 1_000_000 {
            return String(format: "%.2f M sats", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1f K sats", Double(value) / 1_000)
        } else {
            return "\(value) sats"
        }
         */
    }
}

// MARK: - Supporting Views

struct UsageSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    var step: Double? = nil // Optional step for snapping
    
    @State private var tempValue: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(formatter(value))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.Arke.gold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
            }
            
            Slider(value: sliderBinding, in: range)
                .tint(Color.Arke.gold)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                )
                .padding(.horizontal, -4)
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .onAppear {
            tempValue = value
        }
        .onChange(of: value) { oldValue, newValue in
            // Sync tempValue when value changes externally (e.g., from presets)
            withAnimation(.easeInOut(duration: 0.4)) {
                tempValue = newValue
            }
        }
    }
    
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { tempValue },
            set: { newValue in
                tempValue = newValue
                if let step = step {
                    // Snap to step intervals
                    value = round(newValue / step) * step
                } else {
                    // Default behavior - round to nearest integer
                    value = round(newValue)
                }
            }
        )
    }
}

// MARK: - ServerUsageProfile Extension

extension ServerUsageProfile {
    /// Check if this profile matches one of the predefined presets
    var isPreset: Bool {
        return self == .casual || self == .spender || self == .saver
    }
    
    /// Get the name of the preset, or "Custom" if not a preset
    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .spender: return "Spender"
        case .saver: return "Saver"
        default: return "Custom"
        }
    }
}
