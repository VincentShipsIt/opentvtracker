import SwiftUI
import UIKit

struct ViewingAnalyticsSharePayload: Identifiable {
    let id = UUID()
    let text: String
    let image: UIImage
}

@MainActor
enum ViewingAnalyticsShareRenderer {
    static func render(summary: ViewingAnalyticsSummary) -> UIImage? {
        let renderer = ImageRenderer(
            content: ViewingAnalyticsShareCard(summary: summary)
                .frame(width: 1080, height: 1350)
        )
        renderer.scale = 1
        return renderer.uiImage
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ViewingAnalyticsShareCard: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "10142B"), Color(hex: "432B79"), Color(hex: "A03E77")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 660, height: 660)
                .blur(radius: 12)
                .offset(x: 430, y: -510)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 54, weight: .semibold))
                    Text("OpenTV")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                }

                Spacer()

                Text(summary.scope == .personal ? "MY WATCHED LIFE" : "OUR WATCHED LIFE")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(cardDuration)
                    .font(.system(size: 166, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                Text(summary.scope == .personal ? "tracked on screen" : "watched together")
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))

                HStack(spacing: 22) {
                    ShareStat(value: summary.titleCount, label: "TITLES")
                    ShareStat(value: summary.movieCount, label: "MOVIES")
                    ShareStat(value: summary.episodeCount, label: "EPISODES")
                }
                .padding(.top, 72)

                if !summary.genreBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("TOP GENRES")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.64))
                        HStack(spacing: 14) {
                            ForEach(summary.genreBreakdown.prefix(3)) { metric in
                                Text(metric.label)
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 15)
                                    .background(.white.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 58)
                }

                Spacer()

                HStack {
                    Text(summary.scope == .personal ? "My viewing history, privately tracked." : "Our viewing history, privately tracked.")
                    Spacer()
                    Text("#OpenTV")
                        .fontWeight(.bold)
                }
                .font(.system(size: 27, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(76)
            .foregroundStyle(.white)
        }
        .clipped()
    }

    private var cardDuration: String {
        let hours = Double(summary.totalMinutes) / 60
        return "\(hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0)))) HOURS"
    }
}

private struct ShareStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value, format: .number)
                .font(.system(size: 58, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 28))
    }
}
