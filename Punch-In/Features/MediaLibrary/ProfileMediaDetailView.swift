import AVKit
import SwiftUI

struct ProfileMediaDetailView: View {
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel: ProfileMediaDetailViewModel
    @State private var isPresentingEditor = false
    @State private var isShowingRatingAlert = false
    @State private var isScrubbingPlayback = false
    @State private var scrubbingProgress: Double = 0

    private let firestoreService: any FirestoreService
    private let storageService: any StorageService
    private let currentUserProvider: () -> UserProfile?
    private var libraryViewModel: ProfileMediaLibraryViewModel?
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager

    init(
        media: ProfileMediaItem,
        firestoreService: any FirestoreService,
        storageService: any StorageService,
        currentUserProvider: @escaping () -> UserProfile?,
        libraryViewModel: ProfileMediaLibraryViewModel? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ProfileMediaDetailViewModel(media: media, firestoreService: firestoreService, currentUserProvider: currentUserProvider))
        self.firestoreService = firestoreService
        self.storageService = storageService
        self.currentUserProvider = currentUserProvider
        self.libraryViewModel = libraryViewModel
    }

    var body: some View {
        ZStack {
            backgroundView

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    artworkSection
                    infoSection
                    collaboratorsSection
                    metadataSection
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(viewModel.media.displayCategoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isOwner {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { isPresentingEditor = true }
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                ProfileMediaEditorView(
                    draft: viewModel.makeDraft(),
                    capabilities: ownerCapabilities,
                    onSave: handleEditSave,
                    onDelete: handleDelete,
                    collaboratorSearchFactory: { ProfileMediaCollaboratorSearchViewModel(firestoreService: firestoreService) },
                    isPinLimitReached: false
                )
            }
        }
        .alert("Rating failed", isPresented: $isShowingRatingAlert) {
            Button("Dismiss", role: .cancel) { viewModel.ratingError = nil }
        } message: {
            Text(viewModel.ratingError ?? "Please try again later.")
        }
        .onChangeCompatibility(of: viewModel.ratingError) { error in
            isShowingRatingAlert = error != nil
        }
        .onChangeCompatibility(of: viewModel.media) { updated in
            libraryViewModel?.refreshItem(updated)
        }
        .onChangeCompatibility(of: playbackManager.currentItem) { current in
            guard let current, current.id == viewModel.media.id else { return }
            viewModel.refresh(with: current)
            libraryViewModel?.refreshItem(current)
        }
    }

    private var artworkSection: some View {
        VStack(spacing: 18) {
            ZStack {
                ambientGlow

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.elevatedCardBackground.opacity(colorScheme == .dark ? 0.9 : 0.95))
                    .overlay {
                        if let artwork = viewModel.media.coverArtURL ?? viewModel.media.thumbnailURL ?? viewModel.media.mediaURL, viewModel.media.format != .video {
                            AsyncImage(url: artwork) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    placeholderArtwork
                                case .empty:
                                    ProgressView()
                                @unknown default:
                                    placeholderArtwork
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        } else if viewModel.media.format == .video {
                            ProfileMediaVideoPlayer(media: activeMedia)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        } else {
                            placeholderArtwork
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Theme.primaryGradientStart.opacity(0.6),
                                        Theme.primaryGradientEnd.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.4
                            )
                            .blendMode(.plusLighter)
                            .opacity(colorScheme == .dark ? 0.9 : 0.5)
                    }
                    .shadow(color: Theme.primaryGradientEnd.opacity(0.25), radius: 24, y: 12)
                    .frame(height: 240)
            }

            if viewModel.media.format == .audio {
                Button(action: togglePlayback) {
                    HStack(spacing: 16) {
                        Image(systemName: playbackManager.isPlaying(media: viewModel.media) ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playbackManager.isPlaying(media: viewModel.media) ? "Pause" : "Play")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(playbackSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd], startPoint: .leading, endPoint: .trailing))
                    )
                    .shadow(color: Theme.primaryGradientEnd.opacity(0.25), radius: 12, y: 6)
                }

                if playbackManager.currentItem?.id == viewModel.media.id, playbackManager.duration > 0 {
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: {
                                    isScrubbingPlayback ? scrubbingProgress : playbackManager.progress
                                },
                                set: { newValue in
                                    isScrubbingPlayback = true
                                    scrubbingProgress = newValue
                                }
                            ),
                            in: 0...1
                        ) { editing in
                            if editing == false {
                                let target = scrubbingProgress
                                isScrubbingPlayback = false
                                playbackManager.seek(to: target)
                            }
                        }
                        .tint(Theme.primaryColor)

                        HStack {
                            Text(formatTime(playbackManager.currentTime))
                            Spacer()
                            Text(formatTime(playbackManager.duration))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            highlightChips
            audioVisualizer
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.media.title.isEmpty ? viewModel.media.displayCategoryTitle : viewModel.media.title)
                .font(.title2.weight(.semibold))

            if viewModel.media.caption.isEmpty == false {
                Text(viewModel.media.caption)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            ratingControl
        }
    }

    private var ratingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StarRatingView(
                    rating: viewModel.userRating ?? Int(round(viewModel.media.averageRating)),
                    interactive: viewModel.currentUser != nil
                ) { newValue in
                    Task { await viewModel.submitRating(newValue) }
                }

                if viewModel.media.ratingCount > 0 {
                    Text(String(format: "%.1f · %d", viewModel.media.averageRating, viewModel.media.ratingCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.isUpdatingRating)

            if viewModel.userRating != nil {
                Button("Remove your rating") {
                    Task { await viewModel.removeRating() }
                }
                .font(.caption)
            }
        }
    }

    private var collaboratorsSection: some View {
        Group {
            if viewModel.media.collaborators.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contributors")
                        .font(.headline)

                    ForEach(viewModel.media.collaborators) { collaborator in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collaborator.displayName)
                                    .font(.subheadline.weight(.semibold))
                                if let role = collaborator.role {
                                    Text(role.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: collaborator.kind == .studio ? "building.2" : "person")
                        }
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            if let duration = viewModel.media.durationSeconds {
                Text("Duration: \(formatted(duration: duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            let playCount = activeMedia.playCount
            Text("\(formattedPlayCount(playCount)) \(playCount == 1 ? "play" : "plays")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Uploaded: \(viewModel.media.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var backgroundView: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            RadialGradient(
                colors: [
                    Theme.primaryGradientStart.opacity(colorScheme == .dark ? 0.55 : 0.35),
                    .clear
                ],
                center: .topLeading,
                startRadius: 60,
                endRadius: 420
            )
            .blur(radius: 80)
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    Theme.primaryGradientEnd.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    .clear
                ],
                startPoint: .bottomTrailing,
                endPoint: .topLeading
            )
            .blur(radius: 90)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(Theme.primaryGradientStart.opacity(colorScheme == .dark ? 0.45 : 0.25))
                .frame(width: 320, height: 320)
                .offset(x: -140, y: -120)
                .blur(radius: 90)

            Circle()
                .fill(Theme.primaryGradientEnd.opacity(colorScheme == .dark ? 0.5 : 0.28))
                .frame(width: 340, height: 340)
                .offset(x: 150, y: 110)
                .blur(radius: 110)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var highlightChips: some View {
        let chips = highlightChipData()
        if chips.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { entry in
                        chipView(icon: entry.element.icon, text: entry.element.text)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .transition(.opacity)
        }
    }

    private func highlightChipData() -> [(icon: String, text: String)] {
        var chips: [(icon: String, text: String)] = [
            ("tag.fill", viewModel.media.displayCategoryTitle)
        ]

        chips.append(("sparkles", formatDisplayName))

        if let duration = viewModel.media.durationSeconds, viewModel.media.format == .audio {
            chips.append(("clock.fill", formatted(duration: duration)))
        }

        if viewModel.media.ratingCount > 0 {
            let average = String(format: "%.1f★", viewModel.media.averageRating)
            chips.append(("star.fill", "\(average) • \(viewModel.media.ratingCount)"))
        }

        return chips
    }

    private func chipView(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(Color.white)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.primaryGradientStart.opacity(colorScheme == .dark ? 0.85 : 0.7),
                            Theme.primaryGradientEnd.opacity(colorScheme == .dark ? 0.85 : 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25), lineWidth: 0.6)
        )
        .shadow(color: Theme.primaryGradientEnd.opacity(0.25), radius: 10, y: 4)
    }

    private var formatDisplayName: String {
        switch viewModel.media.format {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .photo:
            return "Photo"
        case .gallery:
            return "Gallery"
        }
    }

    @ViewBuilder
    private var audioVisualizer: some View {
        if viewModel.media.format == .audio {
            TimelineView(.periodic(from: Date(), by: 0.18)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let isPlaying = playbackManager.isPlaying(media: viewModel.media)
                let amplitude = isPlaying ? 1.0 : 0.3

                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.primaryGradientStart,
                                        Theme.primaryGradientEnd
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 8, height: visualizerHeight(for: time, index: index, amplitude: amplitude))
                            .animation(.easeInOut(duration: 0.25), value: time)
                    }
                }
                .frame(height: 36)
                .padding(.top, 4)
                .opacity(isPlaying ? 1 : 0.75)
                .animation(.easeInOut(duration: 0.3), value: isPlaying)
            }
            .transition(.opacity)
        } else {
            EmptyView()
        }
    }

    private func visualizerHeight(for time: TimeInterval, index: Int, amplitude: Double) -> CGFloat {
        let base = sin(time * 2.1 + Double(index) * 0.7)
        let secondary = cos(time * 1.6 + Double(index) * 0.45)
        let combined = (base + secondary) / 2
        let normalized = 0.5 + combined * amplitude * 0.5
        let clamped = max(0.2, min(normalized, 1))
        return CGFloat(12 + clamped * 30)
    }

    private var playbackSubtitle: String {
        if playbackManager.isPlaying(media: viewModel.media) {
            return "Now playing"
        }
        return "Tap to listen"
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardBackground)
            Image(systemName: "music.note")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)
        }
    }

    private func formatted(duration: Double) -> String {
        formatTime(duration)
    }

    private func formattedPlayCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private var activeMedia: ProfileMediaItem {
        if let current = playbackManager.currentItem, current.id == viewModel.media.id {
            return current
        }
        return viewModel.media
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    private func togglePlayback() {
        if playbackManager.isPlaying(media: viewModel.media) {
            playbackManager.pause()
        } else {
            playbackManager.play(media: viewModel.media)
        }
    }

    private func handleEditSave(_ draft: ProfileMediaDraft) async -> Bool {
        let tempViewModel = ProfileMediaLibraryViewModel(
            firestoreService: firestoreService,
            storageService: storageService,
            currentUserProvider: currentUserProvider,
            uploadManager: uploadManager
        )

        let success = await tempViewModel.save(draft: draft) { item in
            viewModel.refresh(with: item)
            libraryViewModel?.refreshItem(item)
            playbackManager.updateMetadata(with: item)
        }

        return success
    }

    private func handleDelete(_ media: ProfileMediaItem) async {
        let tempViewModel = ProfileMediaLibraryViewModel(
            firestoreService: firestoreService,
            storageService: storageService,
            currentUserProvider: currentUserProvider,
            uploadManager: uploadManager
        )
        await tempViewModel.delete(media)
        libraryViewModel?.removeItem(withId: media.id)
        if playbackManager.currentItem?.id == media.id {
            playbackManager.stop()
        }
        dismiss()
    }

    private func refreshFromRemote() async {
        let ownerId = viewModel.media.ownerId
        do {
            let items = try await firestoreService.fetchProfileMedia(for: ownerId)
            if let updated = items.first(where: { $0.id == viewModel.media.id }) {
                viewModel.refresh(with: updated)
                libraryViewModel?.refreshItem(updated)
                playbackManager.updateMetadata(with: updated)
            }
        } catch {
            Logger.log("Failed to refresh media detail: \(error.localizedDescription)")
        }
    }

    private var ownerCapabilities: ProfileMediaCapabilities {
        appState.currentUser?.mediaCapabilities ?? ProfileMediaCapabilities.forAccountType(.artist)
    }
}

private struct StarRatingView: View {
    let rating: Int
    var interactive: Bool = false
    var onRatingChanged: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(value <= rating ? Theme.primaryColor : Color.gray.opacity(0.4))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interactive else { return }
                        onRatingChanged?(value)
                    }
            }
        }
    }
}
