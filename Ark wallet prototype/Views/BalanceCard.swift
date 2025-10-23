//
//  BalanceCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct BalanceCard: View {
    let totalBalance: TotalBalanceModel
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your Balance")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                
                Spacer()
                
                Text("₿ \(totalBalance.grandTotalSat.formatted())")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Absolutely positioned pending indicator
            if totalBalance.hasPendingBalance {
                VStack(alignment: .trailing) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .aspectRatio(3/2, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .overlay {
                    Image("card")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
        }
        .cornerRadius(15)
    }
}

#Preview {
    BalanceCard(totalBalance: TotalBalanceModel.empty)
        .frame(width: 180, height: 120)
}
