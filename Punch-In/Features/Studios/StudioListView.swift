import SwiftUI

struct StudioListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: StudiosViewModel
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @State private var isShowingAlerts = false
    @State private var selectedCategory: DiscoveryCategory = .studios

    init(viewModel: StudiosViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                discoveryHeader

                categorySelector

                categoryContent
            }
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingMedium)
        }
        .background(Theme.appBackground)
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingAlerts) {
            NavigationStack {
                AlertsView()
            }
        }
    }

    private var discoveryHeader: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            topBar

            VStack(alignment: .leading, spacing: 4) {
                Text("Punch-In")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))

                Text("Find collaborators")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }

            userSearchField

            searchFeedback

            Divider()
                .overlay(Color.primary.opacity(0.15))
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.spacingSmall) {
            notificationButton

            Spacer()

            ChatPillButton()
        }
    }

    private var categorySelector: some View {
        HStack(spacing: Theme.spacingSmall) {
            categoryArrow(direction: .previous)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacingSmall) {
                        ForEach(DiscoveryCategory.allCases) { category in
                            categoryButton(for: category)
                                .id(category)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity)
                .onAppear {
                    proxy.scrollTo(selectedCategory, anchor: .center)
                }
                .onChange(of: selectedCategory) { _, newValue in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            categoryArrow(direction: .next)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var notificationButton: some View {
        AlertsButton { isShowingAlerts = true }
            .padding(8)
            .background(buttonBackground)
            .overlay(buttonBorder)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.cardBackground)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }

    private var buttonBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .studios:
            studiosSection
        default:
            placeholderCard(
                title: selectedCategory.placeholderTitle,
                message: selectedCategory.placeholderMessage,
                iconName: selectedCategory.iconName
            )
        }
    }

    private func categoryArrow(direction: CategoryDirection) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selectedCategory = direction == .next ? selectedCategory.next() : selectedCategory.previous()
            }
        } label: {
            Image(systemName: direction == .next ? "chevron.right" : "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .background(buttonBackground)
                .overlay(buttonBorder)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .next ? "Next category" : "Previous category")
    }

    private func categoryButton(for category: DiscoveryCategory) -> some View {
        let isSelected = category == selectedCategory

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Theme.primaryColor.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.2) : Theme.primaryColor.opacity(0.1))
                    )

                Text(category.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
            }
            .frame(width: 78)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(categoryCapsuleBackground(isSelected: isSelected))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isSelected ? Theme.primaryColor.opacity(0.15) : Color.clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func categoryCapsuleBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(isSelected ? 1 : 0)
            )
    }

    private func placeholderCard(title: String, message: String, iconName: String) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay(
                VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                    HStack(spacing: Theme.spacingSmall) {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primaryColor)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Theme.primaryColor.opacity(0.12))
                            )

                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    }

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.spacingMedium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
            )
    }

    private var searchFeedback: some View {
        let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            if trimmed.isEmpty {
                Text("Search by username or display name to connect with new collaborators.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if trimmed.count < 2 {
                Text("Keep typing — enter at least two characters to see results.")
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
                Text("No matches yet. Try another name or handle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.userResults.enumerated()), id: \.element.id) { index, profile in
                        NavigationLink {
                            profileDestination(for: profile)
                        } label: {
                            UserSearchRow(profile: profile)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.userResults.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.top, Theme.spacingSmall)
            }
        }
        .padding(.top, Theme.spacingSmall)
    }

    private var userSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func profileDestination(for profile: UserProfile) -> some View {
        if profile.accountType.isEngineer {
            EngineerDetailView(engineerId: profile.id, profile: profile)
        } else if profile.accountType.isStudioOwner {
            if let studio = viewModel.studios.first(where: { $0.ownerId == profile.id }) {
                StudioDetailView(studio: studio)
            } else {
                StudioOwnerProfilePlaceholder(profile: profile)
            }
        } else {
            ArtistDetailView(artistId: profile.id, profile: profile)
        }
    }

    private var studioGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Theme.spacingSmall)
        ]
    }

    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("Studios")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                if !viewModel.studios.isEmpty {
                    Text("\(viewModel.studios.count) available")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.spacingSmall)

            if viewModel.isLoading && viewModel.studios.isEmpty {
                VStack(spacing: Theme.spacingSmall) {
                    HStack(spacing: Theme.spacingSmall) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading studios…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: studioGridColumns, alignment: .center, spacing: Theme.spacingMedium) {
                        ForEach(0..<4, id: \.self) { _ in
                            StudioCardPlaceholder()
                        }
                    }
                    .padding(.leading, Theme.spacingMedium)
                }
                .padding(.top, Theme.spacingSmall)
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(message: errorMessage)
            } else if viewModel.studios.isEmpty {
                emptyStateCard
            } else {
                LazyVGrid(columns: studioGridColumns, alignment: .center, spacing: Theme.spacingMedium) {
                    ForEach(viewModel.studios) { studio in
                        NavigationLink {
                            StudioDetailView(studio: studio)
                        } label: {
                            StudioCard(studio: studio)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, Theme.spacingMedium)
                .padding(.top, Theme.spacingSmall)
            }
        }
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
            .frame(maxWidth: .infinity)
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
            .frame(maxWidth: .infinity)
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

private enum DiscoveryCategory: String, CaseIterable, Identifiable, Hashable {
    case studios
    case engineers
    case producers
    case djs
    case videographers
    case photographers
    case eventCenters
    case podcasts

    var id: Self { self }

    var title: String {
        switch self {
        case .studios: return "Studios"
        case .engineers: return "Engineers"
        case .producers: return "Producers"
        case .djs: return "DJs"
        case .videographers: return "Videographers"
        case .photographers: return "Photographers"
        case .eventCenters: return "Event Centers"
        case .podcasts: return "Podcasts"
        }
    }

    var iconName: String {
        switch self {
        case .studios: return "music.note.house"
        case .engineers: return "wrench.and.screwdriver"
        case .producers: return "headphones"
        case .djs: return "music.quarternote.3"
        case .videographers: return "video.fill"
        case .photographers: return "camera.fill"
        case .eventCenters: return "building.2.fill"
        case .podcasts: return "mic.fill"
        }
    }

    var placeholderTitle: String {
        switch self {
        case .studios: return "Studios"
        case .engineers: return "Engineer discovery"
        case .producers: return "Producer discovery"
        case .djs: return "DJ spotlight"
        case .videographers: return "Videographer showcase"
        case .photographers: return "Photographer showcase"
        case .eventCenters: return "Event centers"
        case .podcasts: return "Podcast studios"
        }
    }

    var placeholderMessage: String {
        switch self {
        case .studios:
            return "Explore listed studios ready for collaboration."
        case .engineers:
            return "Browse curated engineers soon. We're preparing tailored recommendations."
        case .producers:
            return "Producer profiles are coming next. Check back for new talent."
        case .djs:
            return "We’re lining up DJs you can book for events and sessions. Stay tuned."
        case .videographers:
            return "Soon you’ll be able to discover videographers to capture your next project."
        case .photographers:
            return "Photographers are almost here. We’ll showcase creatives available to shoot."
        case .eventCenters:
            return "Find event-friendly spaces and venues once this hub goes live."
        case .podcasts:
            return "Podcast studios and hosts will appear here as we expand discovery."
        }
    }

    func next() -> DiscoveryCategory {
        guard let currentIndex = Self.allCases.firstIndex(of: self) else { return self }
        let nextIndex = Self.allCases.index(after: currentIndex)
        return nextIndex < Self.allCases.endIndex ? Self.allCases[nextIndex] : Self.allCases.first ?? self
    }

    func previous() -> DiscoveryCategory {
        guard let currentIndex = Self.allCases.firstIndex(of: self) else { return self }
        return currentIndex == Self.allCases.startIndex
            ? Self.allCases.last ?? self
            : Self.allCases[Self.allCases.index(before: currentIndex)]
    }
}

private enum CategoryDirection {
    case next
    case previous
}

private struct StudioCard: View {
    let studio: Studio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            coverImage

            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                Text(studio.city)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                infoRow
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var infoRow: some View {
        if !infoItems.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(infoItems.enumerated()), id: \.offset) { _, item in
                    infoBadge(title: item.title, systemImage: item.systemImage)
                }
            }
        }
    }

    private var infoItems: [(title: String, systemImage: String)] {
        var items: [(String, String)] = []
        if let rate = studio.hourlyRate {
            items.append((String(format: "$%.0f/hr", rate), "dollarsign.circle"))
        }
        if let rooms = studio.rooms {
            items.append(("\(rooms) room\(rooms == 1 ? "" : "s")", "music.note.house"))
        }
        if studio.amenities.isEmpty == false {
            items.append(("\(studio.amenities.count) amenit\(studio.amenities.count == 1 ? "y" : "ies")", "sparkles"))
        }
        return Array(items.prefix(2))
    }

    private var coverImage: some View {
        ZStack(alignment: .topLeading) {
            coverAsset

            if let logoURL = studio.logoImageURL {
                logoThumbnail(url: logoURL)
                    .padding(8)
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        )
    }

    private var coverAsset: some View {
        ZStack {
            placeholderCover

            if let coverURL = studio.coverImageURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            LinearGradient(
                colors: [Color.black.opacity(0.12), Color.black.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
    }

    private func logoThumbnail(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .progressViewStyle(.circular)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                fallbackLogo
            @unknown default:
                fallbackLogo
            }
        }
        .frame(width: 36, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 4)
    }

    private var fallbackLogo: some View {
        Image(systemName: "waveform.and.mic")
            .resizable()
            .scaledToFit()
            .padding(8)
            .foregroundStyle(Theme.primaryColor)
    }

    private var placeholderCover: some View {
        LinearGradient(
            colors: [
                Theme.primaryGradientStart.opacity(0.85),
                Theme.primaryGradientEnd.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func infoBadge(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct StudioCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 110)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 90, height: 9)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 60, height: 7)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.05), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
        .frame(maxWidth: .infinity, alignment: .center)
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
        .padding(.vertical, 8)
    }

    private var avatar: some View {
        avatarContent
            .frame(width: 40, height: 40)
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
        .background(Theme.appBackground)
        .navigationTitle(profile.displayName.isEmpty ? profile.username : profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
