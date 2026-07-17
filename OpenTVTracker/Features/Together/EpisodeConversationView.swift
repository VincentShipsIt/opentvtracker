import ImageIO
import SwiftUI
import UIKit

struct EpisodeConversationView: View {
    @Environment(AppModel.self) private var model
    @State private var revealsSpoilers = false
    @State private var noteText = ""
    @State private var notificationStatus: String?

    let title: MediaTitle
    let season: SeasonSummary
    let episode: EpisodeSummary

    var body: some View {
        if model.isShared(title.id) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(
                    title: "Private episode thread",
                    subtitle: "Invitation-only · attached to this watch event"
                )

                if let watchEvent {
                    if canViewConversation {
                        conversation(watchEvent: watchEvent)
                    } else {
                        spoilerGate
                    }
                } else {
                    emptyThread
                }
            }
            .accessibilityIdentifier("episode.private-thread")
        }
    }

    private var watchEvent: SharedWatchEvent? {
        model.conversationWatchEvent(
            titleID: title.id,
            season: season.number,
            episode: episode.number
        )
    }

    private var canViewConversation: Bool {
        revealsSpoilers || model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }

    private var emptyThread: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
            VStack(alignment: .leading, spacing: 12) {
                Label("No shared watch event yet", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Text("Mark this episode watched together to start a private, spoiler-safe thread for it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Mark watched together", systemImage: "person.2.fill") {
                    model.markEpisodeWatchedTogether(
                        titleID: title.id,
                        season: season,
                        episode: episode
                    )
                }
                .adaptiveGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var spoilerGate: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Conversation hidden until you watch", systemImage: "eye.slash.fill")
                    .font(.headline)
                Text("Notes, emoji, and GIF reactions can reveal how the episode lands.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Reveal spoilers", systemImage: "eye.fill") {
                    revealsSpoilers = true
                }
                .adaptiveGlassButton()
                .accessibilityHint("Shows private notes and reactions for this episode")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func conversation(watchEvent: SharedWatchEvent) -> some View {
        EpisodeConversationContent(
            watchEvent: watchEvent,
            notes: model.sharedEpisodeNotes(watchEventID: watchEvent.id),
            reactions: model.sharedEpisodeReactions(watchEventID: watchEvent.id),
            members: model.sharedSpace.members,
            noteText: $noteText,
            notificationStatus: notificationStatus,
            onReact: { asset in
                model.react(to: watchEvent.id, asset: asset)
            },
            onSendNote: sendNote,
            onEnableNotifications: enableNotifications
        )
    }

    private func sendNote() {
        guard let watchEvent else { return }
        model.addSharedEpisodeNote(noteText, watchEventID: watchEvent.id)
        noteText = ""
    }

    private func enableNotifications() {
        Task {
            let enabled = await model.requestSharedConversationNotifications()
            notificationStatus = enabled
                ? "Private conversation alerts are enabled."
                : "Notifications are off. You can enable them in Settings."
        }
    }
}

private struct EpisodeConversationContent: View {
    let watchEvent: SharedWatchEvent
    let notes: [SharedNote]
    let reactions: [SharedReaction]
    let members: [SpaceMember]
    @Binding var noteText: String
    let notificationStatus: String?
    let onReact: (SharedReactionAsset) -> Void
    let onSendNote: () -> Void
    let onEnableNotifications: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
            VStack(alignment: .leading, spacing: 16) {
                watchEventHeader
                reactionPicker
                conversationEntries
                noteComposer
                notificationControl
            }
            .padding(16)
        }
    }

    private var watchEventHeader: some View {
        HStack {
            Label(
                "S\(watchEvent.season ?? 0) E\(watchEvent.episode ?? 0)",
                systemImage: "lock.fill"
            )
            .font(.subheadline.weight(.semibold))
            Spacer()
            Text(watchEvent.occurredAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var reactionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("React")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(SharedReactionAssetPolicy.emojiAssets) { asset in
                    Button {
                        onReact(asset)
                    } label: {
                        Text(asset.displayValue)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .accessibilityLabel("React \(asset.label)")
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(SharedReactionAssetPolicy.gifAssets) { asset in
                        Button {
                            onReact(asset)
                        } label: {
                            VStack(spacing: 5) {
                                if let resourceName = asset.resourceName {
                                    AnimatedReactionGIF(
                                        resourceName: resourceName,
                                        accessibilityLabel: asset.label
                                    )
                                    .frame(width: 112, height: 68)
                                }
                                Text(asset.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("React with \(asset.label) GIF")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var conversationEntries: some View {
        if notes.isEmpty, reactions.isEmpty {
            Text("No reactions or notes yet. Start the post-episode ritual.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(reactions) { reaction in
                    SharedReactionRow(
                        reaction: reaction,
                        memberName: memberName(for: reaction.memberID)
                    )
                }
                ForEach(notes) { note in
                    SharedNoteRow(
                        note: note,
                        memberName: memberName(for: note.memberID)
                    )
                }
            }
        }
    }

    private var noteComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a private note", text: $noteText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("Shared only with invited members after they pass the spoiler gate")

            HStack {
                Text("\(noteText.count)/1,000")
                    .font(.caption)
                    .foregroundStyle(noteText.count > 1_000 ? .red : .secondary)
                Spacer()
                Button("Send note", systemImage: "paperplane.fill", action: onSendNote)
                    .disabled(trimmedNote.isEmpty || noteText.count > 1_000)
            }
        }
    }

    private var notificationControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Enable private thread alerts", systemImage: "bell.badge") {
                onEnableNotifications()
            }
            .font(.subheadline.weight(.semibold))
            if let notificationStatus {
                Text(notificationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Alerts never include note text, reaction content, or public recipients.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedNote: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func memberName(for memberID: SpaceMember.ID) -> String {
        members.first(where: { $0.id == memberID })?.name ?? "Member"
    }
}

private struct SharedReactionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reaction: SharedReaction
    let memberName: String

    var body: some View {
        HStack(spacing: 10) {
            if let asset = SharedReactionAssetPolicy.asset(for: reaction) {
                if asset.kind == .gif, let resourceName = asset.resourceName {
                    AnimatedReactionGIF(
                        resourceName: resourceName,
                        accessibilityLabel: asset.label,
                        animates: !reduceMotion
                    )
                    .frame(width: 88, height: 54)
                } else {
                    Text(asset.displayValue)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(asset.label)
                }
            } else {
                Text("Reaction")
                    .font(.caption.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(memberName)
                    .font(.subheadline.weight(.semibold))
                Text(reaction.occurredAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SharedNoteRow: View {
    let note: SharedNote
    let memberName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(memberName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(note.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.text)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct AnimatedReactionGIF: UIViewRepresentable {
    let resourceName: String
    let accessibilityLabel: String
    var animates = true

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = accessibilityLabel
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = Self.image(resourceName: resourceName, animates: animates)
        imageView.accessibilityLabel = accessibilityLabel
    }

    private static func image(resourceName: String, animates: Bool) -> UIImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let frames = (0..<CGImageSourceGetCount(source)).compactMap { index in
            CGImageSourceCreateImageAtIndex(source, index, nil).map { UIImage(cgImage: $0) }
        }
        guard let firstFrame = frames.first else { return nil }
        guard animates, frames.count > 1 else { return firstFrame }
        return UIImage.animatedImage(with: frames, duration: Double(frames.count) / 8)
    }
}
