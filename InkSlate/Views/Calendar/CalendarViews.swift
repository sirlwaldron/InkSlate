import SwiftUI
@preconcurrency import EventKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - EKEvent Extension
extension EKEvent: @retroactive Identifiable {
    public var id: String { eventIdentifier }
}

#if canImport(UIKit)
private func inkEventCalendarColor(for event: EKEvent) -> Color {
    guard let cg = event.calendar.cgColor else { return .blue }
    return Color(UIColor(cgColor: cg))
}
#else
private func inkEventCalendarColor(for event: EKEvent) -> Color { .blue }
#endif

// MARK: - Calendar Manager
@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    @Published var selectedDate = Date()
    @Published var events: [EKEvent] = []
    @Published private(set) var eventsByDay: [Date: [EKEvent]] = [:]
    @Published var allCalendars: [EKCalendar] = []
    @Published var selectedCalendars: Set<String> = []
    @Published var isLoading = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var searchQuery: String = ""

    nonisolated(unsafe) let store = EKEventStore()
    private let selectedCalendarsKey = "selectedCalendarIdentifiers"
    private var reloadTask: Task<Void, Never>?
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
                self?.reloadEvents()
            }
        }
    }
    
    var canReadEvents: Bool {
        if #available(iOS 17, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }
    
    var canWriteEvents: Bool {
        if #available(iOS 17, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        } else {
            return authorizationStatus == .authorized
        }
    }
    
    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func requestAccess() async {
        if #available(iOS 17, *) {
            if authorizationStatus == .notDetermined {
                do {
                    _ = try await store.requestFullAccessToEvents()
                } catch {
                }
                refreshAuthorizationStatus()
            }
            
            if canReadEvents {
                await reloadEverything()
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                    if granted {
                        await self?.reloadEverything()
                    }
                }
            }
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

            let store = self.store
            let calendars = visibleCalendarIDs.compactMap { store.calendar(withIdentifier: $0) }
            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)

            let fetched = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

            guard !Task.isCancelled, self.loadToken == token else {
                if self.loadToken == token {
                    self.isLoading = false
                }
                return
            }
            self.events = fetched
            self.eventsByDay = self.groupEventsByDay(fetched)
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

    private func groupEventsByDay(_ events: [EKEvent]) -> [Date: [EKEvent]] {
        let cal = dayCalendar
        var dict: [Date: [EKEvent]] = [:]

        for event in events {
            if event.isAllDay {
                let start = cal.startOfDay(for: event.startDate)
                let endExclusive = cal.startOfDay(for: event.endDate)
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
                var d = cal.startOfDay(for: event.startDate)
                let lastDay = cal.startOfDay(for: event.endDate)
                while d <= lastDay {
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: d) ?? d
                    if event.startDate < dayEnd && event.endDate > d {
                        dict[d, default: []].append(event)
                    }
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

// MARK: - Main Calendar View
struct CalendarMainView: View {
    @StateObject private var manager = CalendarManager.shared
    @EnvironmentObject var sharedStateManager: SharedStateManager
    @State private var showingSettings = false
    @State private var showingEventEditor = false
    @State private var showingUpcomingEvents = false
    @State private var selectedEvent: EKEvent?
    @State private var currentMonth = Date()
    @State private var showingYearView = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                if hasAccess {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "calendar")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .frame(width: 40, height: 44)
                                .accessibilityHidden(true)
                            CalendarHeader(
                                selectedDate: $manager.selectedDate,
                                currentMonth: $currentMonth,
                                showingYearView: $showingYearView,
                                onToday: {
                                    manager.selectedDate = Date()
                                    currentMonth = Date()
                                },
                                onSettings: { showingSettings = true }
                            )
                            .frame(maxWidth: .infinity)
                            Button(action: { showingUpcomingEvents = true }) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.Colors.surface)
                                            .shadow(color: DesignSystem.Shadows.small, radius: 8, x: 0, y: 3)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Upcoming events")
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.top, DesignSystem.Spacing.sm)
                        
                        CombinedCalendarView(
                            manager: manager,
                            currentMonth: $currentMonth,
                            showingEventEditor: $showingEventEditor
                        )
                    }
                    .overlay {
                        if showingYearView {
                            YearView(
                                currentYear: Calendar.current.component(.year, from: currentMonth),
                                selectedMonth: $currentMonth,
                                isPresented: $showingYearView
                            )
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(1000)
                            .animation(.spring(response: 0.3), value: showingYearView)
                        }
                    }
                } else {
                    PermissionView(status: manager.authorizationStatus, onRequest: { await manager.requestAccess() })
                }
            }
            .navigationBarHiddenIfPossible(true)
            .sheet(isPresented: $showingSettings) {
                CalendarSettingsView(manager: manager)
            }
            .sheet(isPresented: $showingEventEditor) {
                EventEditorView(event: nil, startTime: manager.selectedDate, manager: manager)
            }
            .sheet(isPresented: $showingUpcomingEvents) {
                UpcomingEventsListView(manager: manager)
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, manager: manager)
            }
            .onAppear {
                manager.refreshAuthorizationStatus()
                if manager.canReadEvents {
                    manager.reloadEvents()
                }
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                manager.refreshAuthorizationStatus()
                if manager.canReadEvents {
                    manager.reloadEvents()
                }
            }
            #endif
            .onChange(of: manager.selectedDate) { _, _ in
                manager.loadEvents(center: manager.selectedDate)
            }
            .onChange(of: currentMonth) { _, newMonth in
                manager.loadEvents(center: newMonth)
            }
        }
    }
    
    private var hasAccess: Bool {
        manager.canReadEvents
    }
}

// MARK: - Calendar Header
struct CalendarHeader: View {
    @Binding var selectedDate: Date
    @Binding var currentMonth: Date
    @Binding var showingYearView: Bool
    let onToday: () -> Void
    let onSettings: () -> Void

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            HStack(spacing: DesignSystem.Spacing.md) {
                monthStepButton(systemName: "chevron.left") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                    }
                }
                Spacer(minLength: 0)
                Button(action: { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showingYearView.toggle() } }) {
                    Text(monthFormatter.string(from: currentMonth))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.vertical, DesignSystem.Spacing.sm + 2)
                        .background(
                            Capsule()
                                .fill(DesignSystem.Colors.backgroundSecondary)
                        )
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                monthStepButton(systemName: "chevron.right") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    }
                }
            }
            HStack {
                Button(action: onToday) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Today")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm + 2)
                    .background(
                        Capsule()
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(DesignSystem.Colors.accent.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DesignSystem.Colors.backgroundSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Calendar settings")
            }
        }
        .padding(.vertical, DesignSystem.Spacing.lg)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 6, style: .continuous)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: DesignSystem.Shadows.small, radius: 16, x: 0, y: 6)
        )
    }

    private func monthStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DesignSystem.Colors.backgroundSecondary))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Year View
struct YearView: View {
    let currentYear: Int
    @State private var displayedYear: Int
    @Binding var selectedMonth: Date
    @Binding var isPresented: Bool
    
    init(currentYear: Int, selectedMonth: Binding<Date>, isPresented: Binding<Bool>) {
        self.currentYear = currentYear
        _displayedYear = State(initialValue: currentYear)
        _selectedMonth = selectedMonth
        _isPresented = isPresented
    }
    
    private var months: [Date] {
        let cal = Calendar.current
        return (1...12).compactMap { month in
            var components = DateComponents()
            components.year = displayedYear
            components.month = month
            components.day = 1
            return cal.date(from: components)
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        withAnimation {
                            displayedYear -= 1
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(DesignSystem.Colors.backgroundSecondary))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text(verbatim: "\(displayedYear)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            displayedYear += 1
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(DesignSystem.Colors.backgroundSecondary))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.lg)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
                ], spacing: DesignSystem.Spacing.lg) {
                    ForEach(months, id: \.self) { month in
                        MonthMiniView(month: month, selectedMonth: $selectedMonth, isPresented: $isPresented)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 8, style: .continuous)
                    .stroke(DesignSystem.Colors.border.opacity(0.35), lineWidth: 1)
            )
            .padding(DesignSystem.Spacing.xl)
            .shadow(color: DesignSystem.Shadows.small, radius: 24, x: 0, y: 12)
        }
        .onAppear {
            displayedYear = currentYear
        }
        .onChange(of: currentYear) { _, newValue in
            if isPresented {
                displayedYear = newValue
            }
        }
    }
}

// MARK: - Month Mini View
struct MonthMiniView: View {
    let month: Date
    @Binding var selectedMonth: Date
    @Binding var isPresented: Bool
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: month)
    }
    
    private var isSelected: Bool {
        Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month)
    }
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }
    
    var body: some View {
        Button(action: {
            withAnimation {
                selectedMonth = month
                isPresented = false
            }
        }) {
            VStack(spacing: 8) {
                Text(monthName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        isSelected ? .white :
                        isCurrentMonth ? DesignSystem.Colors.accent :
                        DesignSystem.Colors.textPrimary
                    )
                
                MonthMiniGrid(month: month)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl + 2, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl + 2, style: .continuous)
                    .stroke(isCurrentMonth && !isSelected ? DesignSystem.Colors.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? DesignSystem.Colors.accent.opacity(0.25) : Color.clear, radius: 10, x: 0, y: 4)
        }
    }
}

// MARK: - Month Mini Grid
struct MonthMiniGrid: View {
    let month: Date
    
    private var monthDates: [[Date]] {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let firstWeekday = cal.component(.weekday, from: startOfMonth)
        let firstWeekdayOffset = (firstWeekday - cal.firstWeekday + 7) % 7
        
        var dates: [Date] = []
        
        if firstWeekdayOffset > 0 {
            for offset in 1...firstWeekdayOffset {
                if let date = cal.date(byAdding: .day, value: -offset, to: startOfMonth) {
                    dates.append(date)
                }
            }
            dates.reverse()
        }
        
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count
        for day in 0..<daysInMonth {
            if let date = cal.date(byAdding: .day, value: day, to: startOfMonth) {
                dates.append(date)
            }
        }
        
        let remaining = 35 - dates.count
        if remaining > 0 {
            if let lastDate = dates.last {
                for day in 1...remaining {
                    if let date = cal.date(byAdding: .day, value: day, to: lastDate) {
                        dates.append(date)
                    }
                }
            }
        }
        
        return dates.chunked(into: 7)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            ForEach(Array(monthDates.enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, date in
                        let isCurrentMonth = Calendar.current.isDate(date, equalTo: month, toGranularity: .month)
                        let isToday = Calendar.current.isDateInToday(date)
                        
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 9, weight: isToday ? .bold : .regular))
                            .foregroundColor(
                                isCurrentMonth
                                    ? (isToday ? DesignSystem.Colors.accent : DesignSystem.Colors.textPrimary)
                                    : DesignSystem.Colors.textTertiary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                    }
                }
            }
        }
    }
}

// MARK: - Combined Calendar View
struct CombinedCalendarView: View {
    @ObservedObject var manager: CalendarManager
    @Binding var currentMonth: Date
    @Binding var showingEventEditor: Bool
    @State private var selectedEvent: EKEvent?
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                MonthCalendarGrid(
                    currentMonth: currentMonth,
                    selectedDate: $manager.selectedDate,
                    manager: manager
                )
                .padding(.bottom, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 4, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                        .shadow(color: DesignSystem.Shadows.small, radius: 14, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 4, style: .continuous)
                        .stroke(DesignSystem.Colors.border.opacity(0.45), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDateHeader(manager.selectedDate))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            if !dayEvents.isEmpty {
                                Text("\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(action: { showingEventEditor = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28, weight: .regular))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add event")
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.lg)

                    if !dayEvents.isEmpty {
                        if !allDayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Text("ALL DAY")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                    .tracking(1.1)
                                    .padding(.horizontal, DesignSystem.Spacing.xl)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DesignSystem.Spacing.md) {
                                        ForEach(Array(allDayEvents.enumerated()), id: \.offset) { _, event in
                                            AllDayEventChip(event: event)
                                                .onTapGesture { selectedEvent = event }
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.Spacing.xl)
                                    .padding(.bottom, DesignSystem.Spacing.sm)
                                }
                            }
                        }

                        VStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(Array(timedEvents.enumerated()), id: \.offset) { _, event in
                                EventRow(event: event)
                                    .onTapGesture { selectedEvent = event }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                    } else {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text("No events this day")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("Tap a date above or add something new.")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.xxl + 8)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                    }
                }
                .padding(.bottom, DesignSystem.Spacing.xxl)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 4, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                        .shadow(color: DesignSystem.Shadows.small, radius: 14, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 4, style: .continuous)
                        .stroke(DesignSystem.Colors.border.opacity(0.45), lineWidth: 1)
                )
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event, manager: manager)
        }
    }
    
    private var dayEvents: [EKEvent] {
        manager.eventsForDay(manager.selectedDate)
    }
    
    private var allDayEvents: [EKEvent] {
        dayEvents.filter { $0.isAllDay }
    }
    
    private var timedEvents: [EKEvent] {
        dayEvents.filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Month Calendar Grid
struct MonthCalendarGrid: View {
    let currentMonth: Date
    @Binding var selectedDate: Date
    @ObservedObject var manager: CalendarManager
    
    private var monthDates: [[Date]] {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let firstWeekday = cal.component(.weekday, from: startOfMonth)
        let firstWeekdayOffset = (firstWeekday - cal.firstWeekday + 7) % 7
        
        var dates: [Date] = []
        
        if firstWeekdayOffset > 0 {
            for offset in 1...firstWeekdayOffset {
                if let date = cal.date(byAdding: .day, value: -offset, to: startOfMonth) {
                    dates.append(date)
                }
            }
            dates.reverse()
        }
        
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count
        for day in 0..<daysInMonth {
            if let date = cal.date(byAdding: .day, value: day, to: startOfMonth) {
                dates.append(date)
            }
        }
        
        let remaining = 42 - dates.count
        if remaining > 0 {
            if let lastDate = dates.last {
                for day in 1...remaining {
                    if let date = cal.date(byAdding: .day, value: day, to: lastDate) {
                        dates.append(date)
                    }
                }
            }
        }
        
        return dates.chunked(into: 7)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.lg)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.55))

            Divider()
                .background(DesignSystem.Colors.border.opacity(0.35))

            ForEach(Array(monthDates.enumerated()), id: \.offset) { _, week in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        MonthDayCell(
                            date: date,
                            events: eventsForDay(date),
                            selectedDate: selectedDate,
                            currentMonth: currentMonth
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                selectedDate = date
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .padding(.bottom, DesignSystem.Spacing.md)
        }
    }
    
    private func eventsForDay(_ date: Date) -> [EKEvent] {
        return manager.eventsForDay(date)
    }
}

struct MonthDayCell: View {
    private static let maxDisplayedEvents = 6

    let date: Date
    let events: [EKEvent]
    let selectedDate: Date
    let currentMonth: Date
    
    private var displayedEvents: [EKEvent] {
        Array(events.prefix(Self.maxDisplayedEvents))
    }
    
    private var titleFontSize: CGFloat {
        events.count > 4 ? 7 : 8
    }
    
    private var isSelected: Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Spacer(minLength: 0)
                Text("\(dayNumber)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .foregroundColor(dayNumberColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? DesignSystem.Colors.accent : Color.clear)
                    )
                Spacer(minLength: 0)
            }
            
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(Array(displayedEvents.enumerated()), id: \.offset) { _, event in
                            Circle()
                                .fill(inkEventCalendarColor(for: event))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    
                    ForEach(Array(displayedEvents.enumerated()), id: \.offset) { _, event in
                        HStack(alignment: .center, spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(inkEventCalendarColor(for: event))
                                .frame(width: 3, height: 11)
                            Text(eventTitle(for: event))
                                .font(.system(size: titleFontSize, weight: .medium))
                                .foregroundColor(eventTitleColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if events.count > Self.maxDisplayedEvents {
                        Text("+\(events.count - Self.maxDisplayedEvents) more")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                .fill(cellFill)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                    .stroke(DesignSystem.Colors.accent.opacity(0.85), lineWidth: 2)
            } else if isToday && isCurrentMonth {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                    .stroke(DesignSystem.Colors.accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private var cellFill: Color {
        if isSelected { return DesignSystem.Colors.accent.opacity(0.14) }
        return Color.clear
    }

    private var dayNumberColor: Color {
        if isSelected { return .white }
        if isToday { return DesignSystem.Colors.accent }
        if isCurrentMonth { return DesignSystem.Colors.textPrimary }
        return DesignSystem.Colors.textTertiary
    }
    
    private var eventTitleColor: Color {
        if !isCurrentMonth { return DesignSystem.Colors.textTertiary }
        return DesignSystem.Colors.textPrimary
    }
    
    private func eventTitle(for event: EKEvent) -> String {
        let raw = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Event" : raw
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: EKEvent
    
    private var eventColor: Color {
        inkEventCalendarColor(for: event)
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeString(from: event.startDate))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if event.endDate.timeIntervalSince(event.startDate) > 3600 {
                    Text(timeString(from: event.endDate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .frame(width: 72, alignment: .leading)
            
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(eventColor)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                        Text(location)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignSystem.Spacing.lg)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                .stroke(DesignSystem.Colors.border.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: DesignSystem.Shadows.small, radius: 6, x: 0, y: 2)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - All Day Event Chip
struct AllDayEventChip: View {
    let event: EKEvent
    
    private var eventColor: Color {
        inkEventCalendarColor(for: event)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(eventColor)
                .frame(width: 7, height: 7)
            
            Text(event.title ?? "Untitled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            Capsule(style: .continuous)
                .fill(eventColor.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(eventColor.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

// MARK: - Event Detail View
struct EventDetailView: View {
    let event: EKEvent
    @ObservedObject var manager: CalendarManager
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingEdit = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(inkEventCalendarColor(for: event))
                        .frame(height: 4)
                        .padding(.bottom, DesignSystem.Spacing.xs)

                    Text(event.title ?? "Untitled")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .frame(width: 28, alignment: .center)
                            Group {
                                if event.isAllDay {
                                    Text("All day")
                                } else {
                                    Text("\(formatDate(event.startDate)) – \(formatDate(event.endDate))")
                                }
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        }

                        if let location = event.location, !location.isEmpty {
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.accent)
                                    .frame(width: 28, alignment: .center)
                                Text(location)
                                    .font(.system(size: 16))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                            }
                        }

                        if let notes = event.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 15))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(DesignSystem.Spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.6))
                                )
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                            .fill(DesignSystem.Colors.surface)
                            .shadow(color: DesignSystem.Shadows.small, radius: 10, x: 0, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                            .stroke(DesignSystem.Colors.border.opacity(0.35), lineWidth: 1)
                    )

                    Button(action: { showingDeleteConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Event")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                .fill(DesignSystem.Colors.error.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Event Details")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showingEdit = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEdit) {
                EventEditorView(event: event, startTime: nil, manager: manager)
            }
            .alert("Delete Event", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    manager.deleteEvent(event)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this event?")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Calendar Settings View
struct CalendarSettingsView: View {
    @ObservedObject var manager: CalendarManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Calendars") {
                    ForEach(manager.allCalendars, id: \.calendarIdentifier) { calendar in
                        CalendarToggleRow(calendar: calendar, manager: manager)
                    }
                }
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CalendarToggleRow: View {
    let calendar: EKCalendar
    @ObservedObject var manager: CalendarManager
    
    private var isSelected: Bool {
        manager.selectedCalendars.contains(calendar.calendarIdentifier)
    }

    var body: some View {
        Toggle(calendar.title, isOn: Binding(
            get: { isSelected },
            set: { _ in manager.toggleCalendar(calendar) }
        ))
        .tint(Color(calendar.cgColor ?? Color.platformSystemBlueCGColor))
    }
}

// MARK: - Upcoming Events List View
struct UpcomingEventsListView: View {
    @ObservedObject var manager: CalendarManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedEvent: EKEvent?
    @State private var showingEventEditor = false
    @State private var filterOption: EventFilterOption = .week
    @State private var searchText = ""
    
    enum EventFilterOption: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "Next 2 years"
        
        var dateRange: (start: Date, end: Date) {
            let cal = Calendar.current
            let now = Date()
            let startOfToday = cal.startOfDay(for: now)
            
            switch self {
            case .today:
                let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
                return (startOfToday, endOfToday)
            case .week:
                let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
                return (startOfToday, endOfWeek)
            case .month:
                let comps = cal.dateComponents([.year, .month], from: now)
                let startOfThisMonth = cal.date(from: comps) ?? startOfToday
                let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfThisMonth) ?? startOfThisMonth
                return (startOfToday, startOfNextMonth)
            case .all:
                let endHorizon = cal.date(byAdding: .year, value: 2, to: startOfToday) ?? startOfToday
                return (startOfToday, endHorizon)
            }
        }
    }
    
    private func eventIntersectsWindow(_ event: EKEvent, windowStart: Date, windowEnd: Date) -> Bool {
        guard let s = event.startDate, let e = event.endDate else { return false }
        if e <= s {
            return s >= windowStart && s < windowEnd
        }
        return s < windowEnd && e > windowStart
    }
    
    private func dedupeEvents(_ events: [EKEvent]) -> [EKEvent] {
        var seen = Set<String>()
        return events.filter { e in
            let key = "\(e.eventIdentifier ?? "")-\(e.startDate?.timeIntervalSince1970 ?? 0)"
            return seen.insert(key).inserted
        }
    }
    
    private var filteredEvents: [EKEvent] {
        let range = filterOption.dateRange
        var events = manager.events.filter { eventIntersectsWindow($0, windowStart: range.start, windowEnd: range.end) }
        events = dedupeEvents(events)
        
        if !searchText.isEmpty {
            events = events.filter { event in
                (event.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                (event.location ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return events.sorted { lhs, rhs in
            let l = lhs.startDate?.timeIntervalSince1970 ?? 0
            let r = rhs.startDate?.timeIntervalSince1970 ?? 0
            return l < r
        }
    }
    
    private var groupedEvents: [(date: Date, events: [EKEvent])] {
        let cal = Calendar.current
        let range = filterOption.dateRange
        let rangeStartDay = cal.startOfDay(for: range.start)
        let grouped = Dictionary(grouping: filteredEvents) { event in
            let eventDay = cal.startOfDay(for: event.startDate ?? .distantPast)
            return max(eventDay, rangeStartDay)
        }
        return grouped.sorted { $0.key < $1.key }.map { pair in
            let sorted = pair.value.sorted { lhs, rhs in
                let l = lhs.startDate?.timeIntervalSince1970 ?? 0
                let r = rhs.startDate?.timeIntervalSince1970 ?? 0
                return l < r
            }
            return (date: pair.key, events: sorted)
        }
    }
    
    private struct UpcomingListRowModel: Identifiable {
        let id: String
        let event: EKEvent
        
        init(sectionDay: Date, index: Int, event: EKEvent) {
            self.event = event
            let dayKey = String(sectionDay.timeIntervalSince1970)
            let sid = event.eventIdentifier ?? ""
            let t = event.startDate?.timeIntervalSince1970 ?? 0
            self.id = "\(dayKey)-\(index)-\(sid)-\(t)"
        }
    }
    
    private func listRowModels(for group: (date: Date, events: [EKEvent])) -> [UpcomingListRowModel] {
        group.events.enumerated().map { UpcomingListRowModel(sectionDay: group.date, index: $0.offset, event: $0.element) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(EventFilterOption.allCases, id: \.self) { option in
                                CalendarFilterPill(
                                    title: option.rawValue,
                                    isSelected: filterOption == option
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        filterOption = option
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        
                        TextField("Search events…", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                            .fill(DesignSystem.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                            .stroke(DesignSystem.Colors.border.opacity(0.45), lineWidth: 1)
                    )
                    .shadow(color: DesignSystem.Shadows.small, radius: 6, x: 0, y: 2)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.bottom, DesignSystem.Spacing.md)
                    
                    if filteredEvents.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 64))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            
                            Text("No Upcoming Events")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("Events for \(filterOption.rawValue.lowercased()) will appear here")
                                .font(.system(size: 15))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: { showingEventEditor = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Event")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(DesignSystem.Colors.accent)
                                .cornerRadius(12)
                            }
                            .padding(.top, 8)
                            
                            Spacer()
                        }
                        .padding(40)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(groupedEvents, id: \.date) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        DateSectionHeader(date: group.date, eventCount: group.events.count)
                                        ForEach(listRowModels(for: group)) { row in
                                            UpcomingEventRow(event: row.event)
                                                .onTapGesture {
                                                    selectedEvent = row.event
                                                }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .navigationTitle("Upcoming Events")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingEventEditor = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, manager: manager)
            }
            .sheet(isPresented: $showingEventEditor) {
                EventEditorView(event: nil, startTime: Date(), manager: manager)
            }
            .onAppear {
                manager.loadEvents(center: Date())
            }
        }
    }
}

// MARK: - Calendar Filter Pill
struct CalendarFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.clear : DesignSystem.Colors.border.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: isSelected ? DesignSystem.Colors.accent.opacity(0.28) : DesignSystem.Shadows.small, radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 3 : 2)
                .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Section Header
struct DateSectionHeader: View {
    let date: Date
    let eventCount: Int
    
    private var formattedDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today"
        } else if cal.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
    
    private var relativeDate: String? {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInTomorrow(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.md) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DesignSystem.Colors.accent)
                .frame(width: 4, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if let relative = relativeDate {
                    Text(relative)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer(minLength: 0)
            
            Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm + 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DesignSystem.Colors.border.opacity(0.4), lineWidth: 1)
                )
        }
        .padding(.vertical, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.sm)
    }
}

// MARK: - Upcoming Event Row
struct UpcomingEventRow: View {
    let event: EKEvent
    
    private var eventColor: Color {
        inkEventCalendarColor(for: event)
    }
    
    private var timeText: String {
        if event.isAllDay {
            return "All Day"
        }
        guard let start = event.startDate else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: start)
    }
    
    private var durationText: String? {
        guard !event.isAllDay else { return nil }
        guard let s = event.startDate, let e = event.endDate else { return nil }
        let duration = e.timeIntervalSince(s)
        guard duration > 0 else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title ?? "Untitled Event")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: event.isAllDay ? "sun.max.fill" : "clock.fill")
                            .font(.system(size: 11))
                        Text(timeText)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(eventColor)
                    
                    if let duration = durationText {
                        Text("•")
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text(duration)
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    if let location = event.location, !location.isEmpty {
                        Text("•")
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        HStack(spacing: 3) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                            Text(location)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            Circle()
                .fill(eventColor.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(eventColor)
                )
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl + 2, style: .continuous)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl + 2, style: .continuous)
                .stroke(DesignSystem.Colors.border.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: DesignSystem.Shadows.small, radius: 8, x: 0, y: 3)
    }
}

// MARK: - Permission View
struct PermissionView: View {
    let status: EKAuthorizationStatus
    let onRequest: () async -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
                .symbolRenderingMode(.hierarchical)
            
            Text("Calendar Access Required")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(message)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
            
            if status == .notDetermined {
                Button(action: { Task { await onRequest() } }) {
                    Text("Allow Calendar Access")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                .fill(DesignSystem.Colors.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignSystem.Spacing.xxl)
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Button(action: openAppSettings) {
                        Text("Open Settings")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.lg)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                    .fill(DesignSystem.Colors.accent)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: { Task { await onRequest() } }) {
                        Text("Check Again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.lg)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                    .stroke(DesignSystem.Colors.accent, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignSystem.Spacing.xxl)
            }
        }
        .padding(DesignSystem.Spacing.xxl + 8)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 8, style: .continuous)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: DesignSystem.Shadows.small, radius: 20, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl + 8, style: .continuous)
                .stroke(DesignSystem.Colors.border.opacity(0.4), lineWidth: 1)
        )
        .padding(DesignSystem.Spacing.xl)
    }
    
    private var message: String {
        if #available(iOS 17, *) {
            if status == .writeOnly {
                return "InkSlate currently needs full access to show your existing events. You’ve granted write-only access, which can create events but can’t display your calendar."
            }
        }
        
        if status == .denied || status == .restricted {
            return "Calendar access is turned off. You can enable it in Settings to view and manage your events."
        }
        
        return "Please grant calendar access to view and manage your events."
    }
    
    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Event Editor View
struct EventEditorView: View {
    let event: EKEvent?
    let startTime: Date?
    @ObservedObject var manager: CalendarManager
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedCalendar: EKCalendar?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    
    private var dayCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCalendar != nil &&
        endDate > startDate &&
        !isSaving
    }
    
    private var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a title"
        }
        if selectedCalendar == nil {
            return "Please select a calendar"
        }
        if endDate <= startDate && !isAllDay {
            return "End time must be after start time"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event Title", text: $title)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    Toggle("All Day", isOn: $isAllDay)
                } header: {
                    Text("Event Details")
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Time") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $endDate, in: isAllDay ? Date.distantPast... : startDate..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                }
                
                Section("Additional Info") {
                    TextField("Location (optional)", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Calendar") {
                    if manager.allCalendars.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("No calendars available")
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    } else {
                        Picker("Select Calendar", selection: $selectedCalendar) {
                            ForEach(manager.allCalendars.filter { $0.allowsContentModifications }, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(Color(calendar.cgColor ?? Color.platformSystemBlueCGColor))
                                        .frame(width: 12, height: 12)
                                    Text(calendar.title)
                                }
                                .tag(calendar as EKCalendar?)
                            }
                        }
                    }
                }
            }
            .navigationTitle(event == nil ? "New Event" : "Edit Event")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveEvent) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(event == nil ? "Create" : "Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                setupInitialValues()
            }
            .onChange(of: isAllDay) { _, newValue in
                if newValue {
                    DispatchQueue.main.async {
                        normalizeAllDayDates()
                    }
                }
            }
            .onChange(of: startDate) { _, newValue in
                if !isAllDay && endDate <= newValue {
                    endDate = newValue.addingTimeInterval(3600)
                }
            }
            .alert("Unable to Save Event", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func setupInitialValues() {
        if let event = event {
            title = event.title ?? ""
            startDate = event.startDate
            endDate = event.endDate
            isAllDay = event.isAllDay
            location = event.location ?? ""
            notes = event.notes ?? ""
            selectedCalendar = event.calendar
        } else {
            startDate = startTime ?? Date()
            endDate = startDate.addingTimeInterval(3600)
            selectedCalendar = manager.allCalendars.first(where: { $0.allowsContentModifications })
        }
    }
    
    private func normalizeAllDayDates() {
        guard isAllDay else { return }
        
        let cal = dayCalendar
        let startComponents = cal.dateComponents([.year, .month, .day], from: startDate)
        
        var startDateComponents = DateComponents()
        startDateComponents.year = startComponents.year
        startDateComponents.month = startComponents.month
        startDateComponents.day = startComponents.day
        startDateComponents.hour = 0
        startDateComponents.minute = 0
        startDateComponents.second = 0
        
        if let normalizedStart = cal.date(from: startDateComponents) {
            startDate = normalizedStart
        }
        
        let endComponents = cal.dateComponents([.year, .month, .day], from: endDate)
        let startDay = cal.date(from: startComponents)
        let endDay = cal.date(from: endComponents)
        
        if let start = startDay, let end = endDay {
            if end <= start {
                endDate = cal.date(byAdding: .day, value: 1, to: startDate) ?? endDate
            } else {
                var endDateComponents = DateComponents()
                endDateComponents.year = endComponents.year
                endDateComponents.month = endComponents.month
                endDateComponents.day = endComponents.day
                endDateComponents.hour = 0
                endDateComponents.minute = 0
                endDateComponents.second = 0
                
                if let normalizedEnd = cal.date(from: endDateComponents) {
                    endDate = cal.date(byAdding: .day, value: 1, to: normalizedEnd) ?? endDate
                }
            }
        }
    }
    
    private func saveEvent() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a title for the event."
            showingError = true
            return
        }
        
        guard let calendar = selectedCalendar else {
            errorMessage = "Please select a calendar to save the event to."
            showingError = true
            return
        }
        
        guard calendar.allowsContentModifications else {
            errorMessage = "The selected calendar does not allow modifications. Please choose a different calendar."
            showingError = true
            return
        }
        
        isSaving = true
        
        let eventToSave = event ?? EKEvent(eventStore: manager.store)
        eventToSave.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isAllDay {
            normalizeAllDayDates()
        }
        
        eventToSave.startDate = startDate
        eventToSave.endDate = endDate
        eventToSave.isAllDay = isAllDay
        eventToSave.location = location.isEmpty ? nil : location
        eventToSave.notes = notes.isEmpty ? nil : notes
        eventToSave.calendar = calendar
        
        do {
            try manager.store.save(eventToSave, span: .thisEvent, commit: true)
            manager.reloadEvents()
            dismiss()
        } catch let error {
            isSaving = false
            errorMessage = "Failed to save event: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Extensions
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
