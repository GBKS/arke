//
//  ManualBackupView_iOS.swift
//  Arké
//
//  Created by Christoph on 5/11/26.
//

import SwiftUI
import ArkeUI

struct ManualBackupView_iOS: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("settings_offline_backup_help")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Recovery Phrase
                VStack {
                    NavigationLink(destination: RecoveryPhraseView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.Arke.blue)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings_recovery_phrase")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("action_view_backup")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    NavigationLink(destination: BackupStatusSectionView_iOS()) {
                        HStack(spacing: 12) {
                            Image(systemName: "tablecells.fill")
                                .foregroundColor(.Arke.teal)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings_backup_file")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("settings_required_to_recover_funds")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("settings_manual_backup")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Supporting Views

struct RecoveryPhraseView: View {
    var body: some View {
        RecoveryPhraseSettingView()
            .padding()
    }
}
