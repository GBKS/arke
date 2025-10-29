//
//  OffboardingModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI

struct OffboardingModalFormView: View {
    let vtxos: [VTXOModel]
    @Binding var selectedVTXOs: Set<String>
    let errorMessage: String?
    let isLoading: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 25) {
            Image("offboard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: 150, maxHeight: .infinity)
                .cornerRadius(15)
                .clipped()
            
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer to savings")
                        .font(.system(size: 24, design: .serif))
                    
                    Text("Move funds to the Bitcoin network for the best security.")
                        .font(.default)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                // VTXO Selection List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select coins to transfer")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    if isLoading {
                        SkeletonLoader(
                            itemCount: 3,
                            itemHeight: 20,
                            spacing: 10,
                            cornerRadius: 15
                        )
                        .padding(.top, 5)
                    } else if vtxos.isEmpty {
                        Text("No coins available")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(vtxos, id: \.id) { vtxo in
                                SelectableVTXORowView(
                                    vtxo: vtxo,
                                    isSelected: selectedVTXOs.contains(vtxo.id),
                                    onToggle: {
                                        if selectedVTXOs.contains(vtxo.id) {
                                            selectedVTXOs.remove(vtxo.id)
                                        } else {
                                            selectedVTXOs.insert(vtxo.id)
                                        }
                                    }
                                )
                                
                                if vtxo.id != vtxos.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    onConfirm()
                }
                .disabled(isLoading || selectedVTXOs.isEmpty)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedVTXOs: Set<String> = []
    
    OffboardingModalFormView(
        vtxos: VTXOModel.mockVTXOs(),
        selectedVTXOs: $selectedVTXOs,
        errorMessage: nil,
        isLoading: false,
        onConfirm: {},
        onCancel: {}
    )
}
