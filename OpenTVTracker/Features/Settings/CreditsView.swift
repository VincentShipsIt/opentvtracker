import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenTV Tracker") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("Storage", value: "On this iPhone")
                    LabeledContent("Sharing", value: "Not configured")
                    LabeledContent("AI", value: "Deterministic preview")
                }

                Section("Data sources") {
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
                    Text("Tracking works locally. Partner sharing will use invitation-only iCloud records separate from the personal library. AI will be optional and will never embed provider credentials in the app.")
                }

                Section("Open source") {
                    Text("MIT licensed. The repository remains private during the foundation phase.")
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
}

#Preview {
    CreditsView()
}
