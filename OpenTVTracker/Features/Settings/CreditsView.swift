import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenTV Tracker") {
                    LabeledContent("Version", value: Self.marketingVersion)
                    LabeledContent("Storage", value: "Local SwiftData")
                    LabeledContent("Sharing", value: "Optional private iCloud")
                    LabeledContent("AI", value: "Optional · off by default")
                }

                Section("Data sources") {
                    LabeledContent(
                        "Catalog status",
                        value: AppServiceConfiguration.apiBaseURL == nil ? "Live TVmaze + official cinema feeds" : "Live operator proxy + TVmaze fallback"
                    )
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    Text("Streaming availability data is provided by JustWatch through TMDB and may vary by region.")
                    if let url = URL(string: "https://www.themoviedb.org") {
                        Link("The Movie Database", destination: url)
                    }
                    if let url = URL(string: "https://www.justwatch.com") {
                        Link("JustWatch", destination: url)
                    }
                }

                Section("Privacy direction") {
                    Text("Tracking works locally. Partner sharing uses invitation-only iCloud records separate from the personal library. AI reranking is opt-in and uses the user's OpenRouter key from this iPhone's Keychain.")
                }

                Section("Data ownership") {
                    Text(
                        """
                        A complete, versioned JSON backup can be exported without an account or support request. \
                        CSV exports keep titles, diary entries, custom lists, watch events, and private shared conversations readable in common tools.
                        """
                    )
                    Text("If the hosted catalog proxy is unavailable, local tracking, import, export, deterministic recommendations, TVmaze fallback, and official cinema links keep working.")
                }

                Section("Open source") {
                    Text("MIT licensed. The app remains useful locally if official hosted services change or end, and forks can operate their own provider proxy.")
                    if let url = URL(string: "https://github.com/VincentShipsIt/opentvtracker") {
                        Link("Repository", destination: url)
                    }
                }
            }
            .navigationTitle("Credits & privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static var marketingVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.1"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }
}

#Preview {
    CreditsView()
}
