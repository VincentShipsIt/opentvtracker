import SafariServices
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
            Group {
                if #available(iOS 26, *) {
                    WebView(url: trailer.url)
                } else {
                    SafariView(url: trailer.url)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
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

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) { }
}
