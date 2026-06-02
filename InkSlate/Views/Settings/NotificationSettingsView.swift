import SwiftUI
import UserNotifications
import UIKit

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
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await refreshAuthorizationStatus()
                    await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                }
            }
            #endif
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
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } footer: {
            Text("Journal uses a daily time you pick. Capture nudge is once per day at a random time while InkSlate is installed; the next day is scheduled when you open the app. Cook timers can alert when the app is in the background.")
        }
    }

    private var cookTimersSection: some View {
        Section("Cook timers") {
            Toggle("Notify when a timer finishes", isOn: $cookTimerNotify)
                .tint(DesignSystem.Colors.accent)
        }
    }

    private var journalSection: some View {
        Section("Daily journal") {
            Toggle("Reminder", isOn: $journalEnabled)
                .tint(DesignSystem.Colors.accent)
            DatePicker(
                "Time",
                selection: journalTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .disabled(!journalEnabled)
        }
    }

    private var nudgeSection: some View {
        Section {
            Toggle("Reminder", isOn: $nudgeEnabled)
                .tint(DesignSystem.Colors.accent)
        } header: {
            Text("Capture nudge")
        } footer: {
            Text("About once per day at a random time between 9:00 and 21:00. After you see a nudge, the next one is planned the next time you open InkSlate.")
        }
    }

    private var statusLabel: String {
        switch authorizationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Off in Settings"
        case .notDetermined: return "Not asked"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var journalTimeBinding: Binding<Date> {
        Binding(
            get: { Self.dateFrom(hour: journalHour, minute: journalMinute) },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                journalHour = parts.hour ?? 0
                journalMinute = parts.minute ?? 0
            }
        )
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await InkSlateNotificationService.shared.authorizationStatus()
    }

    private func handleJournalToggle(_ on: Bool) async {
        if on {
            let ok = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
            if !ok {
                await MainActor.run { journalEnabled = false }
                return
            }
        }
        await InkSlateNotificationService.shared.scheduleJournalAndNudgeFromDefaults()
    }

    private func handleNudgeToggle(_ on: Bool) async {
        if on {
            let ok = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
            if !ok {
                await MainActor.run { nudgeEnabled = false }
                return
            }
        }
        await InkSlateNotificationService.shared.scheduleJournalAndNudgeFromDefaults()
    }

    private func handleCookTimerToggle(_ on: Bool) async {
        if on {
            _ = await InkSlateNotificationService.shared.requestAuthorization()
            await refreshAuthorizationStatus()
        } else {
            await InkSlateNotificationService.shared.cancelAllCookTimerNotifications()
        }
    }

    private func rescheduleRepeatingIfAllowed() async {
        let status = await InkSlateNotificationService.shared.authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        await InkSlateNotificationService.shared.scheduleJournalAndNudgeFromDefaults()
    }
}
