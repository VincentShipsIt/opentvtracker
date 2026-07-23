import SwiftUI

struct DiscoverCategoryCarousel: View {
    let sections: [DiscoverCategorySection]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(sections) { section in
                    NavigationLink(value: section.category) {
                        DiscoverCategoryTile(section: section)
                            .frame(width: 160)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .accessibilityLabel("Browse categories")
    }
}

struct DiscoverCategoryGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sections: [DiscoverCategorySection]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                NavigationLink(value: section.category) {
                    DiscoverCategoryTile(section: section)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 12),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }
}

struct DiscoverCategoryTile: View {
    let section: DiscoverCategorySection

    var body: some View {
        GeometryReader { geometry in
            categoryArtwork
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(hex: section.category.palette.primaryHex).opacity(0.10),
                            Color(hex: section.category.palette.secondaryHex).opacity(0.50),
                            .black.opacity(0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .topLeading) {
                    Image(systemName: section.category.symbol)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(
                            Color(hex: section.category.palette.primaryHex).opacity(0.82),
                            in: Circle()
                        )
                        .padding(10)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.category.title)
                            .font(.headline.weight(.semibold))
                        Text(section.category.subtitle)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .padding(12)
                }
                .compositingGroup()
                .clipShape(.rect(cornerRadius: AppTheme.compactRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.compactRadius)
                        .strokeBorder(.white.opacity(0.18))
                }
        }
        .aspectRatio(1.45, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens titles in this category")
    }

    @ViewBuilder
    private var categoryArtwork: some View {
        if let leadTitle = section.leadTitle {
            BackdropArtwork(title: leadTitle, cornerRadius: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(hex: section.category.palette.primaryHex),
                    Color(hex: section.category.palette.secondaryHex)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private var accessibilityLabel: String {
        guard let leadTitle = section.leadTitle else {
            return "\(section.category.title). \(section.category.subtitle)."
        }
        return "\(section.category.title). Featuring \(leadTitle.title), \(leadTitle.year). \(section.category.subtitle)."
    }
}

struct DiscoveryCategoryPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DiscoverCategoryGrid(sections: sections)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 16)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        title: category == .topRated ? "Highest rated" : "Newest first",
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
        Array(
            repeating: GridItem(.flexible(), spacing: 14),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    private func latestCard(title: MediaTitle) -> some View {
        NavigationLink(value: title) {
            AdaptiveHeroSurface(minimumHeight: 250) {
                BackdropArtwork(title: title, cornerRadius: 0)
                    .accessibilityHidden(true)
            } content: {
                VStack(alignment: .leading, spacing: 7) {
                    Label(category == .topRated ? "Highest rated" : "Latest in \(category.title)", systemImage: category.symbol)
                        .font(.caption.weight(.bold))
                    Text(title.title)
                        .font(.title.weight(.black))
                    Text(category.subtitle)
                        .font(.subheadline)
                    Text("\(title.year) · \(title.kind.label) · \(title.providers.first?.name ?? "Your services")")
                        .font(.caption)
                }
                .foregroundStyle(.white)
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
