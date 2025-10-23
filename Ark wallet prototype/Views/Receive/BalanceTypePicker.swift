//
//  BalanceTypePicker.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import SwiftUI

struct BalanceTypePicker: View {
    @Binding var selectedBalance: ReceiveView.BalanceType
    @State private var showingBalancePicker = false
    
    var body: some View {
        Button {
            showingBalancePicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedBalance.rawValue)
                    .font(.body)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingBalancePicker, arrowEdge: .bottom) {
            balancePickerPopover
        }
    }
    
    @ViewBuilder
    private var balancePickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ReceiveView.BalanceType.allCases, id: \.self) { balanceType in
                balanceTypeRow(for: balanceType)
                
                if balanceType != ReceiveView.BalanceType.allCases.last {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: 300)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 8)
    }
    
    @ViewBuilder
    private func balanceTypeRow(for balanceType: ReceiveView.BalanceType) -> some View {
        Button {
            showingBalancePicker = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    selectedBalance = balanceType
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(balanceType.rawValue)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(balanceType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedBalance == balanceType {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedBalance == balanceType ?
                Color.blue.opacity(0.1) :
                Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selectedBalance: ReceiveView.BalanceType = .payments
    
    BalanceTypePicker(selectedBalance: $selectedBalance)
        .padding()
        .frame(width: 400, height: 200)
}