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
        case .available:
            return persistence.isSyncing ? "Syncing with iCloud" : "Backed up to iCloud"
        case .noAccount: return "Not signed in — changes may not be backed up"
        case .temporarilyUnavailable: return "Offline — changes stay on this device until online"
        case .restricted: return "iCloud restricted — data may not be backed up"
        case .error: return "Sync error — data may not be backed up"
        case .unknown, .couldNotDetermine: return "Checking iCloud..."
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

// MARK: - Global backup warning (shown when iCloud is unavailable)

struct SyncBackupWarningBanner: View {
    @ObservedObject var persistence: PersistenceController
    @State private var showTroubleshooting = false

    var body: some View {
        if persistence.syncStatus.isDefinitivelyUnavailable {
            Button {
                showTroubleshooting = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not backed up to iCloud")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text(backupDetail)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("iCloud backup unavailable. \(backupDetail)")
            .sheet(isPresented: $showTroubleshooting) {
                CloudKitTroubleshootingView()
            }
        }
    }

    private var backupDetail: String {
        switch persistence.syncStatus {
        case .noAccount:
            return "Sign into iCloud on this device to sync notes, journals, and other data across your Apple devices."
        case .temporarilyUnavailable:
            return "You're offline or iCloud is temporarily unavailable. New changes exist only on this device until sync resumes."
        case .restricted:
            return "iCloud access is restricted on this device. Open Settings → iCloud Sync for help."
        case .error:
            return "InkSlate couldn't reach iCloud. Your data on this device is safe, but may not be backed up yet."
        case .available, .unknown, .couldNotDetermine:
            return ""
        }
    }
}

// MARK: - Troubleshooting Sheet

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
