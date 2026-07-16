import SwiftUI
import WebKit

struct TrailerPresentation: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String { url.absoluteString }
}

struct TrailerPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let trailer: TrailerPresentation

    var body: some View {
        NavigationStack {
            WebView(url: trailer.url)
            .navigationTitle("\(trailer.title) trailer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
