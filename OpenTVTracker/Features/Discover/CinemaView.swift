import SwiftUI

struct CinemaDiscoveryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink {
            CinemaView()
        } label: {
            AdaptiveHeroSurface(minimumHeight: 190) {
                artwork
                    .accessibilityHidden(true)
            } content: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("IN CINEMAS", systemImage: "ticket.fill")
                        .font(.caption.weight(.black))
                    Text("Movie night in Malta")
                        .font(.title2.weight(.black))
                    Text("Eden · Embassy · Citadel")
                        .font(.subheadline)
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Movies in cinemas around Malta")
        .accessibilityHint("Browse dates, venues, showtimes, and official booking pages")
    }

    @ViewBuilder
    private var artwork: some View {
        if let movie = model.titles.first(where: { $0.kind == .movie }) {
            BackdropArtwork(title: movie)
        } else {
            LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct CinemaView: View {
    private let service: any CinemaProviding
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showings: [CinemaShowing] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(service: any CinemaProviding = MaltaCinemaService()) {
        self.service = service
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                dateRail
                showtimeSection
                venueSection
                sourceNote
            }
            .padding(.vertical, 12)
        }
        .background(AmbientBackdrop())
        .navigationTitle("In cinemas")
        .navigationBarTitleDisplayMode(.large)
        .task(id: selectedDate) { await loadShowings() }
    }

    private var dateRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Pick a day", subtitle: "Cinema listings around Malta and Gozo")
                .padding(.horizontal, AppTheme.horizontalPadding)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(days) { day in
                        Button {
                            selectedDate = day.date
                        } label: {
                            VStack(spacing: 3) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption.weight(.semibold))
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.title3.weight(.black))
                            }
                            .frame(width: 58, height: 58)
                        }
                        .adaptiveGlassButton(prominent: Calendar.current.isDate(day.date, inSameDayAs: selectedDate))
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(
                            Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                                ? .isSelected
                                : []
                        )
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var showtimeSection: some View {
        if isLoading {
            ProgressView("Checking Malta showtimes…")
                .frame(maxWidth: .infinity)
                .padding(24)
        } else if !showings.isEmpty {
            CinemaShowtimeList(showings: showings, venues: service.venues)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(
                    title: "Official listings",
                    subtitle: errorMessage ?? "Open a cinema to see its current programme and book"
                )
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
    }

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Choose a cinema", subtitle: "Direct links to each venue's official listings")
                .padding(.horizontal, AppTheme.horizontalPadding)

            ForEach(service.venues) { venue in
                Link(destination: venue.listingsURL) {
                    GlassSurface(cornerRadius: AppTheme.compactRadius) {
                        HStack(spacing: 14) {
                            Image(systemName: venue.symbol)
                                .font(.title2)
                                .frame(width: 46, height: 46)
                                .background(Color.accentColor.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(venue.name).font(.headline)
                                Text(venue.locality).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .accessibilityHint("Opens the official cinema website")
            }
        }
    }

    private var sourceNote: some View {
        Text("Showtimes are read from Embassy Cinemas' official schedule. Eden and Citadel remain one tap away while their sites do not expose a stable schedule feed.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var days: [CinemaDay] {
        (0..<7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))
                .map(CinemaDay.init)
        }
    }

    private func loadShowings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            showings = try await service.showings(on: selectedDate, region: "MT")
            errorMessage = nil
        } catch {
            showings = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct CinemaShowtimeList: View {
    let showings: [CinemaShowing]
    let venues: [CinemaVenue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Showtimes", subtitle: "Tap a time to book on the cinema's website")
                .padding(.horizontal, AppTheme.horizontalPadding)
            ForEach(groupedTitles, id: \.key) { title, titleShowings in
                GlassSurface(cornerRadius: AppTheme.compactRadius) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.headline)
                        ForEach(titleShowings) { showing in
                            Link(destination: showing.bookingURL) {
                                HStack {
                                    Text(showing.startsAt.formatted(date: .omitted, time: .shortened))
                                        .font(.headline.monospacedDigit())
                                    Text(venueName(showing.venueID))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let format = showing.format { Text(format).font(.caption.weight(.bold)) }
                                    Image(systemName: "ticket")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
    }

    private var groupedTitles: [(key: String, value: [CinemaShowing])] {
        Dictionary(grouping: showings, by: \.title)
            .map { (key: $0.key, value: $0.value.sorted { $0.startsAt < $1.startsAt }) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    private func venueName(_ id: CinemaVenue.ID) -> String {
        venues.first(where: { $0.id == id })?.name ?? "Cinema"
    }
}

struct TitleCinemaAvailability: View {
    let title: MediaTitle
    private let service: any CinemaProviding
    @State private var showings: [CinemaShowing] = []

    init(title: MediaTitle, service: any CinemaProviding = MaltaCinemaService()) {
        self.title = title
        self.service = service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "In Malta cinemas", subtitle: availabilitySubtitle)
            if !showings.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(showings.prefix(8)) { showing in
                            Link(destination: showing.bookingURL) {
                                VStack(spacing: 3) {
                                    Text(showing.startsAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                    Text(showing.startsAt.formatted(date: .omitted, time: .shortened))
                                        .font(.headline.monospacedDigit())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .adaptiveGlassButton()
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            NavigationLink {
                CinemaView()
            } label: {
                Label("Check Malta cinemas", systemImage: "ticket.fill")
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
        }
        .task { await load() }
    }

    private var availabilitySubtitle: String {
        showings.isEmpty ? "Check official Eden, Embassy, and Citadel listings" : "Live showtimes found near you"
    }

    private func load() async {
        guard let fetched = try? await service.showings(on: .now, region: "MT") else { return }
        showings = fetched.filter { showing in
            if let catalogID = showing.catalogID { return catalogID == title.catalogID }
            return showing.title.localizedStandardCompare(title.title) == .orderedSame
        }
    }
}

#Preview {
    NavigationStack { CinemaView() }
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
