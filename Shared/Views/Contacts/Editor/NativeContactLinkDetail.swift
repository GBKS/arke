//
//  NativeContactLinkDetail.swift
//  Arké
//
//  Created by Christoph on 11/11/25.
//

import SwiftUI
import ArkeUI

/// Detailed view showing native contact link status with refresh option
struct NativeContactLinkDetail: View {
    let contact: ContactModel
    let onRefresh: () -> Void
    let onUnlink: () -> Void
    let onLink: () -> Void
    
    @State private var isRefreshing = false
    
    var body: some View {
        if contact.isLinkedToNativeContact {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.Arke.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("status_linked_contact")
                            .font(.body)
                        
                        if let lastSynced = contact.lastSyncedFromNative {
                            Text("Last synced \(lastSynced, formatter: relativeDateFormatter)")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        isRefreshing = true
                        onRefresh()
                        // Reset after a delay
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            isRefreshing = false
                        }
                    }) {
                        Text("button_refresh")
                            .font(.subheadline)
                    }
                    .disabled(isRefreshing)
                    
                    Button(role: .destructive, action: onUnlink) {
                        Text("button_unlink")
                            .font(.subheadline)
                    }
                    
                    Spacer()
                }
                .padding(.leading, 25)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            HStack {                
                Button(action: {
                    onLink()
                }) {
                    Text("action_link_contact")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
    }
    
    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }
}
