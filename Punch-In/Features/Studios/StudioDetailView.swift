import SwiftUI

struct StudioDetailView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState

    let studio: Studio

    @State private var ownerProfile: UserProfile?
    @State private var isLoadingOwner = false
    @State private var ownerErrorMessage: String?
    @State private var acceptedEngineers: [UserProfile] = []
    @State private var isLoadingEngineers = false
    @State private var engineerErrorMessage: String?
    @State private var currentRequest: StudioEngineerRequest?
    @State private var isProcessingRequest = false
    @State private var isCancellingRequest = false
    @State private var requestErrorMessage: String?
    @State private var observedApprovedEngineerIds: [String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                heroHeader
                quickStatsCard
                engineerActionSection
                availableEngineersSection
                amenitiesSection
                detailsSection
            }
            .padding(Theme.spacingLarge)
        }
        .navigationTitle(studio.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOwnerIfNeeded()
            await loadEngineerRequestIfNeeded()
            updateEngineerStatusCache(with: studio.approvedEngineerIds)
            observedApprovedEngineerIds = studio.approvedEngineerIds
            await loadAcceptedEngineersIfNeeded(force: false)
        }
        .onChange(of: studio.approvedEngineerIds) { ids in
            updateEngineerStatusCache(with: ids)
            Task { await loadAcceptedEngineersIfNeeded(force: true) }
        }
    }

    private var heroHeader: some View {
        VStack(spacing: Theme.spacingLarge) {
            if let coverURL = studio.coverImageURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(uiColor: .secondarySystemGroupedBackground)
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color(uiColor: .secondarySystemGroupedBackground)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 200)
                .overlay(alignment: .bottomLeading) {
                    if let logoURL = studio.logoImageURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "music.note.house")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, height: 56)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                        )
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if let logoURL = studio.logoImageURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "music.note.house")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: 160)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(studio.name)
                    .font(.largeTitle.weight(.bold))
                Text(locationText)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let tagline = ownerProfile?.profileDetails.bio, !tagline.isEmpty {
                    Text(tagline)
                        .font(Theme.bodyFont())
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.spacingSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickStatsCard: some View {
        Group {
            if studio.rooms != nil || formattedHourlyRate != nil {
                HStack(spacing: Theme.spacingLarge) {
                    if let rooms = studio.rooms {
                        StatPill(icon: "square.grid.2x2", title: "Rooms", value: "\(rooms)")
                    }
                    if let rateText = formattedHourlyRate {
                        StatPill(icon: "clock", title: "Rate", value: rateText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var engineerActionSection: some View {
        if isCurrentUserEngineer {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                switch currentEngineerStatus {
                case .accepted:
                    Label("You're available at this studio", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    withdrawButton(title: "Leave this studio")
                case .pending:
                    HStack(spacing: Theme.spacingSmall) {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                        Text("Your request is pending review")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    withdrawButton(title: "Withdraw request")
                case .denied:
                    Label("Your last request was declined", systemImage: "xmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    requestButton(title: "Request again")
                case .none:
                    requestButton(title: "Request to work here")
                }

                if isProcessingRequest || isCancellingRequest {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.primaryColor)
                }

                if let requestErrorMessage {
                    Text(requestErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
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
        }
    }

    @ViewBuilder
    private var availableEngineersSection: some View {
        if isLoadingEngineers {
            HStack(spacing: Theme.spacingSmall) {
                ProgressView()
                Text("Loading engineers…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let engineerErrorMessage {
            Label(engineerErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if !acceptedEngineers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                Text("Available Engineers")
                    .font(.headline)

                ForEach(acceptedEngineers) { engineer in
                    NavigationLink {
                        EngineerDetailView(engineerId: engineer.id, profile: engineer)
                    } label: {
                        EngineerRow(profile: engineer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var amenitiesSection: some View {
        Group {
            if !studio.amenities.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text("Amenities")
                        .font(.headline)

                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(studio.amenities, id: \.self) { amenity in
                            Text(amenity)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Studio Details")
                .font(.headline)

            LabeledContent("Location", value: locationText)

            if !studio.address.isEmpty {
                LabeledContent("Address", value: studio.address)
            }

            if let rooms = studio.rooms {
                LabeledContent("Rooms", value: "\(rooms)")
            }

            if let rateText = formattedHourlyRate {
                LabeledContent("Hourly rate", value: rateText)
            }

            if let profile = ownerProfile {
                if !profile.profileDetails.fieldOne.isEmpty {
                    LabeledContent("Studio name", value: profile.profileDetails.fieldOne)
                }
                if !profile.profileDetails.fieldTwo.isEmpty {
                    LabeledContent("Studio location", value: profile.profileDetails.fieldTwo)
                }
            }

            Divider().padding(.vertical, Theme.spacingMedium)

            Text("Booking")
                .font(.headline)
            Text("Booking through PunchIn is coming soon. In the meantime, reach out to the owner directly to plan your session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var locationText: String {
        if let location = ownerProfile?.profileDetails.fieldTwo, !location.isEmpty {
            return location
        }
        if !studio.city.trimmed.isEmpty {
            return studio.city
        }
        if !studio.address.trimmed.isEmpty {
            return studio.address.trimmed
        }
        return "Location coming soon"
    }

    private var isCurrentUserEngineer: Bool {
        guard let profile = appState.currentUser else { return false }
        return profile.accountType == .engineer
    }

    private var currentEngineerId: String? {
        guard isCurrentUserEngineer, let id = appState.currentUser?.id else { return nil }
        return id
    }

    private var currentEngineerStatus: StudioEngineerRequest.Status? {
        if let engineerId = currentEngineerId,
           approvedEngineerIds.contains(engineerId) {
            return .accepted
        }
        return currentRequest?.status
    }

    private var formattedHourlyRate: String? {
        guard let rate = studio.hourlyRate else { return nil }
        return rate.formatted(.currency(code: "USD"))
    }

    private func loadOwnerIfNeeded() async {
        guard ownerProfile == nil, !isLoadingOwner else { return }
        isLoadingOwner = true
        ownerErrorMessage = nil

        do {
            ownerProfile = try await di.firestoreService.loadUserProfile(for: studio.ownerId)
        } catch {
            ownerErrorMessage = error.localizedDescription
        }

        isLoadingOwner = false
    }

    private func loadEngineerRequestIfNeeded() async {
        guard currentRequest == nil, let engineerId = currentEngineerId else { return }
        do {
            let request = try await di.firestoreService.fetchEngineerRequest(studioId: studio.id, engineerId: engineerId)
            currentRequest = request
        } catch {
            requestErrorMessage = error.localizedDescription
        }
    }

    private func loadAcceptedEngineersIfNeeded(force: Bool) async {
        let targetIDs = studio.approvedEngineerIds

        if targetIDs.isEmpty {
            acceptedEngineers = []
            engineerErrorMessage = nil
            observedApprovedEngineerIds = targetIDs
            return
        }

        if !force {
            let loadedIDs = acceptedEngineers.map(\.id)
            if loadedIDs == targetIDs {
                return
            }
        }

        isLoadingEngineers = true
        engineerErrorMessage = nil

        do {
            let profiles = try await di.firestoreService.fetchUserProfiles(for: targetIDs)
            acceptedEngineers = profiles
            observedApprovedEngineerIds = targetIDs
        } catch {
            engineerErrorMessage = error.localizedDescription
            acceptedEngineers = []
        }

        isLoadingEngineers = false
    }

    private func submitEngineerRequest() async {
        guard let engineerId = currentEngineerId else { return }
        guard currentEngineerStatus != .accepted else { return }

        isProcessingRequest = true
        requestErrorMessage = nil

        do {
            try await di.firestoreService.submitEngineerRequest(
                studioId: studio.id,
                studioOwnerId: studio.ownerId,
                engineerId: engineerId
            )
            currentRequest = try await di.firestoreService.fetchEngineerRequest(studioId: studio.id, engineerId: engineerId)
        } catch {
            requestErrorMessage = error.localizedDescription
        }

        isProcessingRequest = false
    }

    private func withdrawEngineerRequest() async {
        guard let engineerId = currentEngineerId else { return }
        isCancellingRequest = true
        requestErrorMessage = nil

        do {
            try await di.firestoreService.withdrawEngineerRequest(studioId: studio.id, engineerId: engineerId)
            currentRequest = nil
            acceptedEngineers.removeAll { $0.id == engineerId }
            let updatedIds = approvedEngineerIds.filter { $0 != engineerId }
            observedApprovedEngineerIds = updatedIds
            updateEngineerStatusCache(with: updatedIds)
            await loadAcceptedEngineersIfNeeded(force: true)
        } catch {
            requestErrorMessage = error.localizedDescription
        }

        isCancellingRequest = false
    }

    private func updateEngineerStatusCache(with ids: [String]) {
        guard let engineerId = currentEngineerId else { return }
        if ids.contains(engineerId) {
            if var request = currentRequest {
                request.status = .accepted
                request.updatedAt = Date()
                currentRequest = request
            } else {
                currentRequest = StudioEngineerRequest(
                    id: engineerId,
                    studioId: studio.id,
                    engineerId: engineerId,
                    studioOwnerId: studio.ownerId,
                    status: .accepted,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        } else if currentRequest?.status == .accepted {
            currentRequest = nil
        }
    }

    private var approvedEngineerIds: [String] {
        observedApprovedEngineerIds ?? studio.approvedEngineerIds
    }

    @ViewBuilder
    private func requestButton(title: String) -> some View {
        Button {
            Task { await submitEngineerRequest() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProcessingRequest || isCancellingRequest)
    }

    @ViewBuilder
    private func withdrawButton(title: String) -> some View {
        Button {
            Task { await withdrawEngineerRequest() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.primaryColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessingRequest || isCancellingRequest)
    }
}

private struct EngineerRow: View {
    let profile: UserProfile

    private var displayName: String {
        profile.displayName.isEmpty ? profile.username : profile.displayName
    }

    private var subtitle: String {
        if !profile.profileDetails.fieldOne.isEmpty {
            return profile.profileDetails.fieldOne
        }
        if !profile.profileDetails.fieldTwo.isEmpty {
            return profile.profileDetails.fieldTwo
        }
        return profile.profileDetails.bio
    }

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.spacingMedium)
        .padding(.horizontal, Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.elevatedCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageURL = profile.profileImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 54, height: 54)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                case .failure:
                    initialsView
                @unknown default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        let initials = displayName.split(separator: " ")
            .prefix(2)
            .map { $0.first.map(String.init) ?? "" }
            .joined()

        return Circle()
            .fill(Theme.primaryColor.opacity(0.15))
            .frame(width: 54, height: 54)
            .overlay(
                Text(initials.isEmpty ? String(displayName.prefix(2)) : initials)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor)
            )
    }
}

private struct StatPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StudioDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StudioDetailView(studio: .mock())
                .environment(\.di, DIContainer.makeMock())
                .environmentObject(previewAppState)
        }
    }

    private static var previewAppState: AppState {
        let state = AppState()
        state.currentUser = .mockEngineer
        state.isAuthenticated = true
        state.hasCompletedOnboarding = true
        return state
    }
}
