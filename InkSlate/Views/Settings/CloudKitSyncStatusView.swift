//
//  CloudKitSyncStatusView.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/27/25.
//

import SwiftUI

// MARK: - CloudKit Sync Banner

struct CloudKitSyncStatusView: View {
    @ObservedObject var persistence: PersistenceController
    @State private var showDetails = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: persistence.syncStatus.systemImage)
                    .foregroundColor(statusColor)
                    .font(.caption)
                    .accessibilityHidden(true)
                
                if persistence.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing with iCloud...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let lastSync = persistence.lastSyncDate {
                    Text("Last sync: \(timeAgoString(from: lastSync))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !persistence.syncStatus.isAvailable {
                    Button {
                        showDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("CloudKit troubleshooting info")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .animation(.easeInOut(duration: 0.25), value: persistence.isSyncing)
            .accessibilityLabel("iCloud sync status: \(statusText)")
            
            Divider()
                .padding(.horizontal, 16)
                .opacity(colorScheme == .dark ? 0.15 : 0.25)
        }
        .sheet(isPresented: $showDetails) {
            CloudKitTroubleshootingView()
        }
    }
    
    private var statusColor: Color {
        switch persistence.syncStatus {
        case .available: return persistence.isSyncing ? .blue : .green
        case .noAccount, .temporarilyUnavailable: return .orange
        case .restricted, .error: return .red
        case .unknown, .couldNotDetermine: return .gray
        }
    }
    
    private var backgroundColor: Color {
        switch persistence.syncStatus {
        case .available: return .clear
        case .noAccount, .temporarilyUnavailable, .restricted, .error:
            return Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .unknown, .couldNotDetermine: return .clear
        }
    }
    
    private var statusText: String {
        switch persistence.syncStatus {
        case .available: return "Ready to sync"
        case .noAccount: return "Not signed in to iCloud"
        case .temporarilyUnavailable: return "Offline – will sync when online"
        case .restricted: return "iCloud restricted"
        case .error: return "Sync error"
        case .unknown, .couldNotDetermine: return "Checking..."
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }
}

// MARK: - Troubleshooting Sheet
// Note: CloudKitTroubleshootingView is defined in CloudKitTroubleshootingView.swift

// MARK: - Compact Toolbar Version

struct CompactSyncIndicator: View {
    @ObservedObject var persistence: PersistenceController
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: persistence.syncStatus.systemImage)
                .foregroundColor(statusColor)
                .font(.caption)
            
            if persistence.isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .accessibilityLabel(persistence.syncStatus.description)
    }
    
    private var statusColor: Color {
        switch persistence.syncStatus {
        case .available: return persistence.isSyncing ? .blue : .green
        case .noAccount, .temporarilyUnavailable: return .orange
        case .restricted, .error: return .red
        case .unknown, .couldNotDetermine: return .gray
        }
    }
}
