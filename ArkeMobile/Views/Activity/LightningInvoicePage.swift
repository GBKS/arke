//
//  LightningInvoicePage.swift
//  Arké
//
//  Created by Christoph on 5/23/26.
//

import SwiftUI
import SwiftData
import ArkeUI

/// Lightning invoice generation page for TiltShareOverlay
/// Displays either amount input state or QR code state
struct LightningInvoicePage: View {
    @Query private var profiles: [UserProfile]
    
    @State private var amount: String = ""
    @State private var invoiceState: InvoiceState = .amountInput
    @State private var generatedInvoice: String?
    @State private var qrImage: UIImage?
    @State private var errorMessage: String?
    
    let screenWidth: CGFloat
    let walletManager: WalletManager?
    let onClose: () -> Void
    
    private var userProfile: UserProfile? {
        profiles.first
    }
    
    private var amountInSats: Int? {
        Int(amount)
    }
    
    private var formattedAmount: String {
        guard let sats = amountInSats else { return "" }
        return BitcoinFormatter.shared.formatAmount(sats)
    }
    
    enum InvoiceState {
        case amountInput
        case generating
        case qrDisplay
    }
    
    var body: some View {
        ZStack {
            // Close button in top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("button_close")
                    .padding(4)
                    .buttonStyle(.plain)
                    .background(Color.black.opacity(0.15))
                    .clipShape(Circle())
                    .padding(.top, 30)
                    .padding(.trailing, 30)
                }
                Spacer()
            }
            .zIndex(1)
            
            // Main centered content (always centered vertically)
            VStack(spacing: 25) {
                // Header - context-aware
                HStack(alignment: .center) {
                    if invoiceState == .qrDisplay {
                        Text("Scan to Pay")
                            .font(.system(size: 36, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                    } else {
                        Text("Enter amount")
                            .font(.system(size: 36, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                
                // White square box
                ZStack {
                    if invoiceState == .amountInput {
                        // Glass effect when amount is entered
                        Rectangle()
                            .fill(.clear)
                            .frame(width: qrCodeSize(for: screenWidth),
                                   height: qrCodeSize(for: screenWidth))
                            .glassEffect(.clear, in: .rect(cornerRadius: 25))
                    } else {
                        // Solid white background for other states
                        RoundedRectangle(cornerRadius: 25)
                            .fill(.white)
                            .frame(width: qrCodeSize(for: screenWidth),
                                   height: qrCodeSize(for: screenWidth))
                    }
                    
                    switch invoiceState {
                    case .amountInput:
                        amountDisplayView
                    case .generating:
                        generatingView
                    case .qrDisplay:
                        qrDisplayView
                    }
                }
                
                // Error message or amount button (QR state)
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                } else if invoiceState == .qrDisplay {
                    // Tappable amount to edit
                    Button {
                        resetToAmountInput()
                    } label: {
                        HStack(spacing: 8) {
                            Text(formattedAmount)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                            Image(systemName: "pencil")
                                .font(.system(size: 19, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(25)
                    }
                } else {
                    Color.clear
                        .frame(height: 41)
                }
            }
            .padding(24)
            .frame(width: cardWidth(for: screenWidth))
            
            // Keypad overlay - Z-layer on top, bottom-aligned
            if invoiceState == .amountInput {
                VStack {
                    Spacer()
                    CustomNumericKeypad_iOS(amount: $amount) {
                        generateInvoice()
                    }
                    .frame(height: 120)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Views
    
    private var amountDisplayView: some View {
        VStack(spacing: 8) {
            if amount.isEmpty {
                Text("0")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 30)
            } else {
                Text(formattedAmount)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
            }
            
            Spacer()
        }
        .frame(width: qrCodeSize(for: screenWidth),
               height: qrCodeSize(for: screenWidth))
    }
    
    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.black)
            
            Text("Generating invoice...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: qrCodeSize(for: screenWidth),
               height: qrCodeSize(for: screenWidth))
    }
    
    private var qrDisplayView: some View {
        VStack(spacing: 0) {
            // QR Code - same size as BIP-21 page
            if let qrImage = qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: qrCodeSize(for: screenWidth),
                           height: qrCodeSize(for: screenWidth))
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.black)
                    .frame(width: qrCodeSize(for: screenWidth),
                           height: qrCodeSize(for: screenWidth))
            }
        }
        .frame(width: qrCodeSize(for: screenWidth),
               height: qrCodeSize(for: screenWidth))
    }
    
    // MARK: - Computed Properties
    
    private func qrCodeSize(for screenWidth: CGFloat) -> CGFloat {
        let size = screenWidth * 0.8
        return min(size, 400)
    }
    
    private func cardWidth(for screenWidth: CGFloat) -> CGFloat {
        return qrCodeSize(for: screenWidth) + 48
    }
    
    // MARK: - Actions
    
    private func generateInvoice() {
        guard let amountUInt64 = UInt64(amount), amountUInt64 > 0 else {
            errorMessage = "Invalid amount"
            return
        }
        
        guard let walletManager = walletManager else {
            errorMessage = "Wallet not available"
            return
        }
        
        errorMessage = nil
        invoiceState = .generating
        
        Task {
            do {
                let invoice = try await walletManager.getLightningInvoice(
                    amountSats: amountUInt64,
                    description: nil
                )
                
                await MainActor.run {
                    generatedInvoice = invoice
                    generateQRCode(from: invoice)
                    invoiceState = .qrDisplay
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate invoice: \(error.localizedDescription)"
                    invoiceState = .amountInput
                }
            }
        }
    }
    
    private func generateQRCode(from invoice: String) {
        qrImage = QRCodeGenerator.shared.generatePersonalizedQRCode(
            from: invoice,
            avatarData: userProfile?.avatarData
        )
    }
    
    private func resetToAmountInput() {
        // Clear state
        generatedInvoice = nil
        qrImage = nil
        errorMessage = nil
        invoiceState = .amountInput
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}
