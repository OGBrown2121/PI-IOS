import SwiftUI

struct EngineerDetailView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState

    let engineerId: String

    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var availableStudios: [Studio] = []
    @State private var isLoadingStudios = false
    @State private var studiosErrorMessage: String?
    @State private var isBookingPresented = false
    @State private var selectedStudio: Studio?
    @State private var isSelectingStudio = false
    @State private var reviews: [Review] = []
    @State private var isLoadingReviews = false
    @State private var reviewsErrorMessage: String?

    init(engineerId: String, profile: UserProfile? = nil) {
        self.engineerId = engineerId
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                        heroSection(for: profile)
                        expertiseSection(for: profile)
                        detailsSection(for: profile)
                        reviewsSection
                        collaborationSection(for: profile)
                        if canCurrentUserBook {
                            PrimaryButton(title: "Book with \(profile.displayName.isEmpty ? profile.username : profile.displayName)") {
                                handleBookAction()
                            }
                        }
                        if let message = studiosErrorMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
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
                    "We couldn’t load this engineer",
                    systemImage: "wrench.fill",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadProfileIfNeeded()
            await loadStudiosIfNeeded()
            await loadReviews()
        }
        .sheet(isPresented: $isBookingPresented) {
            if let studio = selectedStudio, let profile {
                BookingFlowView(
                    studio: studio,
                    preferredEngineerId: profile.id,
                    bookingService: di.bookingService,
                    firestoreService: di.firestoreService,
                    currentUserProvider: { appState.currentUser }
                )
            }
        }
        .confirmationDialog("Choose a studio", isPresented: $isSelectingStudio, actions: {
            ForEach(availableStudios) { studio in
                Button(studio.name) {
                    selectedStudio = studio
                    isBookingPresented = true
                }
            }
            Button("Cancel", role: .cancel) {}
        })
    }

    private func heroSection(for profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall) {
            avatar(for: profile)
                .padding(.bottom, Theme.spacingSmall)

            Text(profile.accountType.title.uppercased())
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                .font(.largeTitle.weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("@\(profile.username)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            if !profile.profileDetails.bio.isEmpty {
                Text(profile.profileDetails.bio)
                    .font(Theme.bodyFont())
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spacingSmall)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacingLarge * 1.35)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Theme.primaryColor.opacity(0.28), radius: 18, x: 0, y: 12)
    }

    private func expertiseSection(for profile: UserProfile) -> some View {
        let labels = profile.accountType.requiredFieldLabels
        return sectionCard(title: "Expertise", icon: "slider.horizontal.3") {
            VStack(spacing: Theme.spacingMedium) {
                if labels.indices.contains(0) && !profile.profileDetails.fieldOne.isEmpty {
                    InfoPill(icon: "sparkles", title: labels[0], value: profile.profileDetails.fieldOne)
                }

                if labels.indices.contains(1) && !profile.profileDetails.fieldTwo.isEmpty {
                    InfoPill(icon: "clock.badge.checkmark", title: labels[1], value: profile.profileDetails.fieldTwo)
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
                Text("No reviews yet. Sessions completed with this engineer will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                reviewRatingSummary
                Divider()
                let featuredReviews = engineerTopReviews
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

    private var reviewRatingSummary: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.yellow)
                Text(engineerAverageRatingText)
                    .font(.title3.weight(.semibold))
            }

            Text("\(reviews.count) review\(reviews.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var engineerAverageRatingText: String {
        guard let rating = engineerAverageRating else { return "–" }
        return String(format: "%.1f", rating)
    }

    private var engineerAverageRating: Double? {
        guard reviews.isEmpty == false else { return nil }
        let total = reviews.reduce(0.0) { $0 + Double($1.rating) }
        return total / Double(reviews.count)
    }

    private var engineerTopReviews: [Review] {
        Array(engineerSortedReviews.prefix(3))
    }

    private var engineerSortedReviews: [Review] {
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

    private func collaborationSection(for profile: UserProfile) -> some View {
        sectionCard(title: "Collaboration", icon: "waveform.path.ecg") {
            Text("Interested in working with \(profile.displayName.isEmpty ? profile.username : profile.displayName)? Reach out through chat or invite them to a project once booking launches.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private func handleBookAction() {
        guard availableStudios.isEmpty == false else {
            studiosErrorMessage = "This engineer has not connected to any studios yet."
            return
        }
        studiosErrorMessage = nil
        if availableStudios.count == 1 {
            selectedStudio = availableStudios.first
            isBookingPresented = true
        } else {
            isSelectingStudio = true
        }
    }

    private func loadStudiosIfNeeded() async {
        guard availableStudios.isEmpty, isLoadingStudios == false else { return }
        isLoadingStudios = true
        defer { isLoadingStudios = false }
        do {
            let studios = try await di.firestoreService.fetchStudios()
            availableStudios = studios.filter { $0.approvedEngineerIds.contains(engineerId) }
            studiosErrorMessage = nil
        } catch {
            studiosErrorMessage = error.localizedDescription
        }
    }

    private func loadReviews() async {
        guard isLoadingReviews == false else { return }
        isLoadingReviews = true
        reviewsErrorMessage = nil

        do {
            reviews = try await di.reviewService.fetchReviews(for: engineerId, kind: .engineer)
        } catch {
            reviewsErrorMessage = error.localizedDescription
        }

        isLoadingReviews = false
    }

    private var canCurrentUserBook: Bool {
        guard let user = appState.currentUser else { return false }
        return user.accountType == .artist
    }

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
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 4)
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

    private func loadProfileIfNeeded() async {
        guard profile == nil else { return }
        await loadProfile(force: false)
    }

    private func loadProfile(force: Bool) async {
        guard force || profile == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            profile = try await di.firestoreService.loadUserProfile(for: engineerId)
            if profile == nil {
                errorMessage = "We couldn't find this engineer."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct InfoPill: View {
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

#Preview("Engineer Detail") {
    NavigationStack {
        EngineerDetailView(engineerId: "preview", profile: .mockEngineer)
            .environment(\.di, DIContainer.makeMock())
    }
}
