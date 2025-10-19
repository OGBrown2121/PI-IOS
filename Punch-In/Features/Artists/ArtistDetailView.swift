import SwiftUI
import UIKit

struct ArtistDetailView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    let artistId: String
    private let heroStyle: HeroStyle

    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reviews: [Review] = []
    @State private var isLoadingReviews = false
    @State private var reviewsErrorMessage: String?
    @State private var followStats: FollowStats = .empty
    @State private var isLoadingFollowStats = true
    @State private var isUpdatingFollow = false
    @State private var followErrorMessage: String?
    @State private var mediaItems: [ProfileMediaItem] = []
    @State private var isLoadingMediaLibrary = false
    @State private var mediaErrorMessage: String?
    @State private var beatCatalog: [ProducerBeat] = []
    @State private var isLoadingBeatCatalog = false
    @State private var beatCatalogErrorMessage: String?
    @State private var pendingBeatDownloadIds: Set<String> = []
    @State private var beatDownloadErrorMessage: String?
    @State private var beatDownloadSuccessMessage: String?
    @State private var beatDownloadRequests: [BeatDownloadRequest] = []
    @State private var beatDownloadRequesterProfiles: [String: UserProfile] = [:]
    @State private var isLoadingBeatDownloadRequests = false
    @State private var beatDownloadRequestsErrorMessage: String?
    @State private var hasLoadedBeatDownloadRequests = false
    @State private var processingBeatDownloadRequestIds: Set<String> = []
    @State private var beatDownloadManagementMessage: String?
    @State private var beatDownloadManagementErrorMessage: String?
    @State private var beatDownloadManagementMessageTask: Task<Void, Never>?
    @State private var presentedFollowList: FollowConnectionsKind?
    @State private var isShowingReportSheet = false
    @State private var contactContext: ContactActionContext?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    init(artistId: String, profile: UserProfile? = nil, heroStyle: HeroStyle = .standard) {
        self.artistId = artistId
        self.heroStyle = heroStyle
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                        heroSection(for: profile)
                        if let action = profile.accountType.contactAction, shouldShowBookingAction(for: profile) {
                            bookingSection(for: profile, action: action)
                        }
                        if profile.accountType == .producer {
                            beatCatalogSection(for: profile)
                        }
                        if profile.accountType.supportsProfileMediaLibrary {
                            mediaSection(for: profile)
                        }
                        if profile.accountType.isPrivateProfile {
                            privateProfileNotice(for: profile)
                        } else {
                            if activeProjects(for: profile).isEmpty == false {
                                ProfileSpotlightSection(
                                    title: "Pinned Projects",
                                    icon: "hammer",
                                    spotlights: activeProjects(for: profile),
                                    accentColor: Theme.primaryColor
                                )
                            }
                            if activeEvents(for: profile).isEmpty == false {
                                ProfileSpotlightSection(
                                    title: "Upcoming Events",
                                    icon: "calendar",
                                    spotlights: activeEvents(for: profile),
                                    accentColor: Color.purple
                                )
                            }
                            creativeSection(for: profile)
                            detailsSection(for: profile)
                            reviewsSection
                            collaborationSection(for: profile)
                        }
                    }
                    .padding(Theme.spacingLarge)
                }
                .background(Theme.appBackground)
                .navigationTitle(profile.displayName.isEmpty ? profile.username : profile.displayName)
                .navigationBarTitleDisplayMode(.inline)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "We couldn’t load this artist",
                    systemImage: "music.mic",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadProfileIfNeeded()
            await refreshFollowStatsIfNeeded()
            await loadReviews()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let profile,
                   let currentUser = appState.currentUser,
                   currentUser.id != profile.id {
                    Menu {
                        Button(role: .destructive) {
                            isShowingReportSheet = true
                        } label: {
                            let name = profile.displayName.isEmpty ? profile.username : profile.displayName
                            Label("Report \(name)", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .sheet(item: $presentedFollowList) { kind in
            NavigationStack {
                if let profile = self.profile {
                    FollowConnectionsView(
                        userId: profile.id,
                        kind: kind,
                        firestoreService: di.firestoreService
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(\.di, di)
            .environmentObject(appState)
        }
        .sheet(isPresented: $isShowingReportSheet) {
            if let profile {
                ReportUserView(
                    viewModel: ReportUserViewModel(
                        reportedUser: profile,
                        reportService: di.reportService,
                        storageService: di.storageService,
                        currentUserProvider: { appState.currentUser }
                    ),
                    onSubmitted: {
                        showToast("Thanks for letting us know.")
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $contactContext) { context in
            ProfileContactSheet(
                context: context,
                openURLAction: openURL,
                onCopy: { copiedValue in
                    showToast("\(copiedValue) copied to clipboard")
                },
                onUnavailable: {
                    showToast("No direct contact info has been shared yet.")
                }
            )
        }
        .toast(message: $toastMessage, bottomInset: 120)
        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
            beatDownloadManagementMessageTask?.cancel()
            beatDownloadManagementMessageTask = nil
        }
    }

    struct ArtistHeroMetrics {
        let avatarSize: CGFloat
        let cardCornerRadius: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat

        static let standard = ArtistHeroMetrics(
            avatarSize: 76,
            cardCornerRadius: 22,
            horizontalPadding: Theme.spacingMedium,
            verticalPadding: Theme.spacingMedium * 0.55,
            shadowRadius: 4,
            shadowYOffset: 3
        )

        static let compact = ArtistHeroMetrics(
            avatarSize: 64,
            cardCornerRadius: 20,
            horizontalPadding: Theme.spacingSmall * 1.25,
            verticalPadding: Theme.spacingSmall * 0.85,
            shadowRadius: 3,
            shadowYOffset: 2
        )
    }

    enum HeroStyle {
        case standard
        case compact

        var metrics: ArtistHeroMetrics {
            switch self {
            case .standard:
                return .standard
            case .compact:
                return .compact
            }
        }
    }

    private func heroSection(for profile: UserProfile) -> some View {
        let metrics = heroStyle.metrics

        return VStack(spacing: Theme.spacingSmall * 0.6) {
            avatar(for: profile)
                .overlay(alignment: .bottomTrailing) {
                    heroBadge(for: profile.accountType)
                }
                .padding(.bottom, Theme.spacingSmall * 0.6)

            Text(profile.accountType.title.uppercased())
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("@\(profile.username)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            if !profile.profileDetails.bio.isEmpty {
                Text(profile.profileDetails.bio)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spacingSmall * 0.5)
            }

            followSummarySection(for: profile)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(
            color: Theme.primaryColor.opacity(0.18),
            radius: metrics.shadowRadius,
            x: 0,
            y: metrics.shadowYOffset
        )
    }

    private func mediaSection(for profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            if isLoadingMediaLibrary {
                ProgressView("Loading featured media…")
                    .progressViewStyle(.circular)
            } else if let message = mediaErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if mediaItems.isEmpty {
                Text("Add uploads from your settings to showcase music, mixes, or visuals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let pinned = mediaItems.filter { $0.isPinned }

                if pinned.isEmpty == false {
                    ProfileMediaShowcaseSection(
                        title: profile.mediaCapabilities.pinnedSectionTitle,
                        icon: "star.fill",
                        accentColor: mediaAccentColor(for: profile.accountType),
                        items: pinned
                    )
                } else {
                    Text("Pin uploads from your settings to highlight them here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadMediaIfNeeded(for: profile)
        }
    }

    private func bookingSection(for profile: UserProfile, action: AccountType.ContactAction) -> some View {
        sectionCard(title: action.cardTitle, icon: action.cardIcon) {
            VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                Text(action.sheetMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                PrimaryButton(title: action.buttonTitle) {
                    contactContext = ContactActionContext(action: action, profile: profile)
                }
            }
        }
    }

    private func shouldShowBookingAction(for profile: UserProfile) -> Bool {
        guard let currentUser = appState.currentUser else { return true }
        return currentUser.id != profile.id
    }

    private func mediaAccentColor(for accountType: AccountType) -> Color {
        switch accountType {
        case .dj:
            return Color.purple
        case .photographer:
            return Color.orange
        case .videographer:
            return Color.blue
        case .podcast:
            return Color.mint
        case .designer:
            return Color.pink
        case .videoVixen:
            return Color.red.opacity(0.85)
        case .journalist:
            return Color.teal
        case .eventCenter:
            return Color.indigo
        default:
            return Theme.primaryColor
        }
    }

    private func beatCatalogSection(for profile: UserProfile) -> some View {
        sectionCard(title: "Beat Catalog", icon: "music.note.list") {
            VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                if isLoadingBeatCatalog {
                    ProgressView("Loading catalog…")
                        .progressViewStyle(.circular)
                } else if let message = beatCatalogErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if beatCatalog.isEmpty {
                    Text("No beats listed yet. Producers can add beats from their catalog manager.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Browse \(beatCatalog.count) beat\(beatCatalog.count == 1 ? "" : "s") from this producer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let successMessage = beatDownloadSuccessMessage, successMessage.isEmpty == false {
                        Text(successMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.primaryColor)
                    }
                    if let downloadMessage = beatDownloadErrorMessage, downloadMessage.isEmpty == false {
                        Text(downloadMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }

                NavigationLink {
                    ArtistBeatCatalogView(
                        profile: profile,
                        beats: $beatCatalog,
                        isLoading: $isLoadingBeatCatalog,
                        errorMessage: $beatCatalogErrorMessage,
                        pendingDownloadIds: $pendingBeatDownloadIds,
                        downloadErrorMessage: $beatDownloadErrorMessage,
                        reloadAction: {
                            await loadBeatCatalog(for: profile)
                        },
                        onRequestDownload: { beat in
                            return await handleBeatDownload(beat: beat, producerId: profile.id)
                        }
                    )
                } label: {
                    HStack(alignment: .center, spacing: Theme.spacingMedium) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Beat Catalog")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Open the full beat catalog with previews and download requests.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, Theme.spacingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.primaryColor.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open beat catalog for \(profile.displayName.isEmpty ? profile.username : profile.displayName)")

                if shouldShowBeatDownloadRequests(for: profile) {
                    beatDownloadRequestsSection(for: profile)
                }
            }
        }
        .task {
            await loadBeatCatalogIfNeeded(for: profile)
            await loadBeatDownloadRequestsIfNeeded(for: profile)
        }
    }

    @ViewBuilder
    private func beatDownloadRequestsSection(for profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            HStack(spacing: Theme.spacingSmall) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primaryColor)
                Text("Pending Download Requests")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isLoadingBeatDownloadRequests {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await loadBeatDownloadRequests(for: profile) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh download requests")
                    .disabled(isLoadingBeatDownloadRequests)
                }
            }

            if isLoadingBeatDownloadRequests && beatDownloadRequests.isEmpty {
                ProgressView("Checking requests…")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let message = beatDownloadRequestsErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                let pendingRequests = beatDownloadRequests.filter { $0.status == .pending }
                if pendingRequests.isEmpty {
                    Text("No pending download requests yet. We'll surface them here when artists ask to access your stems or previews.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.spacingSmall) {
                        ForEach(pendingRequests) { request in
                            beatDownloadRequestRow(for: request, profile: profile)
                        }
                    }
                }
            }

            if let managementMessage = beatDownloadManagementMessage {
                Text(managementMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.primaryColor)
                    .transition(.opacity)
            }

            if let managementError = beatDownloadManagementErrorMessage {
                Text(managementError)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .padding(.top, Theme.spacingSmall)
    }

    private func beatDownloadRequestRow(for request: BeatDownloadRequest, profile: UserProfile) -> some View {
        let isProcessing = processingBeatDownloadRequestIds.contains(request.id)
        let isReadyToShare = downloadReady(for: request)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(requesterDisplayName(for: request))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(request.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("requested \"\(beatTitle(for: request))\"")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.spacingSmall) {
                Button {
                    Task {
                        await handleBeatDownloadDecision(for: request, decision: .approve, profile: profile)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Share Files")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.primaryColor)
                )
                .foregroundStyle(.white)
                .disabled(isProcessing || isReadyToShare == false)
                .opacity((isProcessing || isReadyToShare == false) ? 0.55 : 1)

                Button(role: .destructive) {
                    Task {
                        await handleBeatDownloadDecision(for: request, decision: .reject, profile: profile)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Decline")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
                .foregroundStyle(Color.red.opacity(0.9))
                .disabled(isProcessing)
            }
            .padding(.top, Theme.spacingSmall * 0.85)

            if isReadyToShare == false {
                Text("Upload a preview or stems archive before sharing files.")
                    .font(.caption2)
                    .foregroundStyle(Color.red.opacity(0.75))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }

    private func requesterDisplayName(for request: BeatDownloadRequest) -> String {
        guard let profile = beatDownloadRequesterProfiles[request.requesterId] else {
            return "New artist"
        }

        let trimmedDisplay = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplay.isEmpty == false {
            return trimmedDisplay
        }

        let trimmedUsername = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else { return "New artist" }
        return "@\(trimmedUsername)"
    }

    private func beatTitle(for request: BeatDownloadRequest) -> String {
        if let storedTitle = request.beatTitle?.trimmingCharacters(in: .whitespacesAndNewlines), storedTitle.isEmpty == false {
            return storedTitle
        }
        if let beat = beatCatalog.first(where: { $0.id == request.beatId }) {
            let trimmed = beat.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return "Untitled Beat"
    }

    private func downloadReady(for request: BeatDownloadRequest) -> Bool {
        guard let beat = beatCatalog.first(where: { $0.id == request.beatId }) else { return false }
        return beat.stemsZipURL != nil || beat.previewURL != nil
    }

    private func followSummarySection(for profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall * CGFloat(0.9)) {
            if isLoadingFollowStats {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                HStack(spacing: Theme.spacingMedium) {
                    followMetricButton(
                        count: followStats.followersCount,
                        label: followersLabel,
                        kind: .followers
                    )
                    followMetricButton(
                        count: followStats.followingCount,
                        label: "Following",
                        kind: .following
                    )
                }
            }

            if shouldShowFollowButton(for: profile) {
                Button {
                    Task { await handleFollowTap(for: profile) }
                } label: {
                    ZStack {
                        HStack(spacing: 8) {
                            Image(systemName: followStats.isFollowing ? "checkmark" : "person.badge.plus")
                                .font(.subheadline.weight(.semibold))
                            Text(followStats.isFollowing ? "Following" : "Follow")
                                .font(.subheadline.weight(.semibold))
                        }
                        .opacity(isUpdatingFollow ? 0 : 1)

                        if isUpdatingFollow {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(followStats.isFollowing ? .white : Theme.primaryColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(followStats.isFollowing ? Color.white.opacity(0.2) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(followStats.isFollowing ? 0.4 : 0), lineWidth: 1)
                )
                .foregroundStyle(followStats.isFollowing ? Color.white : Theme.primaryColor)
                .disabled(isUpdatingFollow || isLoadingFollowStats)
                .padding(.top, Theme.spacingSmall)
            }

            if let message = followErrorMessage, message.isEmpty == false {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func followMetricView(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private func followMetricButton(count: Int, label: String, kind: FollowConnectionsKind) -> some View {
        Button {
            presentedFollowList = kind
        } label: {
            followMetricView(count: count, label: label)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingFollowStats)
    }

    private var followersLabel: String {
        followStats.followersCount == 1 ? "Follower" : "Followers"
    }

    private func shouldShowFollowButton(for profile: UserProfile) -> Bool {
        guard let currentUser = appState.currentUser else { return false }
        return currentUser.id != profile.id
    }

    private func creativeSection(for profile: UserProfile) -> some View {
        let labels = profile.accountType.requiredFieldLabels
        return sectionCard(title: "Creative Focus", icon: "sparkles") {
            VStack(spacing: Theme.spacingMedium) {
                if labels.indices.contains(0) && !profile.profileDetails.fieldOne.isEmpty {
                    CreativeInfoPill(icon: "music.note.list", title: labels[0], value: profile.profileDetails.fieldOne)
                }

                if labels.indices.contains(1) && !profile.profileDetails.fieldTwo.isEmpty {
                    CreativeInfoPill(icon: "lightbulb", title: labels[1], value: profile.profileDetails.fieldTwo)
                }
            }
        }
    }

    private func detailsSection(for profile: UserProfile) -> some View {
        sectionCard(title: "About \(profile.displayName.isEmpty ? profile.username : profile.displayName)", icon: "person.fill") {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                profileDetailRow(label: "Joined", value: formatted(date: profile.createdAt))
                Divider()
                    .padding(.vertical, 4)
                profileDetailRow(label: "Account Type", value: profile.accountType.title)
            }
        }
    }

    private func privateProfileNotice(for profile: UserProfile) -> some View {
        sectionCard(title: "Private scouting", icon: "lock.fill") {
            Text("This \(profile.accountType.title) keeps most details private. Follow to stay on their radar or use the contact button above to introduce your project.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Label("Reviews", systemImage: "star.circle.fill")
                .font(.headline)

            if isLoadingReviews {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let message = reviewsErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if reviews.isEmpty {
                Text("No feedback from collaborators yet. Sessions you’ve completed will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                reviewRatingSummary
                Divider()
                let featuredReviews = artistTopReviews
                ForEach(Array(featuredReviews.enumerated()), id: \.element.id) { entry in
                    let review = entry.element
                    let index = entry.offset
                    reviewRow(for: review)
                    if index < featuredReviews.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func collaborationSection(for profile: UserProfile) -> some View {
        sectionCard(title: "Collaboration", icon: "hand.wave.fill") {
            let name = profile.displayName.isEmpty ? profile.username : profile.displayName
            Text("Want to collaborate with \(name)? Send a message or invite them to a session once booking opens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var reviewRatingSummary: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.yellow)
                Text(artistAverageRatingText)
                    .font(.title3.weight(.semibold))
            }

            Text("\(reviews.count) review\(reviews.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var artistAverageRatingText: String {
        guard let rating = artistAverageRating else { return "–" }
        return String(format: "%.1f", rating)
    }

    private var artistAverageRating: Double? {
        guard reviews.isEmpty == false else { return nil }
        let total = reviews.reduce(0.0) { $0 + Double($1.rating) }
        return total / Double(reviews.count)
    }

    private var artistTopReviews: [Review] {
        Array(artistSortedReviews.prefix(3))
    }

    private var artistSortedReviews: [Review] {
        reviews.sorted { $0.createdAt > $1.createdAt }
    }

    private func reviewRow(for review: Review) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                starRow(for: review.rating)
                Text(review.reviewerAccountType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedReviewDate(review.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if review.comment.trimmed.isEmpty == false {
                Text(review.comment)
                    .font(.footnote)
            } else {
                Text("No written feedback provided.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func starRow(for rating: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
            }
        }
    }

    private func formattedReviewDate(_ date: Date) -> String {
        Self.reviewDateFormatter.string(from: date)
    }

    private static let reviewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private func avatar(for profile: UserProfile) -> some View {
        let metrics = heroStyle.metrics

        return Group {
            if let imageURL = profile.profileImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderAvatar(for: profile)
                    @unknown default:
                        placeholderAvatar(for: profile)
                    }
                }
            } else {
                placeholderAvatar(for: profile)
            }
        }
        .frame(width: metrics.avatarSize, height: metrics.avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 3)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 6)
    }

    private func placeholderAvatar(for profile: UserProfile) -> some View {
        let initials = initials(for: profile)
        return ZStack {
            Circle()
                .fill(heroGradient)
            Text(initials)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func heroBadge(for accountType: AccountType) -> some View {
        if let symbol = accountType.heroBadgeSystemImage {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 26, height: 26)
            .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
        }
    }

    private func loadReviews() async {
        guard isLoadingReviews == false else { return }
        isLoadingReviews = true
        reviewsErrorMessage = nil

        do {
            reviews = try await di.reviewService.fetchReviews(for: artistId, kind: .artist)
        } catch {
            reviewsErrorMessage = error.localizedDescription
        }

        isLoadingReviews = false
    }

    private func initials(for profile: UserProfile) -> String {
        let name = profile.displayName.isEmpty ? profile.username : profile.displayName
        let components = name.split(separator: " ")
        if let first = components.first, let last = components.dropFirst().first {
            return String(first.first!).uppercased() + String(last.first!).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func formatted(date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }

    private var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func activeProjects(for profile: UserProfile) -> [ProfileSpotlight] {
        profile.profileDetails.upcomingProjects.sanitized()
    }

    private func activeEvents(for profile: UserProfile) -> [ProfileSpotlight] {
        profile.profileDetails.upcomingEvents.sanitized()
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.primaryColor)
            content()
        }
        .padding(Theme.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private struct ContactActionContext: Identifiable {
        let id = UUID()
        let action: AccountType.ContactAction
        let profile: UserProfile
    }

    private struct ProfileContactSheet: View {
        @Environment(\.dismiss) private var dismiss
        let context: ContactActionContext
        let openURLAction: OpenURLAction
        let onCopy: (String) -> Void
        let onUnavailable: () -> Void

        var body: some View {
            NavigationStack {
                List {
                    Section("Details") {
                        Text(context.action.sheetMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Section("Contact") {
                        if contactMethods.isEmpty {
                            Text("This profile hasn’t shared direct contact info yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(contactMethods, id: \.self) { method in
                                switch method {
                                case .email(let value):
                                    Button {
                                        openEmail(value)
                                    } label: {
                                        Label("Email", systemImage: "envelope.fill")
                                    }
                                    Button {
                                        copyToClipboard(value, description: "Email address")
                                    } label: {
                                        Label("Copy email", systemImage: "doc.on.doc")
                                    }
                                case .phone(let value):
                                    Button {
                                        callNumber(value)
                                    } label: {
                                        Label("Call", systemImage: "phone.fill")
                                    }
                                    Button {
                                        copyToClipboard(value, description: "Phone number")
                                    } label: {
                                        Label("Copy phone", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(context.action.sheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    if contactMethods.isEmpty {
                        onUnavailable()
                    }
                }
            }
        }

        private enum ContactMethod: Hashable {
            case email(String)
            case phone(String)
        }

        private var contactMethods: [ContactMethod] {
            var methods: [ContactMethod] = []
            let contact = context.profile.contact
            let trimmedEmail = contact.email.trimmed
            if trimmedEmail.isEmpty == false {
                methods.append(.email(trimmedEmail))
            }
            let trimmedPhone = contact.phoneNumber.trimmed
            if trimmedPhone.isEmpty == false {
                methods.append(.phone(trimmedPhone))
            }
            return methods
        }

        private func openEmail(_ address: String) {
            guard let url = URL(string: "mailto:\(address)") else { return }
            openURLAction(url)
            dismiss()
        }

        private func callNumber(_ number: String) {
            let digits = number.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: "tel:\(digits)") else { return }
            openURLAction(url)
            dismiss()
        }

        private func copyToClipboard(_ value: String, description: String) {
            #if canImport(UIKit)
            UIPasteboard.general.string = value
            #endif
            onCopy(description)
        }
    }

    private func profileDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSmall) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refreshFollowStatsIfNeeded() async {
        guard let profile else {
            isLoadingFollowStats = false
            return
        }
        isLoadingFollowStats = true
        followErrorMessage = nil
        do {
            let stats = try await di.firestoreService.loadFollowStats(
                for: profile.id,
                viewerId: appState.currentUser?.id
            )
            followStats = stats
        } catch {
            followStats = .empty
            followErrorMessage = error.localizedDescription
        }
        isLoadingFollowStats = false
    }

    @MainActor
    private func handleFollowTap(for profile: UserProfile) async {
        guard !isUpdatingFollow else { return }
        guard let currentUser = appState.currentUser else { return }
        guard currentUser.id != profile.id else { return }

        isUpdatingFollow = true
        followErrorMessage = nil

        do {
            if followStats.isFollowing {
                try await di.firestoreService.unfollow(userId: currentUser.id, targetUserId: profile.id)
                followStats.isFollowing = false
                followStats.followersCount = max(followStats.followersCount - 1, 0)
            } else {
                try await di.firestoreService.follow(userId: currentUser.id, targetUserId: profile.id)
                followStats.isFollowing = true
                followStats.followersCount += 1
            }
        } catch {
            followErrorMessage = error.localizedDescription
        }

        isUpdatingFollow = false
    }

    private func loadProfileIfNeeded() async {
        guard profile == nil else { return }
        await loadProfile(force: false)
    }

    private func loadProfile(force: Bool) async {
        guard force || profile == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            profile = try await di.firestoreService.loadUserProfile(for: artistId)
            if profile == nil {
                errorMessage = "We couldn't find this artist."
            } else if let loadedProfile = profile, loadedProfile.accountType.supportsProfileMediaLibrary {
                await loadMedia(for: loadedProfile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMediaIfNeeded(for profile: UserProfile) async {
        guard mediaItems.isEmpty else { return }
        await loadMedia(for: profile)
    }

    private func loadMedia(for profile: UserProfile) async {
        guard isLoadingMediaLibrary == false else { return }
        isLoadingMediaLibrary = true
        defer { isLoadingMediaLibrary = false }
        do {
            let items = try await di.firestoreService.fetchProfileMedia(for: profile.id)
            mediaItems = items.filter(\.isShared)
            mediaErrorMessage = nil
        } catch {
            mediaErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadBeatCatalogIfNeeded(for profile: UserProfile) async {
        guard profile.accountType == .producer else { return }
        guard beatCatalog.isEmpty else { return }
        await loadBeatCatalog(for: profile)
    }

    @MainActor
    private func loadBeatCatalog(for profile: UserProfile) async {
        guard profile.accountType == .producer else { return }
        guard isLoadingBeatCatalog == false else { return }
        isLoadingBeatCatalog = true
        defer { isLoadingBeatCatalog = false }
        do {
            let beats = try await di.firestoreService.fetchBeatCatalog(for: profile.id, includeUnpublished: false)
            beatCatalog = beats
            beatCatalogErrorMessage = nil
            if shouldShowBeatDownloadRequests(for: profile) {
                await loadBeatDownloadRequests(for: profile)
            }
        } catch {
            beatCatalogErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shouldShowBeatDownloadRequests(for profile: UserProfile) -> Bool {
        guard profile.accountType == .producer else { return false }
        guard let currentUser = appState.currentUser else { return false }
        return currentUser.id == profile.id
    }

    @MainActor
    private func loadBeatDownloadRequestsIfNeeded(for profile: UserProfile) async {
        guard shouldShowBeatDownloadRequests(for: profile) else { return }
        guard hasLoadedBeatDownloadRequests == false else { return }
        await loadBeatDownloadRequests(for: profile)
    }

    @MainActor
    private func loadBeatDownloadRequests(for profile: UserProfile) async {
        guard shouldShowBeatDownloadRequests(for: profile) else { return }
        guard isLoadingBeatDownloadRequests == false else { return }
        isLoadingBeatDownloadRequests = true
        defer { isLoadingBeatDownloadRequests = false }
        beatDownloadManagementErrorMessage = nil
        do {
            let requests = try await di.firestoreService.fetchBeatDownloadRequests(
                for: profile.id,
                status: .pending
            )
            beatDownloadRequests = requests
            hasLoadedBeatDownloadRequests = true
            beatDownloadRequestsErrorMessage = nil

            let requesterIds = Set(requests.map { $0.requesterId })
            if requesterIds.isEmpty {
                beatDownloadRequesterProfiles = [:]
            } else if let profiles = try? await di.firestoreService.fetchUserProfiles(for: Array(requesterIds)) {
                beatDownloadRequesterProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            } else {
                beatDownloadRequesterProfiles = [:]
            }
        } catch {
            beatDownloadRequestsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if hasLoadedBeatDownloadRequests == false {
                beatDownloadRequests = []
                beatDownloadRequesterProfiles = [:]
            }
        }
    }

    private enum BeatDownloadDecision {
        case approve
        case reject
    }

    @MainActor
    private func handleBeatDownloadDecision(
        for request: BeatDownloadRequest,
        decision: BeatDownloadDecision,
        profile: UserProfile
    ) async {
        guard processingBeatDownloadRequestIds.contains(request.id) == false else { return }
        processingBeatDownloadRequestIds.insert(request.id)
        defer { processingBeatDownloadRequestIds.remove(request.id) }

        beatDownloadManagementErrorMessage = nil
        beatDownloadManagementMessageTask?.cancel()
        beatDownloadManagementMessageTask = nil
        beatDownloadManagementMessage = nil

        guard shouldShowBeatDownloadRequests(for: profile) else { return }

        var downloadURL: URL?

        if decision == .approve {
            guard let beat = beatCatalog.first(where: { $0.id == request.beatId }) else {
                beatDownloadManagementErrorMessage = "We couldn't find that beat anymore."
                return
            }

            guard let shareURL = beat.stemsZipURL ?? beat.previewURL else {
                beatDownloadManagementErrorMessage = "Upload a download-ready file before approving this request."
                return
            }

            downloadURL = shareURL
        }

        do {
            let newStatus: BeatDownloadRequest.Status = decision == .approve ? .fulfilled : .rejected
            try await di.firestoreService.updateBeatDownloadRequest(request, status: newStatus, downloadURL: downloadURL)

            withAnimation {
                beatDownloadRequests.removeAll { $0.id == request.id }
            }

            beatDownloadManagementErrorMessage = nil

            let feedback: String
            if decision == .approve {
                feedback = "Shared files with \(requesterDisplayName(for: request))."
            } else {
                feedback = "Declined download request from \(requesterDisplayName(for: request))."
            }

            withAnimation {
                beatDownloadManagementMessage = feedback
            }
            beatDownloadManagementMessageTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation {
                        beatDownloadManagementMessage = nil
                    }
                }
            }
        } catch {
            beatDownloadManagementErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func handleBeatDownload(beat: ProducerBeat, producerId: String) async -> Bool {
        guard pendingBeatDownloadIds.contains(beat.id) == false else { return false }
        guard let currentUser = appState.currentUser else {
            beatDownloadErrorMessage = "Sign in to request downloads to your drive."
            return false
        }

        pendingBeatDownloadIds.insert(beat.id)
        defer { pendingBeatDownloadIds.remove(beat.id) }
        beatDownloadErrorMessage = nil
        beatDownloadSuccessMessage = nil

        do {
            let request = BeatDownloadRequest(
                beatId: beat.id,
                producerId: producerId,
                requesterId: currentUser.id,
                beatTitle: beat.title
            )
            try await di.firestoreService.submitBeatDownloadRequest(request)
            beatDownloadErrorMessage = nil
            beatDownloadSuccessMessage = "Request sent! We'll notify you once the producer shares the files."
            showToast("We’ll notify you once the producer shares the files.")
            return true
        } catch {
            beatDownloadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @MainActor
    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation { toastMessage = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

private struct CreativeInfoPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMedium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Theme.primaryGradientEnd.opacity(0.3), radius: 6, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.spacingSmall)
        .padding(.horizontal, Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview("Producer Detail") {
    let di = DIContainer.makeMock()
    let profile = UserProfile.previewProducer

    if let firestore = di.firestoreService as? MockFirestoreService {
        firestore.seedUserProfile(profile)
        var primaryBeat = ProducerBeat.mock
        primaryBeat.producerId = profile.id
        var exclusiveBeat = ProducerBeat.exclusiveMock
        exclusiveBeat.producerId = profile.id
        firestore.seedBeatCatalog(for: profile.id, beats: [primaryBeat, exclusiveBeat])
    }

    return NavigationStack {
        ArtistDetailView(artistId: profile.id, profile: profile, heroStyle: .standard)
            .environment(\.di, di)
            .environmentObject(ArtistDetailView.previewAppState)
    }
}

extension ArtistDetailView {
    fileprivate static var previewAppState: AppState {
        let state = AppState()
        state.isAuthenticated = true
        state.currentUser = .mock
        return state
    }
}
