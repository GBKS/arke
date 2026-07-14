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
                Text("settings_make_this_device_secondary")
                    .font(.title2.bold())

                // Explanation
                Text("settings_make_secondary_help")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Info box
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("settings_after_confirming", systemImage: "info.circle")
                            .font(.body)
                        Text("settings_make_secondary_step_1")
                        Text("settings_make_secondary_step_2")
                        Text("settings_make_secondary_step_3")
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
                            Text("settings_make_secondary")
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
                        Text("button_cancel")
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
            .navigationTitle("section_device_role")
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
                Text("settings_make_this_device_primary")
                    .font(.title2.bold())

                // Explanation
                Text("settings_make_primary_help")
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
                            Text("settings_make_primary")
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
                        Text("button_cancel")
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
            .navigationTitle("section_device_role")
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
