//
//  BalanceDetailCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct BalanceDetailCard: View {
    let title: String
    let description: String
    let spendable: Int
    let pending: Int
    let total: Int
    let color: Color
    let imageName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Image(imageName)
                    .resizable()
                    .frame(width: 75, height: 75)
                    .cornerRadius(15)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.regular)
                        .font(.system(size: 30, design: .serif))
                    
                    Text(description)
                        .font(.footnote)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                
                HStack {
                    Text("Available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(spendable.formatted()) ₿")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Pending")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(pending.formatted()) ₿")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Divider()
                
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("\(total.formatted()) ₿")
                        .font(.headline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        BalanceDetailCard(
            title: "Payments balance",
            description: "Fast & low fees · Ark network",
            spendable: 150000,
            pending: 25000,
            total: 175000,
            color: .orange,
            imageName: "wallet"
        )
        
        BalanceDetailCard(
            title: "Savings balance",
            description: "Best security · Bitcoin network",
            spendable: 75000,
            pending: 0,
            total: 75000,
            color: .blue,
            imageName: "safe"
        )
    }
    .padding()
}
