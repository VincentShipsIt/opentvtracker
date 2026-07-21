import SwiftUI

struct ReviewCard: View {
    let review: CommunityReview
    @State private var revealsSpoiler = false

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if review.containsSpoilers && !revealsSpoiler {
                    spoilerPreview
                } else {
                    Text(review.excerpt)
                        .font(.body)
                        .lineLimit(4)
                }

                NavigationLink(value: review) {
                    HStack {
                        Text("Read full review")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the complete review and source details")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ReviewAuthorAvatar(review: review, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(review.author)
                    .font(.headline)
                    .lineLimit(1)
                if let username = visibleUsername {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(review.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let rating = review.rating {
                    RatingLabel(rating: rating)
                }
                if let createdAt = review.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var spoilerPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This review may contain spoilers", systemImage: "eye.slash.fill")
                .font(.subheadline.weight(.semibold))
            Button("Reveal preview") {
                revealsSpoiler = true
            }
            .adaptiveGlassButton()
        }
        .foregroundStyle(.secondary)
    }

    private var visibleUsername: String? {
        guard let username = review.username,
              !username.isEmpty,
              username.localizedCaseInsensitiveCompare(review.author) != .orderedSame else {
            return nil
        }
        return username
    }
}

struct CommunityReviewDetailView: View {
    let review: CommunityReview
    @State private var revealsSpoiler = false

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    authorCard

                    if review.containsSpoilers && !revealsSpoiler {
                        spoilerGate
                    } else {
                        fullReview
                    }

                    if let sourceURL = review.sourceURL {
                        Link(destination: sourceURL) {
                            Label("Open original on \(review.source)", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .adaptiveGlassButton()
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("Community review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var authorCard: some View {
        GlassSurface(tint: .indigo) {
            HStack(spacing: 14) {
                ReviewAuthorAvatar(review: review, size: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(review.author)
                        .font(.title3.weight(.bold))
                    if let username = review.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(review.source)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let rating = review.rating {
                            RatingLabel(rating: rating)
                        }
                    }
                    if let dateLabel {
                        Text(dateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var spoilerGate: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .orange) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Spoiler warning", systemImage: "eye.slash.fill")
                    .font(.title3.weight(.bold))
                Text("This community review may reveal plot details.")
                    .foregroundStyle(.secondary)
                Button("Reveal full review", systemImage: "eye.fill") {
                    revealsSpoiler = true
                }
                .controlSize(.large)
                .adaptiveGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var fullReview: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            Text(review.excerpt)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
    }

    private var dateLabel: String? {
        if let updatedAt = review.updatedAt, updatedAt != review.createdAt {
            return "Updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        if let createdAt = review.createdAt {
            return "Posted \(createdAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }
}

private struct ReviewAuthorAvatar: View {
    let review: CommunityReview
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = review.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.indigo.opacity(0.18))
            .overlay {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
            }
    }

    private var initials: String {
        review.author
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
