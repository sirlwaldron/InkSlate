import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(InkSlateNotificationPreferenceKeys.journalEnabled) private var journalEnabled = false
    @AppStorage(InkSlateNotificationPreferenceKeys.journalHour) private var journalHour = 20
    @AppStorage(InkSlateNotificationPreferenceKeys.journalMinute) private var journalMinute = 0

    @AppStorage(InkSlateNotificationPreferenceKeys.nudgeEnabled) private var nudgeEnabled = false

    @AppStorage(InkSlateNotificationPreferenceKeys.cookTimerEnabled) private var cookTimerNotify = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        notificationList
            .navigationTitle("Notifications")
            .inlineNavigationTitle()
            #if os(iOS)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            #else
            .inkSlateMacListLayout()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await refreshAuthorizationStatus()
                await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
            }
            .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.willEnterForeground)) { _ in
                Task {
                    await refreshAuthorizationStatus()
                    await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                }
            }
            .onChange(of: journalEnabled) { _, on in
                Task { await handleJournalToggle(on) }
            }
            .onChange(of: nudgeEnabled) { _, on in
                Task { await handleNudgeToggle(on) }
            }
            .onChange(of: journalHour) { _, _ in Task { await rescheduleRepeatingIfAllowed() } }
            .onChange(of: journalMinute) { _, _ in Task { await rescheduleRepeatingIfAllowed() } }
            .onChange(of: cookTimerNotify) { _, on in
                Task { await handleCookTimerToggle(on) }
            }
    }

    private var notificationList: some View {
        List {
            permissionSection
            cookTimersSection
            journalSection
            nudgeSection
        }
    }

    private var permissionSection: some View {
        Section {
            HStack {
                Text("Permission")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .font(DesignSystem.Typography.subheadline)
            }
            if authorizationStatus == .notDetermined {
                Button("Enable Notifications") {
                    Task {
                        _ = await InkSlateNotificationService.shared.requestAuthorization()
                        await refreshAuthorizationStatus()
                        await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                    }
                }
            } else if authorizationStatus == .denied {
                Button("Open Settings") {
                    openSystemNotificationSettings()
                }
            }
        } footer: {
            Text("Journal uses a daily time you pick. Capture nudge is once per day at a random time while InkSlate is installed; the next day is scheduled when you open the app. Cook timers can alert when the app is in the background.")
        }
    }

    private func openSystemNotificationSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private var cookTimersSection: some View {
        Section("Cook timers") {
            Toggle("Notify when a timer finishes", isOn: $cookTimerNotify)
                .tint(DesignSystem.Colors.accent)
        }
    }

    private var journalSection: some View {
        Section {
            Toggle("Daily journal reminder", isOn: $journalEnabled)
                .tint(DesignSystem.Colors.accent)
            if journalEnabled {
                DatePicker(
                    "Reminder time",
                    selection: journalTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Journal")
        }
    }

    private var nudgeSection: some View {
        Section {
            Toggle("Capture nudge", isOn: $nudgeEnabled)
                .tint(DesignSystem.Colors.accent)
        } footer: {
            Text("A gentle once-per-day reminder to capture a thought in Notes.")
        }
    }

    private var journalTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = journalHour
                components.minute = journalMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                journalHour = components.hour ?? 20
                journalMinute = components.minute ?? 0
            }
        )
    }

    private var statusLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not set"
        @unknown default: return "Unknown"
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
    }

    private func handleJournalToggle(_ enabled: Bool) async {
        if enabled {
            let granted = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
            guard granted else {
                await MainActor.run { journalEnabled = false }
                return
            }
        }
        await rescheduleRepeatingIfAllowed()
    }

    private func handleNudgeToggle(_ enabled: Bool) async {
        if enabled {
            let granted = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
            guard granted else {
                await MainActor.run { nudgeEnabled = false }
                return
            }
        }
        await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
    }

    private func handleCookTimerToggle(_ enabled: Bool) async {
        if enabled {
            _ = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
        }
    }

    private func rescheduleRepeatingIfAllowed() async {
        await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
    }
}
