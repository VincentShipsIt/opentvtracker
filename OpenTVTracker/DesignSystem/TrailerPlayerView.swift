import Foundation
import SwiftUI
import WebKit

extension EnvironmentValues {
    @Entry var forcesTrailerPlaybackFailure = false
}

struct TrailerPresentation: Identifiable, Hashable {
    let title: String
    let sourceURL: URL
    let embedURL: URL
    let externalURL: URL

    init?(title: String, sourceURL: URL) {
        guard let urls = TrailerURLNormalizer.urls(for: sourceURL) else { return nil }
        self.title = title
        self.sourceURL = sourceURL
        embedURL = urls.embed
        externalURL = urls.external
    }

    var id: String { embedURL.absoluteString }
}

enum TrailerURLNormalizer {
    struct URLs: Hashable {
        let embed: URL
        let external: URL
    }

    static func urls(for sourceURL: URL) -> URLs? {
        guard sourceURL.scheme?.lowercased() == "https",
              sourceURL.user == nil,
              sourceURL.password == nil,
              sourceURL.port == nil || sourceURL.port == 443,
              let host = sourceURL.host?.lowercased(),
              let videoID = videoID(from: sourceURL, host: host),
              isValidVideoID(videoID),
              var embed = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(videoID)"),
              var external = URLComponents(string: "https://www.youtube.com/watch") else {
            return nil
        }

        embed.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0")
        ]
        external.queryItems = [URLQueryItem(name: "v", value: videoID)]
        guard let embedURL = embed.url, let externalURL = external.url else { return nil }
        return URLs(embed: embedURL, external: externalURL)
    }

    static func safeExternalURL(_ sourceURL: URL) -> URL? {
        guard sourceURL.scheme?.lowercased() == "https",
              sourceURL.user == nil,
              sourceURL.password == nil else {
            return nil
        }
        return sourceURL
    }

    private static func videoID(from url: URL, host: String) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "youtu.be", "www.youtu.be":
            return pathComponents.first
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if url.path == "/watch" {
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value
            }
            guard pathComponents.count == 2,
                  pathComponents[0] == "embed" || pathComponents[0] == "shorts" else {
                return nil
            }
            return pathComponents[1]
        case "youtube-nocookie.com", "www.youtube-nocookie.com":
            guard pathComponents.count == 2, pathComponents[0] == "embed" else { return nil }
            return pathComponents[1]
        default:
            return nil
        }
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.count == 11 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }
}

enum TrailerPlaybackState: Equatable {
    case loading
    case ready
    case failed

    var showsFallback: Bool {
        self == .failed
    }
}

struct TrailerPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.forcesTrailerPlaybackFailure) private var forcesTrailerPlaybackFailure
    let trailer: TrailerPresentation
    @State private var playbackState = TrailerPlaybackState.loading
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if forcesTrailerPlaybackFailure || playbackState.showsFallback {
                    ContentUnavailableView {
                        Label("Trailer could not play", systemImage: "play.slash.fill")
                    } description: {
                        Text("Try the in-app player again or open this trailer directly on YouTube.")
                    } actions: {
                        Button("Try again") {
                            playbackState = .loading
                            reloadID = UUID()
                        }
                        .adaptiveGlassButton(prominent: true)
                    }
                    .accessibilityIdentifier("trailer.playback-fallback")
                } else {
                    InlineTrailerWebView(url: trailer.embedURL) { state in
                        playbackState = state
                    }
                    .id(reloadID)
                    .overlay {
                        if playbackState == .loading {
                            ProgressView("Loading trailer…")
                        }
                    }
                }

                Divider()

                Link(destination: trailer.externalURL) {
                    Label("Open trailer on YouTube", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton()
                .padding()
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

private struct InlineTrailerWebView: UIViewRepresentable {
    let url: URL
    let onStateChange: (TrailerPlaybackState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChange: onStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.load(URLRequest(url: url, timeoutInterval: 12))
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onStateChange: (TrailerPlaybackState) -> Void

        init(onStateChange: @escaping (TrailerPlaybackState) -> Void) {
            self.onStateChange = onStateChange
        }

        func webView(_: WKWebView, didFinish _: WKNavigation?) {
            onStateChange(.ready)
        }

        func webView(_: WKWebView, didFail _: WKNavigation?, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onStateChange(.failed)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onStateChange(.failed)
        }

        func webViewWebContentProcessDidTerminate(_: WKWebView) {
            onStateChange(.failed)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.allow)
                return
            }
            let url = navigationAction.request.url
            let isAllowed = url?.scheme == "https"
                && url?.host?.lowercased() == "www.youtube-nocookie.com"
                && url?.path.hasPrefix("/embed/") == true
            decisionHandler(isAllowed ? .allow : .cancel)
        }
    }
}
