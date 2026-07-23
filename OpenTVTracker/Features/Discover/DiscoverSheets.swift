import AuthenticationServices
import SwiftUI

enum DiscoverSheet: Identifiable {
    case assistant
    case categories
    case services
    case aiRanking
    case trailer(TrailerPresentation)

    var id: String {
        switch self {
        case .assistant: "assistant"
        case .categories: "categories"
        case .services: "services"
        case .aiRanking: "ai-ranking"
        case .trailer(let trailer): "trailer-\(trailer.id)"
        }
    }
}

struct AIRankingSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isAuthorized = false
    @State private var isAuthorizing = false
    @State private var authorizationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter account") {
                    LabeledContent("Status", value: isAuthorized ? "Connected" : "Not connected")

                    if isAuthorized {
                        Button("Disconnect OpenRouter", role: .destructive) {
                            Task { await disconnect() }
                        }
                        Link(
                            "Manage spend cap or revoke key",
                            destination: URL(string: "https://openrouter.ai/settings/keys")!
                        )
                    } else {
                        Button("Connect OpenRouter") {
                            Task { await connect() }
                        }
                        .disabled(isAuthorizing)
                    }

                    if isAuthorizing {
                        ProgressView("Waiting for OpenRouter…")
                    }
                    if let authorizationError {
                        Text(authorizationError)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle(
                        "Optional AI reranking",
                        isOn: Binding(
                            get: { model.allowsAIReranking },
                            set: { enabled in model.setAIRerankingEnabled(enabled) }
                        )
                    )
                    .disabled(!isAuthorized)
                } footer: {
                    Text("Off by default. Your OpenRouter key is created with OAuth PKCE, kept in this iPhone's Keychain, and used directly. Deterministic recommendations always remain available.")
                }

                Section("Exact payload preview") {
                    LabeledContent("Candidate", value: "TMDB catalog ID")
                    LabeledContent("Signals", value: "local score, mood, max runtime")
                    LabeledContent("Never sent", value: "notes, names, watch events")
                }

                Section("Failure behavior") {
                    Text("A timeout, quota error, revoked key, invalid response, or unavailable provider silently falls back to the reproducible on-device ranking.")
                }
            }
            .task { await refreshAuthorizationStatus() }
            .navigationTitle("AI discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        guard let callbackURL = AppServiceConfiguration.openRouterOAuthCallbackURL else {
            authorizationError = OpenRouterOAuthError.invalidConfiguration.localizedDescription
            return
        }
        isAuthorizing = true
        authorizationError = nil
        defer { isAuthorizing = false }
        do {
            let client = OpenRouterOAuthClient(callbackURL: callbackURL)
            let authorization = try await client.authorizationRequest()
            let callback = try await webAuthenticationSession.authenticate(
                using: authorization.authorizationURL,
                callback: .https(host: authorization.callbackHost, path: authorization.callbackPath),
                additionalHeaderFields: [:]
            )
            try await client.complete(callback, authorization: authorization)
            isAuthorized = true
            model.setAIRerankingEnabled(true)
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    private func disconnect() async {
        guard let callbackURL = AppServiceConfiguration.openRouterOAuthCallbackURL else { return }
        do {
            try await OpenRouterOAuthClient(callbackURL: callbackURL).disconnect()
            isAuthorized = false
            model.setAIRerankingEnabled(false)
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    private func refreshAuthorizationStatus() async {
        guard let callbackURL = AppServiceConfiguration.openRouterOAuthCallbackURL else { return }
        isAuthorized = await OpenRouterOAuthClient(callbackURL: callbackURL).isAuthorized()
        if !isAuthorized, model.allowsAIReranking {
            model.setAIRerankingEnabled(false)
        }
    }
}

struct ServiceManagerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StreamingServicesSettingsView()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct StreamingServicesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
                Text("These choices personalize Discover recommendations and highlight availability. Catalog search can include other services.")
            }

            Section {
                Text("Availability is refreshed for your selected streaming region through TMDB's JustWatch-backed provider data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Streaming services")
        .navigationBarTitleDisplayMode(.inline)
    }
}
