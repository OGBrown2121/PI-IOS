import SwiftUI

struct ProfileMediaShowcaseSection: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    let title: String
    let icon: String
    let accentColor: Color
    let items: [ProfileMediaItem]

    @State private var selectedMedia: ProfileMediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall * 1.5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                if let pinnedCount = pinnedCountLabel {
                    Text(pinnedCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            selectedMedia = item
                        } label: {
                            ProfileMediaCardView(item: item, accentColor: accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(item: $selectedMedia) { media in
            NavigationStack {
                ProfileMediaDetailView(
                    media: media,
                    firestoreService: di.firestoreService,
                    storageService: di.storageService,
                    currentUserProvider: { appState.currentUser }
                )
            }
        }
    }

    private var pinnedCountLabel: String? {
        guard items.isEmpty == false else { return nil }
        let audioCount = items.filter { $0.format == .audio }.count
        let videoCount = items.filter { $0.format == .video }.count
        if audioCount > 0 && videoCount > 0 {
            return "\(audioCount) audio • \(videoCount) video"
        } else if audioCount > 0 {
            return "\(audioCount) audio"
        } else if videoCount > 0 {
            return "\(videoCount) video"
        } else {
            return "\(items.count) uploads"
        }
    }
}

private struct ProfileMediaCardView: View {
    let item: ProfileMediaItem
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mediaPreview
                .frame(width: 150, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)

            if item.caption.isEmpty == false {
                Text(item.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(item.displayCategoryTitle)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(accentColor)
        }
        .frame(width: 170)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay {
            if item.isPinned {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "star.fill")
                            .foregroundStyle(accentColor)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .shadow(color: accentColor.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        switch item.format {
        case .photo, .gallery:
            if let url = item.mediaURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderIcon
                }
            } else {
                placeholderIcon
            }
        case .video:
            if let thumbnailURL = item.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay(alignment: .center) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 6)
                        }
                } placeholder: {
                    placeholderIcon
                }
            } else {
                placeholderIcon.overlay {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 28, weight: .bold))
                }
            }
        case .audio:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.15))
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(accentColor)
            }
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.15))
            Image(systemName: item.format.iconName)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(accentColor)
        }
    }
}
