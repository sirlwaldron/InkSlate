//
//  CalendarViews.swift
//  InkSlate
//
//  Modern, minimalist calendar implementation

import SwiftUI
import EventKit
import UIKit

// MARK: - EKEvent Extension
extension EKEvent: @retroactive Identifiable {
    public var id: String { eventIdentifier }
}

// MARK: - Calendar Manager
@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    @Published var selectedDate = Date()
    @Published var events: [EKEvent] = []
    @Published var allCalendars: [EKCalendar] = []
    @Published var selectedCalendars: Set<String> = []
    @Published var isLoading = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var searchQuery: String = ""

    let store = EKEventStore()
    private let selectedCalendarsKey = "selectedCalendarIdentifiers"
    private var reloadTask: Task<Void, Never>?
    
    private var dayCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }
    
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
    
    func requestAccess() async {
            if #available(iOS 17, *) {
            if authorizationStatus == .notDetermined {
                    do {
                        let granted = try await store.requestFullAccessToEvents()
                    authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                        if granted {
                        await reloadEverything()
                        }
                    } catch {
                    // Access request failed
                }
            } else if authorizationStatus == .fullAccess {
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
        let hasAccess: Bool
        if #available(iOS 17, *) {
            hasAccess = authorizationStatus == .fullAccess
        } else {
            hasAccess = authorizationStatus == .authorized
        }
        
        guard hasAccess else {
            events = []
            return
        }
        
        reloadTask?.cancel()
        reloadTask = Task {
            isLoading = true
            defer { isLoading = false }

            let base = center ?? selectedDate
            let cal = dayCalendar
            let startDate = cal.date(byAdding: .month, value: -6, to: cal.startOfDay(for: base))!
            let endDate = cal.date(byAdding: .month, value: 6, to: cal.startOfDay(for: base))!
            
            let visibleCalendars = selectedCalendars.isEmpty
                ? allCalendars
                : allCalendars.filter { selectedCalendars.contains($0.calendarIdentifier) }
            
            guard !visibleCalendars.isEmpty else {
                events = []
                return
            }

            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: visibleCalendars)
            let fetched = store.events(matching: predicate)
            events = fetched.sorted { $0.startDate < $1.startDate }
        }
    }
    
    func eventsForDay(_ date: Date) -> [EKEvent] {
        let cal = dayCalendar
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Get date components for the selected day
        let dayComponents = cal.dateComponents([.year, .month, .day], from: date)
        guard let dayYear = dayComponents.year,
              let dayMonth = dayComponents.month,
              let dayDay = dayComponents.day else {
            return []
        }
        
        return events.filter { event in
            if event.isAllDay {
                // For all-day events, compare date components directly
                let eventStartComponents = cal.dateComponents([.year, .month, .day], from: event.startDate)
                let eventEndComponents = cal.dateComponents([.year, .month, .day], from: event.endDate)
                
                // Check if the selected day falls within the event's date range
                // EventKit stores endDate as the start of the next day (exclusive)
                if let eventStartYear = eventStartComponents.year,
                   let eventStartMonth = eventStartComponents.month,
                   let eventStartDay = eventStartComponents.day,
                   let eventEndYear = eventEndComponents.year,
                   let eventEndMonth = eventEndComponents.month,
                   let eventEndDay = eventEndComponents.day {
                    
                    // Compare dates directly using components
                    if dayYear == eventStartYear && dayMonth == eventStartMonth && dayDay == eventStartDay {
                        return true
                    }
                    
                    // Check if day is between start and end (end is exclusive)
                    let eventStart = (eventStartYear * 10000) + (eventStartMonth * 100) + eventStartDay
                    let eventEnd = (eventEndYear * 10000) + (eventEndMonth * 100) + eventEndDay
                    let dayValue = (dayYear * 10000) + (dayMonth * 100) + dayDay
                    
                    return dayValue >= eventStart && dayValue < eventEnd
                }
                return false
            } else {
                // Regular timed event - check if it overlaps with the day
                return event.startDate < dayEnd && event.endDate > dayStart
            }
        }
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
            // Delete failed
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
    @State private var isHovering = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                if hasAccess {
                    VStack(spacing: 0) {
                        // Header with Hamburger Menu
                        HStack {
                            HamburgerMenuButton(
                                isMenuOpen: $sharedStateManager.isMenuOpen,
                                isHovering: $isHovering
                            )
                            .padding(.leading, 16)
                            
                            Spacer()
                            
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
                            
                            Spacer()
                            
                            // List View Button
                            Button(action: { showingUpcomingEvents = true }) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .frame(width: 44, height: 44)
                            }
                            .padding(.trailing, 16)
                        }
                        .padding(.top, 8)
                        
                        // Combined Month + Events View
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
                    PermissionView(onRequest: { await manager.requestAccess() })
                }
            }
            .navigationBarHidden(true)
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
                Task {
                    await manager.requestAccess()
                }
            }
            .onChange(of: manager.selectedDate) { _, _ in
                manager.loadEvents(center: manager.selectedDate)
            }
        }
    }
    
    private var hasAccess: Bool {
        if #available(iOS 17, *) {
            return manager.authorizationStatus == .fullAccess
        } else {
            return manager.authorizationStatus == .authorized
        }
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
        VStack(spacing: 16) {
            HStack {
                Button(action: {
                    withAnimation {
                        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        showingYearView.toggle()
                    }
                }) {
                    Text(monthFormatter.string(from: currentMonth))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            .padding(.horizontal, 20)
            
            HStack {
                Button(action: onToday) {
                    Text("Today")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(DesignSystem.Colors.background)
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
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        isPresented = false
                    }
                }
            
            // Year grid
            VStack(spacing: 0) {
                // Header with year navigation
                        HStack {
                    Button(action: {
                        withAnimation {
                            displayedYear -= 1
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    Text("\(displayedYear)")
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
                    }
                }
                .padding(20)
                
                // Month grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    ForEach(months, id: \.self) { month in
                        MonthMiniView(month: month, selectedMonth: $selectedMonth, isPresented: $isPresented)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(DesignSystem.Colors.background)
            .cornerRadius(20)
            .padding(20)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
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
                
                // Mini calendar grid
                MonthMiniGrid(month: month)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrentMonth && !isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
            )
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
        
        // Add dates before the start of the month
        if firstWeekdayOffset > 0 {
            for offset in 1...firstWeekdayOffset {
                if let date = cal.date(byAdding: .day, value: -offset, to: startOfMonth) {
                    dates.append(date)
                }
            }
            dates.reverse() // Reverse to get chronological order
        }
        
        // Add dates in the month
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count
        for day in 0..<daysInMonth {
            if let date = cal.date(byAdding: .day, value: day, to: startOfMonth) {
                dates.append(date)
            }
        }
        
        // Add dates after the month to fill the grid
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
            // Weekday headers (S M T W T F S)
            HStack(spacing: 2) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
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
            VStack(spacing: 0) {
                // Month Calendar Grid
                MonthCalendarGrid(
                    currentMonth: currentMonth,
                    selectedDate: $manager.selectedDate,
                    manager: manager
                )
                .padding(.bottom, 24)
                
                // Events List for Selected Day
                VStack(alignment: .leading, spacing: 16) {
                    // Date Header
                    HStack {
                        Text(formatDateHeader(manager.selectedDate))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            if !dayEvents.isEmpty {
                                Text("\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            Button(action: {
                                showingEventEditor = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    if !dayEvents.isEmpty {
                        // All-day events
                        if !allDayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ALL DAY")
                                    .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .tracking(0.5)
                                    .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(allDayEvents, id: \.eventIdentifier) { event in
                                            AllDayEventChip(event: event)
                                                .onTapGesture {
                                                    selectedEvent = event
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        
                        // Timed events
                        ForEach(timedEvents, id: \.eventIdentifier) { event in
                            EventRow(event: event)
                                .padding(.horizontal, 20)
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    } else {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 48))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("No events")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.bottom, 20)
            }
        }
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
        
        // Add dates before the start of the month
        if firstWeekdayOffset > 0 {
            for offset in 1...firstWeekdayOffset {
                if let date = cal.date(byAdding: .day, value: -offset, to: startOfMonth) {
                    dates.append(date)
                }
            }
            dates.reverse() // Reverse to get chronological order
        }
        
        // Add dates in the month
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count
        for day in 0..<daysInMonth {
            if let date = cal.date(byAdding: .day, value: day, to: startOfMonth) {
                dates.append(date)
            }
        }
        
        // Add dates after the month to fill the grid
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
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            
            // Calendar grid
            ForEach(Array(monthDates.enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, date in
                        MonthDayCell(
                            date: date,
                            events: eventsForDay(date),
                            selectedDate: selectedDate,
                            currentMonth: currentMonth
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedDate = date
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func eventsForDay(_ date: Date) -> [EKEvent] {
        return manager.eventsForDay(date)
    }
}

struct MonthDayCell: View {
    let date: Date
    let events: [EKEvent]
    let selectedDate: Date
    let currentMonth: Date
    
    private var isSelected: Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected ? .bold : .regular))
                .foregroundColor(
                    isSelected ? .white :
                    isToday ? DesignSystem.Colors.accent :
                    isCurrentMonth ? DesignSystem.Colors.textPrimary :
                    DesignSystem.Colors.textTertiary
                )
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isSelected ? DesignSystem.Colors.accent : Color.clear)
                )
            
            // Event dots
            HStack(spacing: 3) {
                ForEach(Array(events.prefix(3)), id: \.eventIdentifier) { event in
                    Circle()
                        .fill(Color(event.calendar.cgColor ?? UIColor.systemBlue.cgColor))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: EKEvent
    
    private var eventColor: Color {
        Color(event.calendar.cgColor ?? UIColor.systemBlue.cgColor)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(timeString(from: event.startDate))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if event.endDate.timeIntervalSince(event.startDate) > 3600 {
                    Text(timeString(from: event.endDate))
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .frame(width: 70, alignment: .leading)
            
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor)
                .frame(width: 3)
            
            // Event info
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if let location = event.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                        Text(location)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
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
        Color(event.calendar.cgColor ?? UIColor.systemBlue.cgColor)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(eventColor)
                .frame(width: 6, height: 6)
            
            Text(event.title ?? "Untitled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
                                                    .background(
            Capsule()
                .fill(eventColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(eventColor.opacity(0.4), lineWidth: 1)
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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(event.title ?? "Untitled")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .foregroundColor(DesignSystem.Colors.accent)
                        if event.isAllDay {
                            Text("All Day")
                                        } else {
                            Text("\(formatDate(event.startDate)) - \(formatDate(event.endDate))")
                        }
                    }
                    .font(.system(size: 16))
                    
                    if let location = event.location {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle")
                                .foregroundColor(DesignSystem.Colors.accent)
                            Text(location)
                        }
                        .font(.system(size: 16))
                    }
                    
                    if let notes = event.notes {
                        Text(notes)
                            .font(.system(size: 15))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Button(action: { showingDeleteConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Event")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .tint(Color(calendar.cgColor ?? UIColor.systemBlue.cgColor))
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
        case all = "All Events"
        
        var dateRange: (start: Date, end: Date) {
            let cal = Calendar.current
            let now = Date()
            let startOfToday = cal.startOfDay(for: now)
            
            switch self {
            case .today:
                let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!
                return (startOfToday, endOfToday)
            case .week:
                let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday)!
                return (startOfToday, endOfWeek)
            case .month:
                let endOfMonth = cal.date(byAdding: .month, value: 1, to: startOfToday)!
                return (startOfToday, endOfMonth)
            case .all:
                let endOfYear = cal.date(byAdding: .year, value: 1, to: startOfToday)!
                return (startOfToday, endOfYear)
            }
        }
    }
    
    private var filteredEvents: [EKEvent] {
        let range = filterOption.dateRange
        var events = manager.events.filter { event in
            event.startDate >= range.start && event.startDate < range.end
        }
        
        if !searchText.isEmpty {
            events = events.filter { event in
                (event.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                (event.location ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    private var groupedEvents: [(date: Date, events: [EKEvent])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            cal.startOfDay(for: event.startDate)
        }
        return grouped.sorted { $0.key < $1.key }.map { (date: $0.key, events: $0.value) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter Pills
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
                    
                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        TextField("Search events...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    if filteredEvents.isEmpty {
                        // Empty State
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
                        // Events List
                        ScrollView {
                            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                                ForEach(groupedEvents, id: \.date) { group in
                                    Section {
                                        ForEach(group.events, id: \.eventIdentifier) { event in
                                            UpcomingEventRow(event: event)
                                                .onTapGesture {
                                                    selectedEvent = event
                                                }
                                        }
                                    } header: {
                                        DateSectionHeader(date: group.date, eventCount: group.events.count)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
                )
        }
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if let relative = relativeDate {
                    Text(relative)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Upcoming Event Row
struct UpcomingEventRow: View {
    let event: EKEvent
    
    private var eventColor: Color {
        Color(event.calendar.cgColor ?? UIColor.systemBlue.cgColor)
    }
    
    private var timeText: String {
        if event.isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate)
    }
    
    private var durationText: String? {
        guard !event.isAllDay else { return nil }
        let duration = event.endDate.timeIntervalSince(event.startDate)
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
            // Color accent bar
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)
                .frame(width: 4)
            
            // Event content
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title ?? "Untitled Event")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    // Time
                    HStack(spacing: 4) {
                        Image(systemName: event.isAllDay ? "sun.max.fill" : "clock.fill")
                            .font(.system(size: 11))
                        Text(timeText)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(eventColor)
                    
                    // Duration
                    if let duration = durationText {
                        Text("•")
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text(duration)
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    // Location
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
            
            // Calendar indicator
            Circle()
                .fill(eventColor.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(eventColor)
                )
        }
        .padding(16)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Permission View
struct PermissionView: View {
    let onRequest: () async -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.accent)
            
            Text("Calendar Access Required")
                .font(.system(size: 24, weight: .bold))
            
            Text("Please grant calendar access to view and manage your events.")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { Task { await onRequest() } }) {
                Text("Grant Access")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
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
                        .textInputAutocapitalization(.words)
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
                                        .fill(Color(calendar.cgColor ?? UIColor.systemBlue.cgColor))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveEvent) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Create")
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
                // Ensure end date is always after start date for timed events
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
            // Select the first calendar that allows modifications
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
        // Validate inputs
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
