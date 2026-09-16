import SwiftUI
@preconcurrency import EventKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Sheet/detail selection wrapper — avoids retroactive `EKEvent: Identifiable` (can trap at launch on newer SDKs).
struct IdentifiedCalendarEvent: Identifiable {
    let event: EKEvent
    var id: String {
        let sid = event.eventIdentifier ?? ""
        let start = event.startDate?.timeIntervalSince1970 ?? 0
        return "\(sid)-\(start)"
    }
}

#if canImport(UIKit)
func inkEventCalendarColor(for event: EKEvent) -> Color {
    guard let cg = event.calendar.cgColor else { return .blue }
    return Color(UIColor(cgColor: cg))
}
#else
func inkEventCalendarColor(for event: EKEvent) -> Color { .blue }
#endif

// MARK: - Calendar Manager
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var selectedDate = Date()
    @Published var events: [EKEvent] = []
    @Published private(set) var eventsByDay: [Date: [EKEvent]] = [:]
    @Published var allCalendars: [EKCalendar] = []
    @Published var selectedCalendars: Set<String> = []
    @Published var isLoading = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var searchQuery: String = ""

    let store = EKEventStore()
    private let selectedCalendarsKey = "selectedCalendarIdentifiers"
    private var reloadTask: Task<Void, Never>?
    private var storeChangeTask: Task<Void, Never>?
    private var loadToken = UUID()

    private var dayCalendar: Calendar { Calendar.current }

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if let saved = UserDefaults.standard.array(forKey: selectedCalendarsKey) as? [String] {
            selectedCalendars = Set(saved)
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStoreChanged()
            }
        }
    }

    /// Debounce iCloud/Calendar sync bursts so the UI doesn’t thrash mid-update.
    private func handleStoreChanged() {
        storeChangeTask?.cancel()
        storeChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadEvents()
        }
    }

    var canReadEvents: Bool {
        authorizationStatus == .fullAccess
    }

    var canWriteEvents: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Requests full calendar access only while status is still `.notDetermined`.
    /// After the user chooses (full, write-only, or deny), the system will not show the dialog again —
    /// upgrades must go through Settings. Avoid calling `requestFullAccessToEvents()` for `.writeOnly`
    /// or it can keep re-prompting.
    func requestAccess() async {
        refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else {
            if canReadEvents {
                await reloadEverything()
            }
            return
        }
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            #if DEBUG
            print("Calendar access request failed: \(error.localizedDescription)")
            #endif
        }
        refreshAuthorizationStatus()
        if canReadEvents {
            await reloadEverything()
        }
    }

    /// Re-check TCC status after the user may have changed it in Settings (no system prompt).
    func refreshAccessFromSettings() {
        refreshAuthorizationStatus()
        if canReadEvents {
            reloadEvents()
        }
    }

    private func reloadEverything() async {
        loadCalendars()
        try? await Task.sleep(nanoseconds: 100_000_000)
        loadEvents(center: selectedDate)
    }

    func loadCalendars() {
        allCalendars = store.calendars(for: .event)
        if selectedCalendars.isEmpty {
            selectedCalendars = Set(allCalendars.map { $0.calendarIdentifier })
            saveCalendarSelection()
        }
    }

    func loadEvents(center: Date? = nil) {
        guard canReadEvents else {
            events = []
            eventsByDay = [:]
            isLoading = false
            return
        }

        reloadTask?.cancel()
        let token = UUID()
        loadToken = token

        isLoading = true

        let base = center ?? selectedDate
        let cal = dayCalendar
        let startOfBase = cal.startOfDay(for: base)
        let startDate = cal.date(byAdding: .month, value: -18, to: startOfBase) ?? startOfBase
        let endDate = cal.date(byAdding: .month, value: 18, to: startOfBase) ?? startOfBase

        let visibleCalendarIDs: [String] = selectedCalendars.isEmpty
            ? allCalendars.map(\.calendarIdentifier)
            : allCalendars.compactMap { selectedCalendars.contains($0.calendarIdentifier) ? $0.calendarIdentifier : nil }

        guard !visibleCalendarIDs.isEmpty else {
            events = []
            eventsByDay = [:]
            isLoading = false
            return
        }

        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let calendars = visibleCalendarIDs.compactMap { self.store.calendar(withIdentifier: $0) }
            let predicate = self.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
            let fetched = self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            let grouped = Self.groupEventsByDay(fetched, calendar: cal)

            guard !Task.isCancelled, self.loadToken == token else { return }
            self.events = fetched
            self.eventsByDay = grouped
            self.isLoading = false
        }
    }

    func eventsForDay(_ date: Date) -> [EKEvent] {
        let dayStart = dayCalendar.startOfDay(for: date)
        guard let list = eventsByDay[dayStart], !list.isEmpty else { return [] }
        var seen = Set<String>()
        return list.filter { event in
            let key = "\(event.eventIdentifier ?? "")-\(event.startDate?.timeIntervalSince1970 ?? 0)"
            return seen.insert(key).inserted
        }
    }

    /// Map an EventKit all-day timestamp to a local day key.
    /// EventKit stores floating all-day values as GMT civil midnights after save.
    static func allDayCivilDay(from date: Date, displayCalendar cal: Calendar) -> Date {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let ymd = gmt.dateComponents([.year, .month, .day], from: date)
        return cal.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day))
            ?? cal.startOfDay(for: date)
    }

    private static func groupEventsByDay(_ events: [EKEvent], calendar cal: Calendar) -> [Date: [EKEvent]] {
        var dict: [Date: [EKEvent]] = [:]

        for event in events {
            if event.isAllDay {
                // EventKit all-day end is exclusive (often start+1 day after save, even if you saved end == start).
                let start = allDayCivilDay(from: event.startDate, displayCalendar: cal)
                let endExclusive = allDayCivilDay(from: event.endDate, displayCalendar: cal)
                if endExclusive <= start {
                    dict[start, default: []].append(event)
                } else {
                    var d = start
                    while d < endExclusive {
                        dict[d, default: []].append(event)
                        guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                        d = next
                    }
                }
            } else {
                // Timed events: walk days with exclusive end semantics so an event that
                // ends exactly at midnight does not paint the following day.
                var d = cal.startOfDay(for: event.startDate)
                while true {
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: d) ?? d
                    if event.startDate < dayEnd && event.endDate > d {
                        dict[d, default: []].append(event)
                    }
                    guard event.endDate > dayEnd else { break }
                    guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                    d = next
                }
            }
        }

        for (k, v) in dict {
            dict[k] = v.sorted { $0.startDate < $1.startDate }
        }
        return dict
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        if selectedCalendars.contains(calendar.calendarIdentifier) {
            selectedCalendars.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendars.insert(calendar.calendarIdentifier)
        }
        saveCalendarSelection()
        loadEvents(center: selectedDate)
    }

    private func saveCalendarSelection() {
        UserDefaults.standard.set(Array(selectedCalendars), forKey: selectedCalendarsKey)
    }

    func reloadEvents() {
        loadCalendars()
        loadEvents(center: selectedDate)
    }

    func deleteEvent(_ event: EKEvent) {
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            reloadEvents()
        } catch {
        }
    }
}
