//
//  BalanceDetailCard.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI

struct BalanceDetailCard: View {
    let title: String
    let description: String
    let spendable: Int?
    let pending: Int?
    let total: Int?
    let color: Color
    let imageName: String
    let pendingItems: [(label: String, amount: Int)]?
    
    @State private var isPendingExpanded: Bool = false
    
    private var imageSize: CGFloat {
        #if os(macOS)
        return 150
        #else
        return 80
        #endif
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(imageName)
                .resizable()
                .frame(width: imageSize, height: imageSize)
                .cornerRadius(15)
                .shadow(radius: 10, x: 0, y: 5)
            
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.regular)
                        .font(.system(size: 30, design: .serif))
                        .foregroundColor(.white)
                    
                    /*
                    Text(description)
                        .font(.footnote)
                    */
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "status_available", defaultValue: "Available"))
                                .font(.body)
                                .foregroundColor(.white.opacity(0.75))
                            Spacer()
                            if let spendable = spendable {
                                Text("\(spendable.formatted()) ₿")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            } else {
                                Text(L10n.symbolEmDash)
                                    .font(.body)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        if let items = pendingItems, !items.isEmpty {
                            if isPendingExpanded {
                                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                    HStack {
                                        Text(item.label)
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.75))
                                        Spacer()
                                        Text("\(item.amount.formatted()) ₿")
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation {
                                            isPendingExpanded = false
                                        }
                                    }
                                }
                            } else {
                                HStack {
                                    Text(L10n.statusPending)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.75))
                                    Spacer()
                                    if let pending = pending {
                                        Text("\(pending.formatted()) ₿")
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                    } else {
                                        Text(L10n.symbolEmDash)
                                            .font(.body)
                                            .foregroundColor(.white)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        isPendingExpanded = true
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(L10n.statusPending)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                                if let pending = pending {
                                    Text("\(pending.formatted()) ₿")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                } else {
                                    Text(L10n.symbolEmDash)
                                        .font(.body)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .overlay(.white.opacity(0.3))
                        .padding(.vertical, 5)
                    
                    HStack {
                        Text(String(localized: "label_total", defaultValue: "Total"))
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        if let total = total {
                            Text("\(total.formatted()) ₿")
                                .font(.title2)
                                .foregroundColor(.white)
                        } else {
                            Text(L10n.symbolEmDash)
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
    }
}
