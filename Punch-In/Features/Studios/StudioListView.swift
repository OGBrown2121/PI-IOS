import SwiftUI

struct StudioListView: View {
    @StateObject private var viewModel: StudiosViewModel
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    init(viewModel: StudiosViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                heroBanner

                userSearchSection

                studiosSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task { viewModel.listenForStudios() }
        .onDisappear {
            viewModel.stopListening()
            toastDismissTask?.cancel()
        }
        .refreshable {
            let success = await viewModel.refreshStudios()
            await MainActor.run { showToast(success ? "Studios updated" : "Refresh failed") }
        }
        .toast(message: $toastMessage, bottomInset: 110)
    }

    private var heroBanner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(heroGradient)
                .shadow(color: Theme.primaryColor.opacity(0.2), radius: 16, x: 0, y: 12)

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Discovery Hub")
                    .font(.title.weight(.heavy))
                Text("Explore studios and discover artists or engineers to collaborate with.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(Theme.spacingLarge)
            .foregroundStyle(.white)
        }
    }

    private var userSearchSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Text("Find collaborators")
                .font(.headline.weight(.semibold))

            userSearchField

            if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text("Type at least two characters to search by username or display name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.isSearchingUsers {
                HStack(spacing: Theme.spacingSmall) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching users…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let message = viewModel.userSearchError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if viewModel.userResults.isEmpty {
                Text("No matching users yet. Try a different name or handle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.userResults.enumerated()), id: \.element.id) { index, profile in
                        NavigationLink {
                            profileDestination(for: profile)
                        } label: {
                            UserSearchRow(profile: profile)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.userResults.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.top, Theme.spacingSmall)
            }
        }
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var userSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search people", text: $viewModel.searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($isSearchFocused)
                .submitLabel(.search)

            if viewModel.isSearchingUsers {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
            } else if viewModel.searchQuery.isEmpty == false {
                Button {
                    viewModel.resetSearch()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func profileDestination(for profile: UserProfile) -> some View {
        switch profile.accountType {
        case .artist:
            ArtistDetailView(artistId: profile.id, profile: profile)
        case .engineer:
            EngineerDetailView(engineerId: profile.id, profile: profile)
        case .studioOwner:
            if let studio = viewModel.studios.first(where: { $0.ownerId == profile.id }) {
                StudioDetailView(studio: studio)
            } else {
                StudioOwnerProfilePlaceholder(profile: profile)
            }
        }
    }

    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack {
                Text("Studios")
                    .font(.headline.weight(.semibold))
                Spacer()
                if !viewModel.studios.isEmpty {
                    Text("\(viewModel.studios.count) available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.bottom, Theme.spacingSmall)

            if viewModel.isLoading && viewModel.studios.isEmpty {
                loadingCard
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(message: errorMessage)
            } else if viewModel.studios.isEmpty {
                emptyStateCard
            } else {
                VStack(spacing: Theme.spacingXLarge) {
                    ForEach(viewModel.studios) { studio in
                        NavigationLink {
                            StudioDetailView(studio: studio)
                        } label: {
                            StudioCard(studio: studio)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Theme.spacingXLarge)
            }
        }
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay(
                VStack(spacing: Theme.spacingSmall) {
                    ProgressView()
                    Text("Loading studios…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
            )
    }

    private func errorCard(message: String) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay(
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Label("We couldn't load studios", systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.primaryColor)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.spacingLarge)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
            )
    }

    private var emptyStateCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay(
                VStack(spacing: Theme.spacingSmall) {
                    Image(systemName: "music.note.house")
                        .font(.title)
                        .foregroundStyle(Theme.primaryColor)
                    Text("Studios will appear here soon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.spacingLarge)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
            )
    }

    private var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @MainActor
    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }

}

private struct StudioCard: View {
    let studio: Studio

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundContent
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(studio.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(studio.city)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 8) {
                    if let rate = studio.hourlyRate {
                        infoTag(text: String(format: "$%.0f/hr", rate))
                    }
                    if let rooms = studio.rooms {
                        infoTag(text: "\(rooms) room\(rooms == 1 ? "" : "s")")
                    }
                    if studio.amenities.isEmpty == false {
                        infoTag(text: "\(studio.amenities.count) amenit\(studio.amenities.count == 1 ? "y" : "ies")")
                    }
                }
            }
            .padding(Theme.spacingLarge)
        }
        .overlay(alignment: .topLeading) {
            if let logoURL = studio.logoImageURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        logoFallback
                    @unknown default:
                        logoFallback
                    }
                }
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(Theme.spacingMedium)
            }
        }
        .frame(height: 200)
    }

    private var logoFallback: some View {
        Image(systemName: "music.note.house")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(Theme.primaryColor)
    }

    @ViewBuilder
    private var backgroundContent: some View {
        GeometryReader { proxy in
            ZStack {
                if let cover = studio.coverImageURL {
                    AsyncImage(url: cover) { phase in
                        backgroundImage(for: phase)
                    }
                } else {
                    placeholderBackground
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func backgroundImage(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .empty:
            placeholderBackground
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
                .overlay(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.25), .clear], startPoint: .bottom, endPoint: .top))
        case .failure:
            placeholderBackground
        @unknown default:
            placeholderBackground
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func infoTag(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
    }
}

private struct UserSearchRow: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("@\(profile.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(profile.accountType.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor.opacity(0.9))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 10)
    }

    private var avatar: some View {
        avatarContent
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let imageURL = profile.profileImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .progressViewStyle(.circular)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
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

    private var placeholder: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let base = profile.displayName.isEmpty ? profile.username : profile.displayName
        let components = base.split(separator: " ")
        if let first = components.first, let second = components.dropFirst().first, let firstChar = first.first, let secondChar = second.first {
            return String(firstChar).uppercased() + String(secondChar).uppercased()
        }
        return String(base.prefix(2)).uppercased()
    }
}

private struct StudioOwnerProfilePlaceholder: View {
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLarge) {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Theme.primaryColor)

                VStack(spacing: Theme.spacingSmall) {
                    Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                        .font(.title3.weight(.semibold))
                    Text("This studio owner hasn’t listed a public studio yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.spacingLarge)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(profile.displayName.isEmpty ? profile.username : profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
