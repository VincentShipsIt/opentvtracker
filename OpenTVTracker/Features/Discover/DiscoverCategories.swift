import SwiftUI

struct DiscoverCategoryRail: View {
    let sections: [DiscoverCategorySection]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Browse like a menu",
                subtitle: "Pick a category. We show what is newest on your services."
            )
            .padding(.horizontal, AppTheme.horizontalPadding)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(sections) { section in
                        NavigationLink(value: section.category) {
                            DiscoverCategoryTile(section: section)
                                .frame(width: 180)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DiscoverCategoryGrid: View {
    let sections: [DiscoverCategorySection]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(sections) { section in
                NavigationLink(value: section.category) {
                    DiscoverCategoryTile(section: section)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DiscoverCategoryTile: View {
    let section: DiscoverCategorySection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryArtwork
                .frame(height: 116)

            VStack(alignment: .leading, spacing: 5) {
                Text(section.category.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)

                if let latestTitle = section.latestTitle {
                    Text("Latest · \(latestTitle.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        }
        .background(
            Color(hex: section.category.palette.primaryHex).opacity(0.13),
            in: RoundedRectangle(cornerRadius: AppTheme.compactRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.compactRadius)
                .strokeBorder(.white.opacity(0.16))
        }
        .compositingGroup()
        .clipShape(.rect(cornerRadius: AppTheme.compactRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens titles in this category")
    }

    private var categoryArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            if let latestTitle = section.latestTitle {
                BackdropArtwork(title: latestTitle, cornerRadius: 0)
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: section.category.palette.primaryHex),
                        Color(hex: section.category.palette.secondaryHex)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [.clear, Color(hex: section.category.palette.secondaryHex).opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            if section.titles.count > 1 {
                PosterArtwork(title: section.titles[1], cornerRadius: 7)
                    .frame(width: 40, height: 59)
                    .padding(10)
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
            }

            Image(systemName: section.category.symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.34), in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.30)) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
                .accessibilityHidden(true)
        }
        .clipped()
    }

    private var accessibilityLabel: String {
        guard let latestTitle = section.latestTitle else { return section.category.title }
        return "\(section.category.title). Latest: \(latestTitle.title), \(latestTitle.year)."
    }
}

struct DiscoveryCategoryPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What sounds good?")
                            .font(.largeTitle.weight(.black))
                        Text("Choose a category, then pick from the newest movies and shows included with your subscriptions.")
                            .foregroundStyle(.secondary)
                    }

                    DiscoverCategoryGrid(sections: sections)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(AmbientBackdrop())
            .navigationTitle("Choose tonight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: DiscoverCategory.self) { category in
                DiscoverCategoryShelfView(category: category)
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private var sections: [DiscoverCategorySection] {
        DiscoverCategorySection.available(in: model.titlesOnSelectedProviders)
    }
}

struct DiscoverCategoryShelfView: View {
    @Environment(AppModel.self) private var model
    let category: DiscoverCategory

    var body: some View {
        let categoryTitles = category.titles(from: model.titlesOnSelectedProviders)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                if let latestTitle = categoryTitles.first {
                    latestCard(title: latestTitle)
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(
                        title: "Newest first",
                        subtitle: "\(categoryTitles.count) picks on your selected services"
                    )

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(categoryTitles) { title in
                            NavigationLink(value: title) {
                                PosterShelfCard(title: title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .background(AmbientBackdrop())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    private func latestCard(title: MediaTitle) -> some View {
        NavigationLink(value: title) {
            ZStack(alignment: .bottomLeading) {
                BackdropArtwork(title: title)
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(.rect(cornerRadius: AppTheme.cardRadius))

                VStack(alignment: .leading, spacing: 7) {
                    Label("Latest in \(category.title)", systemImage: category.symbol)
                        .font(.caption.weight(.bold))
                    Text(title.title)
                        .font(.title.weight(.black))
                    Text(category.subtitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("\(title.year) · \(title.kind.label) · \(title.providers.first?.name ?? "Your services")")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .accessibilityLabel("Latest in \(category.title): \(title.title), \(title.year)")
    }
}

#Preview("Category picker") {
    DiscoveryCategoryPickerView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
