import Foundation
import UserNotifications

// MARK: - UserDefaults keys (also listed in `InkSlateUserDefaultsKeys.all` for factory reset)

enum InkSlateNotificationPreferenceKeys {
    static let journalEnabled = "notifications.journal.enabled"
    static let journalHour = "notifications.journal.hour"
    static let journalMinute = "notifications.journal.minute"
    static let nudgeEnabled = "notifications.nudge.enabled"
    /// Legacy — random nudge no longer uses fixed time; keys kept for factory reset / migration
    static let nudgeHour = "notifications.nudge.hour"
    static let nudgeMinute = "notifications.nudge.minute"
    static let cookTimerEnabled = "notifications.cookTimer.enabled"
    static let nudgeLastScheduledFireTime = "notifications.nudge.lastScheduledFireTime"
}

enum InkSlateNotificationIdentifiers {
    static let journalDaily = "inkslate.notification.journal.daily"
    static let nudgeDaily = "inkslate.notification.nudge.daily"
    static let nudgeSlotPrefix = "inkslate.notification.nudge.slot."

    static func cookTimer(_ stepID: UUID) -> String {
        "inkslate.notification.recipeTimer.\(stepID.uuidString)"
    }
}

private enum InkSlateNotificationUserInfoKeys {
    static let deepLink = "deepLink"
}

@MainActor
final class InkSlateNotificationService {
    static let shared = InkSlateNotificationService()

    private let defaults = UserDefaults.standard

    private let captureNudgeRandomStartHour = 9
    private let captureNudgeRandomEndHour = 21
    private let legacyNudgeSlotCount = 14

    private init() {}

    // MARK: - Preferences

    var journalReminderEnabled: Bool {
        get { defaults.bool(forKey: InkSlateNotificationPreferenceKeys.journalEnabled) }
        set { defaults.set(newValue, forKey: InkSlateNotificationPreferenceKeys.journalEnabled) }
    }

    var journalReminderHour: Int {
        get {
            guard defaults.object(forKey: InkSlateNotificationPreferenceKeys.journalHour) != nil else { return 20 }
            let v = defaults.integer(forKey: InkSlateNotificationPreferenceKeys.journalHour)
            return (0...23).contains(v) ? v : 20
        }
        set { defaults.set(newValue, forKey: InkSlateNotificationPreferenceKeys.journalHour) }
    }

    var journalReminderMinute: Int {
        get {
            guard defaults.object(forKey: InkSlateNotificationPreferenceKeys.journalMinute) != nil else { return 0 }
            let v = defaults.integer(forKey: InkSlateNotificationPreferenceKeys.journalMinute)
            return (0...59).contains(v) ? v : 0
        }
        set { defaults.set(newValue, forKey: InkSlateNotificationPreferenceKeys.journalMinute) }
    }

    var captureNudgeEnabled: Bool {
        get { defaults.bool(forKey: InkSlateNotificationPreferenceKeys.nudgeEnabled) }
        set { defaults.set(newValue, forKey: InkSlateNotificationPreferenceKeys.nudgeEnabled) }
    }

    var cookTimerNotificationsEnabled: Bool {
        get {
            if defaults.object(forKey: InkSlateNotificationPreferenceKeys.cookTimerEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: InkSlateNotificationPreferenceKeys.cookTimerEnabled)
        }
        set { defaults.set(newValue, forKey: InkSlateNotificationPreferenceKeys.cookTimerEnabled) }
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func refreshRepeatingNotificationsFromDefaultsIfAuthorized() async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        await scheduleJournalAndNudgeFromDefaults()
    }

    func scheduleJournalAndNudgeFromDefaults() async {
        let center = UNUserNotificationCenter.current()
        await removeLegacyNudgeSlotNotifications(using: center)

        center.removePendingNotificationRequests(withIdentifiers: [InkSlateNotificationIdentifiers.journalDaily])

        if journalReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Daily journal"
            content.body = "Take a moment to reflect in InkSlate."
            content.sound = .default
            content.userInfo = [InkSlateNotificationUserInfoKeys.deepLink: "journal"]

            var components = DateComponents()
            components.hour = journalReminderHour
            components.minute = journalReminderMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: InkSlateNotificationIdentifiers.journalDaily,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }

        await rescheduleCaptureNudgeIfNeeded()
    }

    func rescheduleCaptureNudgeIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        await removeLegacyNudgeSlotNotifications(using: center)

        guard captureNudgeEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [InkSlateNotificationIdentifiers.nudgeDaily])
            defaults.removeObject(forKey: InkSlateNotificationPreferenceKeys.nudgeLastScheduledFireTime)
            return
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        if let existing = pending.first(where: { $0.identifier == InkSlateNotificationIdentifiers.nudgeDaily }),
           let calTrigger = existing.trigger as? UNCalendarNotificationTrigger,
           let next = calTrigger.nextTriggerDate(),
           next > Date().addingTimeInterval(30) {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [InkSlateNotificationIdentifiers.nudgeDaily])

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let lastFireTs = defaults.double(forKey: InkSlateNotificationPreferenceKeys.nudgeLastScheduledFireTime)
        let lastFireDate = Date(timeIntervalSince1970: lastFireTs)
        let nudgeAlreadyFiredThisCalendarDay = lastFireTs > 0
            && lastFireDate < now
            && calendar.isDate(lastFireDate, inSameDayAs: now)

        let fireDate: Date
        if nudgeAlreadyFiredThisCalendarDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86_400)
            fireDate = nextRandomCaptureNudgeFireDate(on: nextDay, calendar: calendar)
        } else {
            fireDate = nextRandomCaptureNudgeFireDate(from: now, calendar: calendar)
        }

        defaults.set(fireDate.timeIntervalSince1970, forKey: InkSlateNotificationPreferenceKeys.nudgeLastScheduledFireTime)

        let content = UNMutableNotificationContent()
        content.title = "InkSlate"
        content.body = "Come back to InkSlate — open the app and capture what’s on your mind."
        content.sound = .default
        content.userInfo = [InkSlateNotificationUserInfoKeys.deepLink: "notes"]

        let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        let request = UNNotificationRequest(
            identifier: InkSlateNotificationIdentifiers.nudgeDaily,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private func removeLegacyNudgeSlotNotifications(using center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let slotIds = pending.map(\.identifier).filter { $0.hasPrefix(InkSlateNotificationIdentifiers.nudgeSlotPrefix) }
        if !slotIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: slotIds)
        }
    }

    private func nextRandomCaptureNudgeFireDate(from now: Date, calendar: Calendar) -> Date {
        guard let todayStart = calendar.dateInterval(of: .day, for: now)?.start else {
            return now.addingTimeInterval(86_400)
        }
        let hour = Int.random(in: captureNudgeRandomStartHour...captureNudgeRandomEndHour)
        let minute = Int.random(in: 0...59)
        let todayCandidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: todayStart) ?? now
        if todayCandidate > now {
            return todayCandidate
        }
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return todayCandidate.addingTimeInterval(86_400)
        }
        let h2 = Int.random(in: captureNudgeRandomStartHour...captureNudgeRandomEndHour)
        let m2 = Int.random(in: 0...59)
        return calendar.date(bySettingHour: h2, minute: m2, second: 0, of: tomorrowStart)
            ?? tomorrowStart.addingTimeInterval(Double((h2 * 3600) + (m2 * 60)))
    }

    private func nextRandomCaptureNudgeFireDate(on dayStart: Date, calendar: Calendar) -> Date {
        let hour = Int.random(in: captureNudgeRandomStartHour...captureNudgeRandomEndHour)
        let minute = Int.random(in: 0...59)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(Double((hour * 3600) + (minute * 60)))
    }

    func cancelJournalAndNudgeNotifications() {
        let center = UNUserNotificationCenter.current()
        var ids = [InkSlateNotificationIdentifiers.journalDaily, InkSlateNotificationIdentifiers.nudgeDaily]
        ids += (0..<legacyNudgeSlotCount).map { "\(InkSlateNotificationIdentifiers.nudgeSlotPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Recipe timers

    func scheduleCookTimerNotificationIfNeeded(stepID: UUID, remainingSeconds: Int, title: String, body: String) async {
        guard cookTimerNotificationsEnabled else {
            cancelCookTimerNotification(stepID: stepID)
            return
        }
        guard remainingSeconds > 0 else {
            cancelCookTimerNotification(stepID: stepID)
            return
        }

        var status = await authorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
            status = await authorizationStatus()
        }
        guard status == .authorized || status == .provisional else {
            return
        }

        let identifier = InkSlateNotificationIdentifiers.cookTimer(stepID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [InkSlateNotificationUserInfoKeys.deepLink: "recipes"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
        }
    }

    func cancelCookTimerNotification(stepID: UUID) {
        let identifier = InkSlateNotificationIdentifiers.cookTimer(stepID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllCookTimerNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix("inkslate.notification.recipeTimer.") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Response handling (from AppDelegate)

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let request = response.notification.request
        let identifier = request.identifier

        let deepLink: String?
        if let fromInfo = request.content.userInfo[InkSlateNotificationUserInfoKeys.deepLink] as? String {
            deepLink = fromInfo
        } else if identifier == InkSlateNotificationIdentifiers.journalDaily {
            deepLink = "journal"
        } else if identifier == InkSlateNotificationIdentifiers.nudgeDaily
            || identifier.hasPrefix(InkSlateNotificationIdentifiers.nudgeSlotPrefix) {
            deepLink = "notes"
        } else if identifier.hasPrefix("inkslate.notification.recipeTimer.") {
            deepLink = "recipes"
        } else {
            deepLink = nil
        }

        guard let deepLink else { return }

        let menu: MenuViewType?
        switch deepLink {
        case "journal": menu = .journal
        case "notes": menu = .notes
        case "recipes": menu = .recipes
        default: menu = nil
        }

        guard let menu else { return }

        Task { @MainActor in
            SharedStateManager.shared.requestOpenMenu(menu)
        }
    }
}
