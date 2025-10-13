import SwiftUI

enum FollowConnectionsKind: String, Identifiable {
    case followers
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followers:
            return "Followers"
        case .following:
            return "Following"
        }
    }

    var emptyMessage: String {
        switch self {
        case .followers:
            return "No one is following this profile yet."
        case .following:
            return "This profile isn't following anyone yet."
        }
    }

    var emptySubtitle: String {
        switch self {
        case .followers:
            return "When someone follows this account, they'll appear here."
        case .following:
            return "Accounts that this profile follows will be listed here."
        }
    }

    var analyticsLabel: String {
        switch self {
        case .followers:
            return "followers"
        case .following:
            return "following"
        }
    }
}

struct FollowConnectionsView: View {
    @StateObject private var viewModel: FollowConnectionsViewModel

    private let kind: FollowConnectionsKind

    init(userId: String, kind: FollowConnectionsKind, firestoreService: any FirestoreService) {
        self.kind = kind
        _viewModel = StateObject(
            wrappedValue: FollowConnectionsViewModel(
                userId: userId,
                kind: kind,
                firestoreService: firestoreService
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingMedium) {
                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    loadingState
                        .padding(.top, Theme.spacingLarge)
                } else if let message = viewModel.errorMessage {
                    errorState(message: message)
                        .padding(.top, Theme.spacingLarge)
                } else if viewModel.profiles.isEmpty {
                    emptyState
                        .padding(.top, Theme.spacingLarge)
                } else {
                    ForEach(viewModel.profiles) { profile in
                        NavigationLink {
                            destination(for: profile)
                        } label: {
                            profileRow(for: profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingMedium)
        }
        .scrollIndicators(.hidden)
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitialIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private extension FollowConnectionsView {
    var emptyState: some View {
        VStack(spacing: Theme.spacingSmall) {
            Text(kind.emptyMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(kind.emptySubtitle)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
    }

    var loadingState: some View {
        ProgressView("Loading \(kind.analyticsLabel)...")
            .progressViewStyle(.circular)
            .tint(Theme.primaryColor)
            .frame(maxWidth: .infinity)
    }

    func errorState(message: String) -> some View {
        VStack(spacing: Theme.spacingSmall) {
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.red.opacity(0.85))

            Button {
                Task { await viewModel.retry() }
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.primaryColor.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
    }

    func profileRow(for profile: UserProfile) -> some View {
        HStack(spacing: Theme.spacingMedium) {
            avatar(for: profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)

                Text("@\(profile.username)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
        )
    }

    func avatar(for profile: UserProfile) -> some View {
        Group {
            if let imageURL = profile.profileImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholderAvatar(for: profile)
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
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    func placeholderAvatar(for profile: UserProfile) -> some View {
        let initials = avatarInitials(for: profile)
        return Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Theme.primaryGradientStart.opacity(0.9),
                        Theme.primaryGradientEnd.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            )
    }

    func avatarInitials(for profile: UserProfile) -> String {
        let source = profile.displayName.isEmpty ? profile.username : profile.displayName
        let components = source.split(separator: " ").prefix(2)
        if components.isEmpty {
            return "?"
        }
        let initials = components.map { String($0.prefix(1)).uppercased() }
        return initials.joined()
    }

    @ViewBuilder
    func destination(for profile: UserProfile) -> some View {
        if profile.accountType.isEngineer {
            EngineerDetailView(engineerId: profile.id, profile: profile, heroStyle: .compact)
        } else {
            ArtistDetailView(artistId: profile.id, profile: profile, heroStyle: .compact)
        }
    }
}

@MainActor
final class FollowConnectionsViewModel: ObservableObject {
    @Published private(set) var profiles: [UserProfile] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let userId: String
    private let kind: FollowConnectionsKind
    private let firestoreService: any FirestoreService

    init(userId: String, kind: FollowConnectionsKind, firestoreService: any FirestoreService) {
        self.userId = userId
        self.kind = kind
        self.firestoreService = firestoreService
    }

    func loadInitialIfNeeded() async {
        guard profiles.isEmpty else { return }
        await fetchProfiles()
    }

    func refresh() async {
        await fetchProfiles()
    }

    func retry() async {
        await fetchProfiles()
    }

    private func fetchProfiles() async {
        guard isLoading == false else { return }

        isLoading = true
        errorMessage = nil

        do {
            let results: [UserProfile]
            switch kind {
            case .followers:
                results = try await firestoreService.fetchFollowers(for: userId)
            case .following:
                results = try await firestoreService.fetchFollowing(for: userId)
            }

            profiles = results
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
