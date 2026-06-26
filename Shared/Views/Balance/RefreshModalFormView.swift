//
//  RefreshModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import ArkeUI
import Bark

struct RefreshModalFormView: View {
    @Environment(WalletManager.self) private var walletManager
    var isLoading: Bool = false
    var amountToRefresh: Int?
    var vtxoIdsToRefresh: [String] = []
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "poolside", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("button_close")
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .padding(.trailing, 8)
                    .padding(.top, 12)
                    .disabled(isLoading)
                }
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "poolside", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(15)
                .clipped()
            #endif
            
            /*
            Image("board") // Using same image as boarding for now
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("button_close")
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .padding(.trailing, 8)
                    .padding(.top, 12)
                }
            */
            
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("action_refresh_payments")
                        .font(.system(.title, design: .serif))
                    
                    Text("desc_maintenance_task")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal)
                    
                    if vtxoIdsToRefresh.isEmpty {
                        Text("balance_no_vtxos_to_refresh")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                    } else if let amount = amountToRefresh, amount > 0 {
                        VStack(spacing: 8) {
                            Text("balance_amount_refreshing")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(BitcoinFormatter.shared.formatAmount(amount))
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 8) {
                                Text("balance_amount_locked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                // Fee estimate
                                if !vtxoIdsToRefresh.isEmpty {
                                    FeeEstimateView(input: vtxoIdsToRefresh) { vtxoIds in
                                        let estimate = try await walletManager.estimateRefreshFee(vtxoIds: vtxoIds)
                                        return estimate.feeSats
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        #if os(iOS)
                        .background(Color(.systemGray6))
                        #else
                        .background(Color(white: 0.949))
                        #endif
                        .cornerRadius(12)
                        .padding(.top, 8)
                    }
                }
            }
            
            Button {
                onConfirm()
            } label: {
                HStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                    }
                    Text(isLoading ? String(localized: "status_refreshing") : "Start")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .disabled(isLoading || vtxoIdsToRefresh.isEmpty)
        }
        .padding()
    }
}
