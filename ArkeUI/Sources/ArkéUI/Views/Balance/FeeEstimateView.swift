//
//  FeeEstimateView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 3/10/26.
//

import SwiftUI

/// A reusable view that displays fee estimates with debounced async loading
/// - Parameter Input: The type of input used to estimate the fee (e.g., UInt64 for amount, [String] for vtxoIds)
public struct FeeEstimateView<Input: Equatable & Sendable>: View {
    let input: Input?
    let estimateFee: @Sendable (Input) async throws -> UInt64
    
    @State private var estimatedFee: UInt64?
    @State private var isLoading: Bool = false
    @State private var hasError: Bool = false
    @State private var estimateTask: Task<Void, Never>?
    
    private let debounceDelay: TimeInterval = 0.5

    public init(input: Input?, estimateFee: @escaping @Sendable (Input) async throws -> UInt64) {
        self.input = input
        self.estimateFee = estimateFee
    }

    public var body: some View {
        VStack {
            if isLoading {
                HStack(spacing: 6) {
                    Text("Fee: ")
                    ProgressView()
                        .controlSize(.small)
                }
                .font(.body)
                .foregroundColor(.secondary)
            } else if hasError {
                Text("Fee: Not available")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else if let fee = estimatedFee {
                Text("Fee: ~\(BitcoinFormatter.shared.formatAmount(Int(fee)))")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text("Fee: —")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: input) { oldValue, newValue in
            handleInputChange(newValue)
        }
        .onAppear {
            handleInputChange(input)
        }
        .onDisappear {
            estimateTask?.cancel()
        }
    }
    
    private func handleInputChange(_ input: Input?) {
        // Cancel any existing task
        estimateTask?.cancel()
        
        // Reset state if input is nil
        guard let input = input else {
            estimatedFee = nil
            isLoading = false
            hasError = false
            return
        }
        
        // Show loading immediately
        isLoading = true
        hasError = false
        estimatedFee = nil
        
        // Create new debounced task
        estimateTask = Task {
            // Wait for debounce delay
            try? await Task.sleep(for: .milliseconds(Int(debounceDelay * 1000)))
            
            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { return }
            
            do {
                let fee = try await estimateFee(input)
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Update UI with result
                await MainActor.run {
                    estimatedFee = fee
                    isLoading = false
                    hasError = false
                }
            } catch {
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Update UI with error
                await MainActor.run {
                    estimatedFee = nil
                    isLoading = false
                    hasError = true
                }
            }
        }
    }
}

#Preview("With Amount") {
    VStack(spacing: 20) {
        FeeEstimateView(input: UInt64(50000)) { amount in
            // Simulate network delay
            try await Task.sleep(for: .milliseconds(500))
            return 1500 // Mock fee
        }
        
        FeeEstimateView(input: UInt64(100000)) { amount in
            try await Task.sleep(for: .milliseconds(300))
            return 2000
        }
    }
    .padding()
}

#Preview("Loading") {
    FeeEstimateView(input: UInt64(50000)) { amount in
        // Simulate slow network
        try await Task.sleep(for: .seconds(5))
        return 1500
    }
    .padding()
}

#Preview("Error") {
    FeeEstimateView(input: UInt64(50000)) { amount in
        throw NSError(domain: "FeeError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
    }
    .padding()
}

#Preview("No Amount") {
    FeeEstimateView<UInt64>(input: nil) { amount in
        return 1500
    }
    .padding()
}

#Preview("With VTXO IDs") {
    FeeEstimateView(input: ["vtxo1", "vtxo2", "vtxo3"]) { vtxoIds in
        // Simulate fee calculation for refresh
        try await Task.sleep(for: .milliseconds(400))
        return UInt64(vtxoIds.count) * 500 // Mock fee based on count
    }
    .padding()
}
