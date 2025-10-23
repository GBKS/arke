//
//  SelectableVTXORowView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct SelectableVTXORowView: View {
    let vtxo: VTXOModel
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .imageScale(.large)
                    
                    HStack(spacing: 4) {                        
                        // Amount and state
                        VStack(alignment: .leading) {
                            Text(vtxo.formattedAmount)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                            
                        Spacer()
                            
                        Text(vtxo.state.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(stateBackgroundColor)
                            .foregroundColor(stateTextColor)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private var stateBackgroundColor: Color {
        switch vtxo.state {
        case .unregisteredBoard:
            return .orange.opacity(0.2)
        case .registeredBoard:
            return .green.opacity(0.2)
        case .spent:
            return .gray.opacity(0.2)
        case .pending:
            return .blue.opacity(0.2)
        case .spendable:
            return .green.opacity(0.3)
        }
    }
    
    private var stateTextColor: Color {
        switch vtxo.state {
        case .unregisteredBoard:
            return .orange
        case .registeredBoard:
            return .green
        case .spent:
            return .gray
        case .pending:
            return .blue
        case .spendable:
            return .green
        }
    }
}

#Preview {
    VStack {
        SelectableVTXORowView(
            vtxo: VTXOModel.mockVTXOs()[0],
            isSelected: false,
            onToggle: {}
        )
        SelectableVTXORowView(
            vtxo: VTXOModel.mockVTXOs()[1],
            isSelected: true,
            onToggle: {}
        )
    }
    .padding()
}
