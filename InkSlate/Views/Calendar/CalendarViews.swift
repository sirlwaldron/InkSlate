import SwiftUI
@preconcurrency import EventKit
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Identified Day (navigation)
struct IdentifiedDay: Identifiable, Hashable {
    let date: Date
    var id: TimeInterval {
        Calendar.current.startOfDay(for: date).timeIntervalSince1970
    }
}

// MARK: - Main Calendar View
struct CalendarMainView: View {
    @ObservedObject private var manager = CalendarManager.shared
    @EnvironmentObject var sharedStateManager: SharedStateManager
    @State private var showingSettings = false
    @State private var showingUpcomingEvents = false
    @State private var dayDestination: IdentifiedDay?
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
                                    dayDestination = IdentifiedDay(date: Date())
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
                            onDaySelected: { date in
                                manager.selectedDate = date
                                dayDestination = IdentifiedDay(date: date)
                            }
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
                    PermissionView(
                        status: manager.authorizationStatus,
                        onRequest: { await manager.requestAccess() },
                        onRecheck: { manager.refreshAccessFromSettings() }
                    )
                }
            }
            .navigationBarHiddenIfPossible(true)
            .navigationDestination(item: $dayDestination) { day in
                DayEventsView(date: day.date, manager: manager)
            }
            .inkSlateSheet(isPresented: $showingSettings) {
                CalendarSettingsView(manager: manager)
            }
            .inkSlateSheet(isPresented: $showingUpcomingEvents) {
                UpcomingEventsListView(manager: manager)
            }
            .onAppear {
                manager.refreshAuthorizationStatus()
                if manager.canReadEvents {
                    manager.reloadEvents()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.didBecomeActive)) { _ in
                manager.refreshAccessFromSettings()
            }
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
    let onDaySelected: (Date) -> Void
    
    var body: some View {
        ScrollView {
            MonthCalendarGrid(
                currentMonth: currentMonth,
                selectedDate: $manager.selectedDate,
                manager: manager,
                onDaySelected: onDaySelected
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
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Day Events View
struct DayEventsView: View {
    let date: Date
    @ObservedObject var manager: CalendarManager
    @State private var selectedEvent: IdentifiedCalendarEvent?
    @State private var showingEventEditor = false
    
    private var dayEvents: [EKEvent] {
        manager.eventsForDay(date)
    }
    
    private var allDayEvents: [EKEvent] {
        dayEvents.filter { $0.isAllDay }
    }
    
    private var timedEvents: [EKEvent] {
        dayEvents.filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDateHeader(date))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text(formatDateSubtitle(date))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        if !dayEvents.isEmpty {
                            Text("\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.md)

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
                                                .onTapGesture { selectedEvent = IdentifiedCalendarEvent(event: event) }
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
                                    .onTapGesture { selectedEvent = IdentifiedCalendarEvent(event: event) }
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
                            Text("Add a new event to get started.")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                            Button(action: { showingEventEditor = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Event")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(DesignSystem.Colors.accent)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.xxl + 8)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                    }
                }
                .padding(.bottom, DesignSystem.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(shortDayTitle(date))
        .inlineNavigationTitle()
        .navigationBarHiddenIfPossible(false)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingEventEditor = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Add event")
            }
        }
        .inkSlateSheet(item: $selectedEvent) { selection in
            EventDetailView(event: selection.event, manager: manager)
        }
        .inkSlateSheet(isPresented: $showingEventEditor) {
            EventEditorView(event: nil, startTime: defaultNewEventStart, manager: manager)
        }
        .onAppear {
            manager.selectedDate = date
            manager.loadEvents(center: date)
        }
    }
    
    private var defaultNewEventStart: Date {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Date()
        }
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        return cal.date(from: components) ?? date
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
    }
    
    private func formatDateSubtitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func shortDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Month Calendar Grid
struct MonthCalendarGrid: View {
    let currentMonth: Date
    @Binding var selectedDate: Date
    @ObservedObject var manager: CalendarManager
    let onDaySelected: (Date) -> Void
    
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
                            onDaySelected(date)
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
            .inkSlateSheet(isPresented: $showingEdit) {
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
    @State private var selectedEvent: IdentifiedCalendarEvent?
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
            let eventDay: Date
            if event.isAllDay, let start = event.startDate {
                eventDay = CalendarManager.allDayCivilDay(from: start, displayCalendar: cal)
            } else {
                eventDay = cal.startOfDay(for: event.startDate ?? .distantPast)
            }
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
                                                    selectedEvent = IdentifiedCalendarEvent(event: row.event)
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
            .inkSlateSheet(item: $selectedEvent) { selection in
                EventDetailView(event: selection.event, manager: manager)
            }
            .inkSlateSheet(isPresented: $showingEventEditor) {
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
    var onRecheck: (() -> Void)? = nil
    
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

                    Button(action: { onRecheck?() }) {
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
        if #available(iOS 17, macOS 14, *) {
            if status == .writeOnly {
                return "InkSlate needs Full Access to show your existing events. Write Only can’t display them. Open Settings → InkSlate → Calendars and choose Full Access."
            }
        }
        
        if status == .denied || status == .restricted {
            #if os(macOS)
            return "Calendar access is turned off. Open System Settings → Privacy & Security → Calendars and enable InkSlate with Full Access."
            #else
            return "Calendar access is turned off. Open Settings → InkSlate → Calendars and enable Full Access to view and manage your events."
            #endif
        }
        
        return "Please grant full calendar access to view and manage your events."
    }
    
    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
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
        hasValidDateRange &&
        !isSaving
    }
    
    private var hasValidDateRange: Bool {
        if isAllDay {
            return dayCalendar.startOfDay(for: endDate) >= dayCalendar.startOfDay(for: startDate)
        }
        return endDate > startDate
    }
    
    private var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a title"
        }
        if selectedCalendar == nil {
            return "Please select a calendar"
        }
        if isAllDay {
            if dayCalendar.startOfDay(for: endDate) < dayCalendar.startOfDay(for: startDate) {
                return "End date must be on or after the start date"
            }
        } else if endDate <= startDate {
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
                    if isAllDay {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                            .environment(\.timeZone, TimeZone.current)
                        DatePicker("Ends", selection: $endDate, in: dayCalendar.startOfDay(for: startDate)..., displayedComponents: .date)
                            .environment(\.timeZone, TimeZone.current)
                    } else {
                        DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, TimeZone.current)
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, TimeZone.current)
                    }
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
                    // Keep the selected calendar day; pin to noon so DatePicker/timezone math can't slip a day.
                    startDate = Self.noon(on: startDate, calendar: dayCalendar)
                    endDate = Self.noon(on: endDate, calendar: dayCalendar)
                    if dayCalendar.startOfDay(for: endDate) < dayCalendar.startOfDay(for: startDate) {
                        endDate = startDate
                    }
                } else {
                    let day = dayCalendar.startOfDay(for: startDate)
                    let hour = dayCalendar.component(.hour, from: Date())
                    startDate = dayCalendar.date(bySettingHour: max(hour, 9), minute: 0, second: 0, of: day) ?? day
                    endDate = startDate.addingTimeInterval(3600)
                }
            }
            .onChange(of: startDate) { _, newValue in
                if isAllDay {
                    let startDay = dayCalendar.startOfDay(for: newValue)
                    if dayCalendar.startOfDay(for: endDate) < startDay {
                        endDate = Self.noon(on: newValue, calendar: dayCalendar)
                    }
                } else if endDate <= newValue {
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
            isAllDay = event.isAllDay
            location = event.location ?? ""
            notes = event.notes ?? ""
            selectedCalendar = event.calendar
            if event.isAllDay {
                // Read floating all-day civil day (EventKit uses GMT midnight under the hood).
                // EventKit all-day end is exclusive — convert to inclusive end for the UI.
                startDate = Self.noon(
                    on: Self.civilDay(fromAllDay: event.startDate, localCalendar: dayCalendar),
                    calendar: dayCalendar
                )
                let endExclusive = Self.civilDay(fromAllDay: event.endDate, localCalendar: dayCalendar)
                let startDay = dayCalendar.startOfDay(for: startDate)
                if endExclusive <= startDay {
                    endDate = startDate
                } else {
                    let inclusiveEnd = dayCalendar.date(byAdding: .day, value: -1, to: endExclusive) ?? startDay
                    endDate = Self.noon(on: max(inclusiveEnd, startDay), calendar: dayCalendar)
                }
            } else {
                startDate = event.startDate
                endDate = event.endDate
            }
        } else {
            let base = startTime ?? Date()
            startDate = base
            endDate = base.addingTimeInterval(3600)
            selectedCalendar = manager.allCalendars.first(where: { $0.allowsContentModifications })
                ?? manager.store.defaultCalendarForNewEvents
        }
    }
    
    /// Noon avoids DatePicker / timezone edge cases around local midnight.
    private static func noon(on date: Date, calendar cal: Calendar) -> Date {
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
    
    private static func civilDay(fromAllDay date: Date, localCalendar cal: Calendar) -> Date {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let ymd = gmt.dateComponents([.year, .month, .day], from: date)
        return cal.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day))
            ?? cal.startOfDay(for: date)
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
        
        guard hasValidDateRange else {
            errorMessage = validationMessage ?? "Invalid date range."
            showingError = true
            return
        }
        
        isSaving = true
        
        let eventToSave = event ?? EKEvent(eventStore: manager.store)
        eventToSave.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        eventToSave.location = location.isEmpty ? nil : location
        eventToSave.notes = notes.isEmpty ? nil : notes
        eventToSave.calendar = calendar
        
        if isAllDay {
            // Consensus from EventKit / Stack Overflow / working samples:
            // 1) set isAllDay BEFORE dates
            // 2) use local startOfDay
            // 3) single-day: endDate == startDate (EventKit expands storage itself)
            // 4) multi-day: exclusive end = day after last inclusive day
            // 5) do NOT force a GMT timeZone (that shifts US timezones back one day)
            let startDay = dayCalendar.startOfDay(for: startDate)
            let endInclusive = dayCalendar.startOfDay(for: endDate)
            eventToSave.isAllDay = true
            eventToSave.startDate = startDay
            if endInclusive <= startDay {
                eventToSave.endDate = startDay
            } else if let exclusiveEnd = dayCalendar.date(byAdding: .day, value: 1, to: endInclusive) {
                eventToSave.endDate = exclusiveEnd
            } else {
                eventToSave.endDate = startDay
            }
        } else {
            eventToSave.isAllDay = false
            eventToSave.startDate = startDate
            eventToSave.endDate = endDate
        }
        
        do {
            try manager.store.save(eventToSave, span: .thisEvent, commit: true)
            manager.selectedDate = isAllDay ? dayCalendar.startOfDay(for: startDate) : startDate
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
