import SwiftUI

struct LocalArtistRadioView: View {
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.di) private var di
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel: LocalArtistRadioViewModel
    @State private var isScrubbing = false
    @State private var scrubbingProgress: Double = 0
    @State private var artistRoute: ArtistRoute?
    @State private var isShowingLikeError = false
    @State private var isShowingGenreDialog = false
    @State private var isShowingRegionDialog = false
    @State private var reportTrack: LocalArtistRadioViewModel.RadioTrack?
    @State private var reportToastMessage: String?
    @State private var reportToastTask: Task<Void, Never>?
    @State private var listMode: RadioListMode = .queue

    let onClose: () -> Void

    init(viewModel: LocalArtistRadioViewModel, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        filterControls
                        mainContent
                        queueSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await viewModel.refreshLineup()
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.likeErrorMessage) { _, newValue in
            isShowingLikeError = newValue != nil
        }
        .alert("Unable to Save", isPresented: $isShowingLikeError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(viewModel.likeErrorMessage ?? "Please try again.")
        })
        .sheet(item: $artistRoute) { route in
            NavigationStack {
                ArtistDetailView(artistId: route.id)
            }
            .environment(\.di, di)
            .environmentObject(appState)
        }
        .sheet(item: $reportTrack) { track in
            ReportMediaView(
                viewModel: ReportMediaViewModel(
                    media: track.media,
                    reportService: di.reportService,
                    storageService: di.storageService,
                    currentUserProvider: { appState.currentUser }
                ),
                onSubmitted: {
                    showReportToast("Thanks for letting us know.")
                }
            )
        }
        .toast(message: $reportToastMessage, bottomInset: 120)
        .onDisappear {
            reportToastTask?.cancel()
            reportToastTask = nil
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Artist Radio")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)

                if let artistName = viewModel.nowPlaying?.ownerDisplayName {
                    Text("Now featuring \(artistName)")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Text("Discover emerging talent around you")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                Task { await viewModel.refreshLineup() }
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.7 : 0.55),
                    Color.black.opacity(colorScheme == .dark ? 0.45 : 0.3),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blur(radius: 16)
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if let error = viewModel.errorMessage {
            glassCard {
                errorState(message: error)
            }
        } else if let current = viewModel.nowPlaying {
            nowPlayingSection(for: current)
        } else if viewModel.isLoading {
            glassCard {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Theme.primaryColor)
                    Text("Tuning Local Frequencies…")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.vertical, 16)
            }
        } else {
            glassCard {
                placeholderCard
            }
        }
    }

    private var filterControls: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Text("Dial in your station by genre and region.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.65))

                HStack(spacing: 12) {
                    genreButton
                    regionButton
                }
            }
        }
    }

    private var genreButton: some View {
        Button {
            isShowingGenreDialog = true
        } label: {
            filterLabel(title: "Genre", value: viewModel.filter.genre?.displayName ?? "All")
        }
        .buttonStyle(.plain)
        .confirmationDialog("Choose Genre", isPresented: $isShowingGenreDialog, titleVisibility: .visible) {
            Button {
                viewModel.updateGenre(nil)
            } label: {
                selectionLabel("All Genres", isSelected: viewModel.filter.genre == nil)
            }

            ForEach(MusicGenre.allCases, id: \.rawValue) { genre in
                Button {
                    viewModel.updateGenre(genre)
                } label: {
                    selectionLabel(genre.displayName, isSelected: viewModel.filter.genre == genre)
                }
            }
        }
    }

    private var regionButton: some View {
        let sortedStates = USState.allCases.sorted { $0.displayName < $1.displayName }

        return Button {
            isShowingRegionDialog = true
        } label: {
            filterLabel(title: "Region", value: viewModel.filter.region.displayName)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Choose Region", isPresented: $isShowingRegionDialog, titleVisibility: .visible) {
            Button {
                viewModel.updateRegion(.nationwide)
            } label: {
                selectionLabel("Nationwide", isSelected: viewModel.filter.region == .nationwide)
            }

            ForEach(sortedStates, id: \.rawValue) { state in
                Button {
                    viewModel.updateRegion(.state(state))
                } label: {
                    selectionLabel(state.displayName, isSelected: viewModel.filter.region.state == state)
                }
            }
        }
    }

    private func filterLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
        }
        .contentShape(Rectangle())
    }

    private func selectionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private func nowPlayingSection(for track: LocalArtistRadioViewModel.RadioTrack) -> some View {
        glassCard {
            VStack(spacing: 22) {
                featuredArtwork(for: track)

                VStack(spacing: 6) {
                    Text(track.displayTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white)
                        .lineLimit(3)

                    Button {
                        artistRoute = ArtistRoute(id: track.media.ownerId)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text(track.ownerDisplayName)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    if let meta = metadataSummary(for: track) {
                        Text(meta)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.top, 4)
                    }
                }

                playbackTimeline
                transportControls
                engagementButtons(for: track)
            }
        }
    }

    private func featuredArtwork(for track: LocalArtistRadioViewModel.RadioTrack) -> some View {
        let dimension = min(UIScreen.main.bounds.width - 120, 280)
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let artworkURL = track.media.coverArtURL ?? track.media.thumbnailURL

        return ZStack {
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        fallbackArtwork
                    case .failure:
                        fallbackArtwork
                    @unknown default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(shape)
        .overlay(
            shape.stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, y: 12)
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.primaryGradientStart.opacity(0.7),
                        Theme.primaryGradientEnd.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
            )
    }

    private var playbackTimeline: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubbingProgress : playbackManager.progress },
                    set: { newValue in
                        isScrubbing = true
                        scrubbingProgress = newValue
                    }
                ),
                in: 0...1
            ) { editing in
                if !editing {
                    let target = scrubbingProgress
                    isScrubbing = false
                    playbackManager.seek(to: target)
                }
            }
            .tint(Theme.primaryColor)

            HStack {
                Text(formatTime(playbackManager.currentTime))
                Spacer()
                Text(formatTime(playbackManager.duration))
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private var transportControls: some View {
        HStack(spacing: 22) {
            transportUtilityButton(systemName: "shuffle", isActive: viewModel.isShuffleEnabled) {
                viewModel.toggleShuffle()
            }

            transportButton("backward.fill") {
                viewModel.playPrevious()
            }

            Button {
                playbackManager.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)

                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, y: 4)
                }
            }
            .buttonStyle(.plain)

            transportButton("forward.fill") {
                viewModel.playNext()
            }

            transportUtilityButton(systemName: "repeat", isActive: viewModel.isRepeatEnabled) {
                viewModel.toggleRepeat()
            }
        }
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func transportUtilityButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(activeFillStyle(isActive: isActive))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isActive ? Theme.primaryGradientEnd.opacity(0.55) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isActive ? Theme.primaryGradientEnd.opacity(0.45) : Color.black.opacity(0.2),
                    radius: isActive ? 9 : 4,
                    y: isActive ? 5 : 2
                )
        }
        .buttonStyle(.plain)
    }

    private func activeFillStyle(isActive: Bool) -> AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }

    private func engagementButtons(for track: LocalArtistRadioViewModel.RadioTrack) -> some View {
        HStack(spacing: 12) {
            capsuleButton(
                icon: viewModel.isLiked(track) ? "heart.fill" : "heart",
                title: viewModel.isLiked(track) ? "Added to Likes" : "Like Track",
                style: viewModel.isLiked(track) ? .primary : .secondary
            ) {
                Task { await viewModel.toggleLike(for: track) }
            }
            .disabled(viewModel.isProcessingLike)
            .opacity(viewModel.isProcessingLike ? 0.6 : 1)

            capsuleButton(
                icon: "rectangle.stack.person.crop",
                title: "View Artist",
                style: .outline
            ) {
                artistRoute = ArtistRoute(id: track.media.ownerId)
            }
        }
    }

    private enum CapsuleStyle {
        case primary
        case secondary
        case outline
        case destructive
    }

    private func capsuleButton(icon: String, title: String, style: CapsuleStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(capsuleForeground(for: style))
            .background(
                Capsule()
                    .fill(capsuleBackground(for: style))
            )
            .overlay(
                Capsule()
                    .stroke(
                        capsuleBorder(for: style),
                        lineWidth: style == .outline ? 1.2 : (style == .destructive ? 0.8 : 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .shadow(color: capsuleShadow(for: style), radius: style == .primary ? 12 : 4, y: style == .primary ? 6 : 2)
    }

    private func capsuleBackground(for style: CapsuleStyle) -> AnyShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .outline:
            return AnyShapeStyle(Color.white.opacity(0.04))
        case .destructive:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.red.opacity(0.85), Color.red.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private func capsuleForeground(for style: CapsuleStyle) -> Color {
        switch style {
        case .primary:
            return Color.white
        case .secondary:
            return Color.white.opacity(0.9)
        case .outline:
            return Color.white.opacity(0.85)
        case .destructive:
            return Color.white
        }
    }

    private func capsuleBorder(for style: CapsuleStyle) -> Color {
        switch style {
        case .primary:
            return Color.white.opacity(0.3)
        case .secondary:
            return Color.white.opacity(0.2)
        case .outline:
            return Color.white.opacity(0.4)
        case .destructive:
            return Color.red.opacity(0.5)
        }
    }

    private func capsuleShadow(for style: CapsuleStyle) -> Color {
        switch style {
        case .primary:
            return Theme.primaryGradientEnd.opacity(0.45)
        case .secondary:
            return Color.black.opacity(0.25)
        case .outline:
            return Color.black.opacity(0.2)
        case .destructive:
            return Color.red.opacity(0.35)
        }
    }

    private func reportButtonTitle(for track: LocalArtistRadioViewModel.RadioTrack) -> String {
        track.media.format == .audio ? "Report Song" : "Report Upload"
    }

    @MainActor
    private func showReportToast(_ message: String) {
        reportToastTask?.cancel()
        withAnimation { reportToastMessage = message }
        reportToastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { reportToastMessage = nil }
            }
        }
    }

private var queueSection: some View {
    VStack(spacing: 18) {
        glassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listMode.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.white)
                        Text(listMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    Spacer()
                    if viewModel.isLoading && viewModel.nowPlaying != nil {
                        ProgressView()
                            .tint(Color.white)
                    }
                }

                queueModePicker

                queueContent(for: listMode)
            }
        }

        if let track = viewModel.nowPlaying, appState.currentUser?.id != track.media.ownerId {
            Button {
                    reportTrack = track
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text(reportButtonTitle(for: track))
                            .font(.headline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.32 : 0.24))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.red.opacity(colorScheme == .dark ? 0.45 : 0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var queueModePicker: some View {
        HStack(spacing: 10) {
            queueModeButton(.queue, icon: "list.bullet", title: "Up Next")
            queueModeButton(.likes, icon: "heart.fill", title: "Liked")
        }
    }

    private func queueModeButton(_ mode: RadioListMode, icon: String, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                listMode = mode
            }
        }
        label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(mode == listMode ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(mode == listMode ? 0.35 : 0.12), lineWidth: 1)
            )
            .foregroundStyle(Color.white.opacity(mode == listMode ? 0.95 : 0.7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func queueContent(for mode: RadioListMode) -> some View {
        switch mode {
        case .queue:
            if let error = viewModel.errorMessage {
                errorState(message: error)
            } else if viewModel.lineup.isEmpty {
                emptyQueueState
            } else {
                LazyVStack(spacing: 14, pinnedViews: []) {
                    ForEach(Array(viewModel.lineup.enumerated()), id: \.offset) { index, track in
                        RadioTrackRow(
                            track: track,
                            isActive: viewModel.currentQueueIndex == index,
                            isLiked: viewModel.isLiked(track),
                            onPlay: {
                                viewModel.play(track: track)
                            },
                            onToggleLike: {
                                Task { await viewModel.toggleLike(for: track) }
                            }
                        )
                    }
                }
            }
        case .likes:
            let likedTracks = viewModel.likedTracks
            if likedTracks.isEmpty {
                likedEmptyState
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(likedTracks, id: \.id) { track in
                        RadioTrackRow(
                            track: track,
                            isActive: viewModel.nowPlaying?.id == track.id,
                            isLiked: true,
                            onPlay: {
                                viewModel.play(track: track)
                            },
                            onToggleLike: {
                                Task { await viewModel.toggleLike(for: track) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28),
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 25, y: 16)
            )
    }

    private var emptyQueueState: some View {
        VStack(spacing: 18) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text("Nothing queued yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white)

            Text("When nearby artists enable radio on their uploads, their tracks will appear here—pull down to check again.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.74))
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var likedEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))

            Text("No liked tracks yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white)

            Text("Tap the heart button while listening to save tracks you love.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("We couldn’t load Local Artist Radio.")
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.list")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("Discover local talent")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white)
            Text("As soon as artists enable radio on their uploads, you can stream their tracks right here.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var backgroundLayer: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let overlayOpacity = colorScheme == .dark ? 0.68 : 0.54

            ZStack {
                LinearGradient(
                    colors: [
                        Theme.primaryGradientStart.opacity(0.45),
                        Theme.primaryGradientEnd.opacity(0.35),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)

                if let url = viewModel.nowPlaying?.media.coverArtURL ?? viewModel.nowPlaying?.media.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        default:
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .blur(radius: 55)
            .overlay(Color.black.opacity(overlayOpacity))
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.1),
                        Color.black.opacity(colorScheme == .dark ? 0.85 : 0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
    }

    private struct ArtistRoute: Identifiable {
        let id: String
    }
}

private struct RadioTrackRow: View {
    let track: LocalArtistRadioViewModel.RadioTrack
    let isActive: Bool
    let isLiked: Bool
    let onPlay: () -> Void
    let onToggleLike: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            artwork

            VStack(alignment: .leading, spacing: 6) {
                Text(track.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(track.ownerDisplayName)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)

                    if isActive {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                        Text("Now Playing")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }

                if let meta = metadataSummary(for: track) {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onToggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isLiked ? Theme.primaryGradientEnd : Color.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            Button(action: onPlay) {
                Image(systemName: isActive ? "waveform" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(playButtonFill)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isActive ? 0.4 : 0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? (isActive ? 0.22 : 0.14) : (isActive ? 0.26 : 0.16)),
                            Color.white.opacity(colorScheme == .dark ? (isActive ? 0.12 : 0.08) : (isActive ? 0.18 : 0.12))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isActive ? 0.35 : 0.18), lineWidth: 1)
                )
        )
    }

    private var artwork: some View {
        let artworkURL = track.media.coverArtURL ?? track.media.thumbnailURL

        return Group {
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholder
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.1))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            )
    }

    private var playButtonFill: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color.white.opacity(0.14))
        }
    }
}

private enum RadioListMode: CaseIterable {
    case queue
    case likes

    var title: String {
        switch self {
        case .queue:
            return "Up Next"
        case .likes:
            return "Liked Tracks"
        }
    }

    var subtitle: String {
        switch self {
        case .queue:
            return "Swipe down to refresh and hear what's playing locally."
        case .likes:
            return "Songs you've saved from Local Artist Radio."
        }
    }
}

private func metadataSummary(for track: LocalArtistRadioViewModel.RadioTrack) -> String? {
    var components: [String] = []
    if let genre = track.genreDisplayName {
        components.append(genre)
    }
    if let origin = track.originStateDisplayName {
        components.append(origin)
    }
    return components.isEmpty ? nil : components.joined(separator: " • ")
}

struct LocalArtistRadioView_Previews: PreviewProvider {
    static var previews: some View {
        let playback = MediaPlaybackManager()
        let service = MockFirestoreService()
        let sampleTrack = ProfileMediaItem.mock(format: .audio)
        playback.prepare(media: sampleTrack)

        let viewModel = LocalArtistRadioViewModel(
            firestoreService: service,
            playbackManager: playback,
            currentUserProvider: { UserProfile.mock }
        )

        return LocalArtistRadioView(viewModel: viewModel, onClose: {})
            .environmentObject(playback)
            .environmentObject(AppState())
            .environment(\.di, DIContainer.makeMock())
    }
}
