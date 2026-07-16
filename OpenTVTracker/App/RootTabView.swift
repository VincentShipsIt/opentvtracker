import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case together
    case library
    case profile
}

struct RootTabView: View {
    @State private var selection: AppTab = .today
    @State private var presentsAssistant = false

    var body: some View {
        Group {
            switch selection {
            case .today:
                TodayView()
                    .accessibilityIdentifier("tab.today")
            case .discover:
                DiscoverView()
                    .accessibilityIdentifier("tab.discover")
            case .together:
                TogetherView()
                    .accessibilityIdentifier("tab.together")
            case .library:
                LibraryView()
                    .accessibilityIdentifier("tab.library")
            case .profile:
                ProfileView()
                    .accessibilityIdentifier("tab.profile")
            }
        }
        .tint(.accentColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OpenTVTabBar(selection: $selection) {
                presentsAssistant = true
            }
        }
        .fullScreenCover(isPresented: $presentsAssistant) {
            DiscoveryAssistantView()
        }
        .preferredColorScheme(.dark)
    }
}

private struct OpenTVTabBar: View {
    @Binding var selection: AppTab
    let onAskAI: () -> Void

    private let primaryTabs = [
        OpenTVTabItem(tab: .today, title: "Home", symbol: "house.fill"),
        OpenTVTabItem(tab: .together, title: "Together", symbol: "person.2.fill"),
        OpenTVTabItem(tab: .library, title: "Library", symbol: "rectangle.stack.fill"),
        OpenTVTabItem(tab: .profile, title: "Profile", symbol: "person.crop.circle.fill")
    ]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                GlassSurface(cornerRadius: 28) {
                    HStack(spacing: 0) {
                        ForEach(primaryTabs, id: \.tab) { item in
                            tabButton(item.tab, title: item.title, symbol: item.symbol)
                        }
                    }
                    .padding(5)
                }
                .frame(maxWidth: .infinity)

                GlassSurface(cornerRadius: 28) {
                    HStack(spacing: 0) {
                        tabButton(.discover, title: "Search", symbol: "magnifyingglass")

                        Button(action: onAskAI) {
                            tabLabel(title: "AI", symbol: "sparkles", isSelected: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the OpenTV assistant")
                        .accessibilityIdentifier("tab.ai")
                    }
                    .padding(5)
                }
                .frame(width: 112)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            tabLabel(title: title, symbol: symbol, isSelected: selection == tab)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == tab ? "Selected" : "")
        .accessibilityIdentifier("tab.\(title.lowercased())")
    }

    private func tabLabel(title: String, symbol: String, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: Capsule()
        )
        .contentShape(.rect)
    }
}

private struct OpenTVTabItem {
    let tab: AppTab
    let title: String
    let symbol: String
}

#Preview {
    RootTabView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
