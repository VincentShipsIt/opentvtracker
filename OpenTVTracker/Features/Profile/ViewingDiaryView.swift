import SwiftUI

struct ViewingDiaryView: View {
    @Environment(AppModel.self) private var model
    @State private var displayMode: ViewingDiaryDisplayMode = .timeline
    @State private var visibleMonth = Calendar.autoupdatingCurrent.dateInterval(
        of: .month,
        for: .now
    )?.start ?? .now
    @State private var selectedDate: Date?

    var body: some View {
        let records = model.diaryRecords
        ZStack {
            AmbientBackdrop()

            VStack(spacing: 12) {
                Picker("Diary view", selection: $displayMode) {
                    ForEach(ViewingDiaryDisplayMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.horizontalPadding)

                if records.isEmpty {
                    ContentUnavailableView(
                        "No diary entries yet",
                        systemImage: "book.closed",
                        description: Text("Watched movies and episodes will appear here with their private dates, ratings, and notes.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    switch displayMode {
                    case .timeline:
                        ViewingDiaryTimeline(days: model.diaryDays(from: records))
                    case .calendar:
                        ViewingDiaryCalendar(
                            month: $visibleMonth,
                            selectedDate: $selectedDate,
                            records: records
                        )
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Viewing diary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum ViewingDiaryDisplayMode: String, CaseIterable, Identifiable {
    case timeline
    case calendar

    var id: Self { self }
    var label: String { self == .timeline ? "Timeline" : "Calendar" }
    var symbol: String { self == .timeline ? "list.bullet" : "calendar" }
}

private struct ViewingDiaryTimeline: View {
    let days: [ViewingDiaryDay]

    var body: some View {
        List {
            ForEach(days) { day in
                Section {
                    ForEach(day.records) { record in
                        NavigationLink {
                            MediaDetailView(titleID: record.title.id)
                        } label: {
                            ViewingDiaryRecordRow(record: record)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(day.date.formatted(date: .complete, time: .omitted))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct ViewingDiaryCalendar: View {
    @Binding var month: Date
    @Binding var selectedDate: Date?
    let records: [ViewingDiaryRecord]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.sectionSpacing) {
                monthHeader
                ViewingDiaryMonthGrid(
                    month: month,
                    records: records,
                    selectedDate: $selectedDate
                )

                if let selectedDate {
                    let selectedRecords = records(on: selectedDate)
                    if selectedRecords.isEmpty {
                        ContentUnavailableView(
                            "Nothing watched",
                            systemImage: "calendar",
                            description: Text("Choose a highlighted day to see its diary entries.")
                        )
                    } else {
                        ViewingDiarySelectedDay(date: selectedDate, records: selectedRecords)
                    }
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 36)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") {
                moveMonth(by: -1)
            }
            .labelStyle(.iconOnly)

            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.bold))
            Spacer()

            Button("Next month", systemImage: "chevron.right") {
                moveMonth(by: 1)
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 4)
    }

    private func records(on date: Date) -> [ViewingDiaryRecord] {
        let calendar = Calendar.autoupdatingCurrent
        return records.filter { record in
            guard let watchedAt = record.entry.watchedAt else { return false }
            return calendar.isDate(watchedAt, inSameDayAs: date)
        }
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = Calendar.autoupdatingCurrent.date(byAdding: .month, value: value, to: month) else {
            return
        }
        month = nextMonth
        selectedDate = nil
    }
}

private struct ViewingDiaryMonthGrid: View {
    @Binding var selectedDate: Date?
    let weekdays: [ViewingDiaryWeekday]
    let cells: [ViewingDiaryCalendarCell]

    init(
        month: Date,
        records: [ViewingDiaryRecord],
        selectedDate: Binding<Date?>
    ) {
        _selectedDate = selectedDate
        let calendar = Calendar.autoupdatingCurrent
        let firstDay = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let dayRange = calendar.range(of: .day, in: .month, for: firstDay) ?? 1..<2
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        let counts = Dictionary(grouping: records.compactMap { record -> Date? in
            guard let watchedAt = record.entry.watchedAt else { return nil }
            return calendar.startOfDay(for: watchedAt)
        }, by: { $0 }).mapValues(\.count)

        let emptyCells = (0..<leadingCount).map { offset in
            ViewingDiaryCalendarCell(id: "empty:\(firstDay.timeIntervalSince1970):\(offset)", date: nil, count: 0)
        }
        let dateCells = dayRange.compactMap { day -> ViewingDiaryCalendarCell? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) else { return nil }
            return ViewingDiaryCalendarCell(
                id: "day:\(date.timeIntervalSince1970)",
                date: date,
                count: counts[calendar.startOfDay(for: date), default: 0]
            )
        }
        cells = emptyCells + dateCells

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(calendar.firstWeekday - 1, 0)
        let orderedSymbols = Array(symbols[startIndex...] + symbols[..<startIndex])
        weekdays = orderedSymbols.enumerated().map { offset, symbol in
            ViewingDiaryWeekday(id: offset, symbol: symbol)
        }
    }

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays) { weekday in
                    Text(weekday.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ForEach(cells) { cell in
                    ViewingDiaryCalendarDayButton(
                        cell: cell,
                        isSelected: cell.date.map(isSelected) ?? false,
                        select: { selectedDate = cell.date }
                    )
                }
            }
            .padding(14)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: selectedDate)
    }
}

private struct ViewingDiaryWeekday: Identifiable {
    let id: Int
    let symbol: String
}

private struct ViewingDiaryCalendarCell: Identifiable {
    let id: String
    let date: Date?
    let count: Int
}

private struct ViewingDiaryCalendarDayButton: View {
    let cell: ViewingDiaryCalendarCell
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        if let date = cell.date {
            Button(action: select) {
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(isSelected ? .bold : .regular))
                    Circle()
                        .fill(cell.count > 0 ? Color.accentColor : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(cell.count == 0 ? "Nothing watched" : "\(cell.count) diary entries")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear.frame(height: 42)
                .accessibilityHidden(true)
        }
    }
}

private struct ViewingDiarySelectedDay: View {
    let date: Date
    let records: [ViewingDiaryRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: date.formatted(date: .complete, time: .omitted))
            ForEach(records) { record in
                NavigationLink {
                    MediaDetailView(titleID: record.title.id)
                } label: {
                    GlassSurface(cornerRadius: AppTheme.compactRadius) {
                        ViewingDiaryRecordRow(record: record)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ViewingDiaryRecordRow: View {
    let record: ViewingDiaryRecord

    var body: some View {
        HStack(spacing: 13) {
            PosterArtwork(title: record.title, cornerRadius: 8)
                .frame(width: 54, height: 78)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.title.title)
                    .font(.headline)
                Text(scopeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if record.entry.isRewatch {
                        Label("Rewatch", systemImage: "arrow.clockwise")
                    }
                    if let rating = record.entry.rating {
                        Label(
                            rating.formatted(.number.precision(.fractionLength(1))),
                            systemImage: "star.fill"
                        )
                    }
                    if record.entry.note?.isEmpty == false {
                        Label("Note", systemImage: "note.text")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let watchedAt = record.entry.watchedAt {
                Text(watchedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var scopeLabel: String {
        if let season = record.entry.seasonNumber, let episode = record.entry.episodeNumber {
            let episodeTitle = record.episode?.title ?? "Episode \(episode)"
            return "S\(season) E\(episode) · \(episodeTitle)"
        }
        return record.title.kind == .movie ? "Movie" : "Series"
    }
}

#Preview {
    NavigationStack {
        ViewingDiaryView()
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
            .environment(\.allowsRemoteArtwork, false)
    }
}
