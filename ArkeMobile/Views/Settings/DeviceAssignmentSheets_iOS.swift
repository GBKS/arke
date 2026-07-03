import SwiftUI
import ArkeUI

/// Sheet for demoting current device from primary to secondary
struct DemoteDeviceSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.deviceRegistrationService) private var deviceService
    @State private var isProcessing = false
    @State private var error: String?
    var onSuccess: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Arke.blue)

                // Title
                Text("Make This Device Secondary?")
                    .font(.title2.bold())

                // Explanation
                Text("This device will switch to view-only mode. Make sure you have your other device ready to make it primary.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Info box
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("After confirming:", systemImage: "info.circle")
                            .font(.body)
                        Text("1. This device becomes view-only")
                        Text("2. Open your other device")
                        Text("3. Make that device primary")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.Arke.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: performDemotion) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Make Secondary")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                    .disabled(isProcessing)

                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                        
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Device Role")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func performDemotion() {
        Task {
            isProcessing = true
            error = nil

            do {
                try await deviceService.demoteThisDevice()

                // Success - dismiss sheet and notify parent
                await MainActor.run {
                    isPresented = false
                    onSuccess?()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

/// Sheet for promoting current device from secondary to primary
struct PromoteDeviceSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.deviceRegistrationService) private var deviceService
    @State private var isProcessing = false
    @State private var error: String?
    var onSuccess: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Arke.green)

                // Title
                Text("Make This Device Primary?")
                    .font(.title2.bold())

                // Explanation
                Text("This device will become your active wallet, able to send and receive payments.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.Arke.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: performPromotion) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Make Primary")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color.Arke.gold4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                    .disabled(isProcessing)
                    
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                        
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Device Role")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func performPromotion() {
        Task {
            isProcessing = true
            error = nil

            do {
                try await deviceService.promoteThisDeviceToPrimary()

                // Success - dismiss sheet and notify parent
                await MainActor.run {
                    isPresented = false
                    onSuccess?()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
