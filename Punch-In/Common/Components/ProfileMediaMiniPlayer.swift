import SwiftUI

struct ProfileMediaMiniPlayer: View {
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    @EnvironmentObject private var appState: AppState
    let onExpand: (ProfileMediaItem) -> Void
    @State private var isScrubbing = false
    @State private var scrubbingProgress: Double = 0

    var body: some View {
        if let item = playbackManager.currentItem {
            VStack(spacing: 10) {
                if playbackManager.duration > 0 {
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: {
                                    isScrubbing ? scrubbingProgress : playbackManager.progress
                                },
                                set: { newValue in
                                    isScrubbing = true
                                    scrubbingProgress = newValue
                                }
                            ),
                            in: 0...1
                        ) { isEditing in
                            if isEditing == false {
                                let target = scrubbingProgress
                                isScrubbing = false
                                playbackManager.seek(to: target)
                            }
                        }
                        .tint(Theme.primaryColor)

                        HStack {
                            Text(formatTime(playbackManager.currentTime))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatTime(playbackManager.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView(value: playbackManager.progress)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 12) {
                    coverArt(for: item)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? item.displayCategoryTitle : item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(subtitle(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        playbackManager.togglePlayPause()
                    } label: {
                        Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Theme.primaryColor.opacity(0.15))
                            )
                    }

                    Button {
                        playbackManager.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Close player")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onExpand(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        }
    }

    private func coverArt(for item: ProfileMediaItem) -> some View {
        Group {
            if let cover = item.coverArtURL ?? item.thumbnailURL {
                AsyncImage(url: cover) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground)
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)
        }
    }

    private func subtitle(for item: ProfileMediaItem) -> String {
        if let rating = item.rating(for: appState.currentUser?.id) {
            return "You rated: \(rating)★"
        }
        if item.ratingCount > 0 {
            return String(format: "%.1f★ · %d ratings", item.averageRating, item.ratingCount)
        }
        return item.category.displayTitle
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
