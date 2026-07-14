import SwiftUI

enum DiscoverSheet: Identifiable {
    case categories
    case services
    case trailer(TrailerPresentation)

    var id: String {
        switch self {
        case .categories: "categories"
        case .services: "services"
        case .trailer(let trailer): "trailer-\(trailer.id)"
        }
    }
}

struct ServiceManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StreamingProvider.supportedSubscriptions) { provider in
                        Button {
                            model.toggleProvider(provider.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: provider.symbol)
                                    .frame(width: 38, height: 38)
                                    .background(provider.brandHex.map { Color(hex: $0) } ?? .accentColor, in: Circle())
                                    .foregroundStyle(.white)
                                Text(provider.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: model.isProviderSelected(provider.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.isProviderSelected(provider.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("I subscribe to")
                } footer: {
                    Text("Discover and search only include titles available on at least one selected service.")
                }

                Section {
                    Text("Availability will be refreshed by region through TMDB's JustWatch-backed provider data. Provider deep links remain on the source page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Streaming services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
