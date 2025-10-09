import SwiftUI

struct ArtistDetailView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState

    let artistId: String

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

    init(artistId: String, profile: UserProfile? = nil) {
        self.artistId = artistId
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                        heroSection(for: profile)
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
                    .padding(Theme.spacingLarge)
                }
                .background(Color(uiColor: .systemBackground))
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
    }

    private enum ArtistHeroMetrics {
        static let avatarSize: CGFloat = 88
        static let cardCornerRadius: CGFloat = 26
        static let horizontalPadding: CGFloat = Theme.spacingLarge
        static let verticalPadding: CGFloat = Theme.spacingMedium * CGFloat(0.85)
        static let shadowRadius: CGFloat = 6
        static let shadowYOffset: CGFloat = 4
    }

    private func heroSection(for profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall * CGFloat(0.8)) {
            avatar(for: profile)
                .padding(.bottom, Theme.spacingSmall)

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
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("@\(profile.username)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            if !profile.profileDetails.bio.isEmpty {
                Text(profile.profileDetails.bio)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spacingSmall * CGFloat(0.75))
            }

            followSummarySection(for: profile)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ArtistHeroMetrics.horizontalPadding)
        .padding(.vertical, ArtistHeroMetrics.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: ArtistHeroMetrics.cardCornerRadius, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ArtistHeroMetrics.cardCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(
            color: Theme.primaryColor.opacity(0.18),
            radius: ArtistHeroMetrics.shadowRadius,
            x: 0,
            y: ArtistHeroMetrics.shadowYOffset
        )
    }

    private func followSummarySection(for profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall * CGFloat(0.9)) {
            if isLoadingFollowStats {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                HStack(spacing: Theme.spacingMedium) {
                    followMetricView(count: followStats.followersCount, label: followersLabel)
                    followMetricView(count: followStats.followingCount, label: "Following")
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
                    .padding(.vertical, 10)
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
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
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
            Text("Want to collaborate with \(profile.displayName.isEmpty ? profile.username : profile.displayName)? Send a message or invite them to a session once booking opens.")
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
        Group {
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
        .frame(width: ArtistHeroMetrics.avatarSize, height: ArtistHeroMetrics.avatarSize)
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
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
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

    @MainActor
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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

#Preview("Artist Detail") {
    NavigationStack {
        ArtistDetailView(artistId: "preview", profile: .mock)
            .environment(\.di, DIContainer.makeMock())
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
