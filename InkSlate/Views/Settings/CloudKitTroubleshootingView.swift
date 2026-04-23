//
//  CloudKitTroubleshootingView.swift
//  InkSlate
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct CloudKitTroubleshootingView: View {
    @State private var cloudKitStatus: CloudKitStatus = .unknown
    @State private var isChecking = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                            
                            Text("iCloud Sync Status")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text(statusDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.adaptiveSystemBackground)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                    
                    // Troubleshooting Steps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Troubleshooting Steps")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(troubleshootingSteps, id: \.title) { step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(step.number)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text(step.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.adaptiveSystemBackground)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: checkCloudKitStatus) {
                            HStack {
                                if isChecking {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                
                                Text(isChecking ? "Checking..." : "Check Status Again")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isChecking)
                        
                        Button(action: openSettings) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.adaptiveSystemBackground)
                            .foregroundColor(.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("iCloud Sync")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            checkCloudKitStatus()
        }
    }
    
    private var statusColor: Color {
        switch cloudKitStatus {
        case .available:
            return .green
        case .noAccount, .restricted, .temporarilyUnavailable:
            return .orange
        case .couldNotDetermine, .unknown, .error:
            return .red
        }
    }
    
    private var statusDescription: String {
        switch cloudKitStatus {
        case .available:
            return "iCloud sync is working properly. Your data will sync across all your devices."
        case .noAccount:
            return "No iCloud account is signed in. Please sign in to iCloud in Settings to enable sync."
        case .restricted:
            return "Your iCloud account is restricted. Check parental controls or account settings."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Your app will work offline until iCloud is available again."
        case .couldNotDetermine:
            return "Could not determine iCloud status. Please check your internet connection and try again."
        case .unknown:
            return "Checking iCloud status..."
        case .error:
            return "Error checking iCloud status"
        }
    }
    
    private var troubleshootingSteps: [TroubleshootingStep] {
        switch cloudKitStatus {
        case .noAccount:
            return [
                TroubleshootingStep(
                    number: 1,
                    title: "Sign in to iCloud",
                    description: "Go to Settings > Sign-In to your iPhone and sign in with your Apple ID"
                ),
                TroubleshootingStep(
                    number: 2,
                    title: "Enable iCloud Drive",
                    description: "In Settings > [Your Name] > iCloud, make sure iCloud Drive is turned on"
                ),
                TroubleshootingStep(
                    number: 3,
                    title: "Restart the app",
                    description: "Close and reopen InkSlate to retry CloudKit connection"
                )
            ]
        case .temporarilyUnavailable:
            return [
                TroubleshootingStep(
                    number: 1,
                    title: "Check internet connection",
                    description: "Make sure you have a stable internet connection"
                ),
                TroubleshootingStep(
                    number: 2,
                    title: "Wait and retry",
                    description: "iCloud services may be temporarily down. Try again in a few minutes"
                ),
                TroubleshootingStep(
                    number: 3,
                    title: "Check Apple System Status",
                    description: "Visit apple.com/support/systemstatus to check if iCloud services are down"
                )
            ]
        case .restricted:
            return [
                TroubleshootingStep(
                    number: 1,
                    title: "Check parental controls",
                    description: "If you're using a child account, check Screen Time restrictions"
                ),
                TroubleshootingStep(
                    number: 2,
                    title: "Verify account status",
                    description: "Make sure your Apple ID account is in good standing"
                ),
                TroubleshootingStep(
                    number: 3,
                    title: "Contact support",
                    description: "If the issue persists, contact Apple Support"
                )
            ]
        default:
            return [
                TroubleshootingStep(
                    number: 1,
                    title: "Check internet connection",
                    description: "Make sure you have a stable internet connection"
                ),
                TroubleshootingStep(
                    number: 2,
                    title: "Sign out and back in",
                    description: "Try signing out of iCloud and signing back in"
                ),
                TroubleshootingStep(
                    number: 3,
                    title: "Restart device",
                    description: "Restart your iPhone or iPad and try again"
                )
            ]
        }
    }
    
    private func checkCloudKitStatus() {
        isChecking = true
        Task {
            await PersistenceController.shared.checkCloudKitStatus()
            await MainActor.run {
                cloudKitStatus = PersistenceController.shared.syncStatus
                isChecking = false
            }
        }
    }
    
    private func openSettings() {
        #if canImport(UIKit)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

struct TroubleshootingStep {
    let number: Int
    let title: String
    let description: String
}

#Preview {
    CloudKitTroubleshootingView()
}
