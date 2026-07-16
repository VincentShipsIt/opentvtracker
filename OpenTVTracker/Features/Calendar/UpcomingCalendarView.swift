import SwiftUI

private enum UpcomingCalendarMode: String, CaseIterable, Hashable {
    case day
    case week
    case agenda

    var label: LocalizedStringResource {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .agenda: "Agenda"
        }
    }
}

enum UpcomingCalendarDestination: Hashable {
    case title(MediaTitle.ID)
    case episode(EpisodeDetailRoute)
}

struct UpcomingCalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.timeZone) private var timeZone
    @State private var mode: UpcomingCalendarMode = .week
    @State private var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    @State private var includedStates: Set<WatchState> = [.watching, .planned, .paused]
    @State private var selectedServicesOnly = false
    @State private var days: [UpcomingCalendarDay] = []

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    controls
                    statusBanner
                    schedule
                }
                .padding(.vertical, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UpcomingCalendarDestination.self) { destination in
            switch destination {
            case .title(let titleID):
                MediaDetailView(titleID: titleID)
            case .episode(let route):
                EpisodeDetailView(route: route)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Button("Refresh schedule", systemImage: "arrow.clockwise") {
                    Task {
                        await model.refreshUpcomingCalendar(force: true)
                        updateSchedule()
                    }
                }
                .disabled(model.isRefreshingUpcomingCalendar)
            }
        }
        .task {
            updateSchedule()
            await model.refreshUpcomingCalendar()
            updateSchedule()
        }
        .onChange(of: mode) { updateSchedule() }
        .onChange(of: selectedDate) { updateSchedule() }
        .onChange(of: includedStates) { updateSchedule() }
        .onChange(of: selectedServicesOnly) { updateSchedule() }
        .onChange(of: model.selectedProviderIDs) { updateSchedule() }
        .onChange(of: model.titles) { updateSchedule() }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("Calendar view", selection: $mode) {
                ForEach(UpcomingCalendarMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode != .agenda {
                DateRangeNavigator(
                    title: selectedRangeTitle,
                    previousLabel: previousRangeLabel,
                    nextLabel: nextRangeLabel,
                    onPrevious: { moveSelection(by: -1) },
                    onToday: { selectedDate = localCalendar.startOfDay(for: .now) },
                    onNext: { moveSelection(by: 1) }
                )
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var statusBanner: some View {
        UpcomingCalendarStatusBanner(
            isRefreshing: model.isRefreshingUpcomingCalendar,
            errorMessage: model.upcomingCalendarRefreshError,
            lastRefreshedAt: model.upcomingCalendarLastRefreshedAt,
            hasItems: !days.isEmpty,
            regionCode: model.streamingRegion.code,
            timeZoneIdentifier: timeZone.identifier
        )
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    @ViewBuilder
    private var schedule: some View {
        if days.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "calendar.badge.exclamationmark",
                description: Text(emptyDescription)
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, 32)
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(days) { day in
                    UpcomingCalendarDaySection(day: day, calendar: localCalendar)
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu("Filter schedule", systemImage: "line.3.horizontal.decrease.circle") {
            Section("Tracked state") {
                ForEach(WatchState.allCases, id: \.self) { state in
                    Button {
                        toggle(state)
                    } label: {
                        Label(state.label, systemImage: includedStates.contains(state) ? "checkmark" : state.symbol)
                    }
                }
            }

            Section("Streaming services") {
                Button {
                    selectedServicesOnly.toggle()
                } label: {
                    Label(
                        "Only my selected services",
                        systemImage: selectedServicesOnly ? "checkmark" : "play.tv"
                    )
                }
            }
        }
        .accessibilityHint("Filters the schedule by tracking state and streaming service")
    }

    private var localCalendar: Calendar {
        var calendar = environmentCalendar
        calendar.timeZone = timeZone
        return calendar
    }

    private var selectedRange: DateInterval {
        let selectedStart = localCalendar.startOfDay(for: selectedDate)
        switch mode {
        case .day:
            let end = localCalendar.date(byAdding: .day, value: 1, to: selectedStart) ?? selectedStart
            return DateInterval(start: selectedStart, end: end)
        case .week:
            return localCalendar.dateInterval(of: .weekOfYear, for: selectedStart)
                ?? DateInterval(
                    start: selectedStart,
                    end: localCalendar.date(byAdding: .day, value: 7, to: selectedStart) ?? selectedStart
                )
        case .agenda:
            let today = localCalendar.startOfDay(for: .now)
            let end = localCalendar.date(byAdding: .day, value: 90, to: today) ?? today
            return DateInterval(start: today, end: end)
        }
    }

    private var selectedRangeTitle: String {
        switch mode {
        case .day:
            selectedRange.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .week:
            let finalDay = localCalendar.date(byAdding: .day, value: -1, to: selectedRange.end)
                ?? selectedRange.end
            return "\(selectedRange.start.formatted(.dateTime.month(.abbreviated).day())) – \(finalDay.formatted(.dateTime.month(.abbreviated).day()))"
        case .agenda:
            "Next 90 days"
        }
    }

    private var previousRangeLabel: String {
        mode == .week ? "Previous week" : "Previous day"
    }

    private var nextRangeLabel: String {
        mode == .week ? "Next week" : "Next day"
    }

    private var emptyTitle: String {
        if includedStates.isEmpty {
            return "No tracked states selected"
        }
        if selectedServicesOnly, model.selectedProviderIDs.isEmpty {
            return "No streaming services selected"
        }
        return mode == .agenda ? "No upcoming releases" : "Nothing scheduled"
    }

    private var emptyDescription: String {
        if includedStates.isEmpty {
            return "Choose at least one tracked state from the filter menu."
        }
        if selectedServicesOnly, model.selectedProviderIDs.isEmpty {
            return "Choose services in Discover, or turn off the service filter."
        }
        if model.upcomingCalendarRefreshError != nil {
            return "Saved metadata has no events in this range. Refresh again when you are online."
        }
        return "Try another range or adjust the tracked-state and service filters."
    }

    private func moveSelection(by amount: Int) {
        let component: Calendar.Component = mode == .week ? .weekOfYear : .day
        selectedDate = localCalendar.date(byAdding: component, value: amount, to: selectedDate) ?? selectedDate
    }

    private func toggle(_ state: WatchState) {
        if includedStates.contains(state) {
            includedStates.remove(state)
        } else {
            includedStates.insert(state)
        }
    }

    private func updateSchedule() {
        let range = selectedRange
        let finalDay = localCalendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let providerFilter = selectedServicesOnly ? model.selectedProviderIDs : nil
        let items = UpcomingCalendarEngine.items(
            from: model.titles,
            in: range.start...finalDay,
            includedStates: includedStates,
            providerIDs: providerFilter,
            calendar: localCalendar
        )
        days = UpcomingCalendarEngine.days(from: items, calendar: localCalendar)
    }
}

#Preview {
    NavigationStack {
        UpcomingCalendarView()
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
            .environment(\.allowsRemoteArtwork, false)
    }
}
