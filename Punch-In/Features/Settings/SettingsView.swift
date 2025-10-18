import SwiftUI

struct SettingsView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var studiosViewModel: StudiosViewModel
    @State private var isPresentingProfileEditor = false
    @State private var isManagingStudio = false
    @State private var studioToEdit: Studio?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var isShowingAlerts = false

    init(viewModel: SettingsViewModel, studiosViewModel: StudiosViewModel) {
        _settingsViewModel = StateObject(wrappedValue: viewModel)
        _studiosViewModel = StateObject(wrappedValue: studiosViewModel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                if let profile = appState.currentUser {
                    profileSummarySection(profile)
                    profileActionsSection(profile)
                    if profile.accountType.isArtistFamily {
                        DriveDownloadRequestsCard(profile: profile)
                    }
                    if profile.accountType.canViewStudioOwnerTools {
                        ownerToolsSection
                    }
                }

                managementSection
                aboutSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
            .background(Theme.appBackground)
        }
        .refreshable {
            let refreshed = await reloadProfile()
            await MainActor.run { showToast(refreshed ? "Details updated" : "Up to date") }
        }
        .toast(message: $toastMessage, bottomInset: 120)
        .task {
            if isOwner {
                studiosViewModel.listenForStudios()
            }
        }
        .onReceive(studiosViewModel.$studios) { _ in
            guard isManagingStudio else { return }
            if let updatedStudio = ownedStudio {
                studioToEdit = updatedStudio
            }
        }
        .onChangeCompatibility(of: appState.currentUser?.accountType) { newValue in
            if newValue?.canViewStudioOwnerTools == true {
                studiosViewModel.listenForStudios()
            } else {
                studiosViewModel.stopListening()
            }
        }
        .onDisappear {
            toastDismissTask?.cancel()
            studiosViewModel.stopListening()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AlertsButton { isShowingAlerts = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatPillButton()
            }
        }
        .sheet(isPresented: $isShowingAlerts) {
            NavigationStack {
                AlertsView()
            }
        }
        .sheet(isPresented: $isPresentingProfileEditor) {
            NavigationStack {
                OnboardingView(
                    viewModel: OnboardingViewModel(
                        appState: appState,
                        firestoreService: di.firestoreService,
                        storageService: di.storageService
                    ),
                    mode: .editing
                )
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $isManagingStudio, onDismiss: { studioToEdit = nil }) {
            NavigationStack {
                StudioEditorView(existingStudio: studioToEdit) { data in
                    guard let ownerId = appState.currentUser?.id else {
                        return "You need to be signed in to manage a studio."
                    }

                    return await studiosViewModel.saveStudio(
                        name: data.name,
                        city: data.city,
                        ownerId: ownerId,
                        studioId: studioToEdit?.id,
                        address: data.address,
                        hourlyRate: data.numericHourlyRate,
                        rooms: data.numericRooms,
                        amenities: data.amenitiesList,
                        coverImageData: data.newCoverImageData,
                        logoImageData: data.newLogoImageData,
                        coverImageContentType: data.coverImageContentType,
                        logoImageContentType: data.logoImageContentType,
                        existingCoverURL: data.existingCoverURL,
                        existingLogoURL: data.existingLogoURL,
                        removeCoverImage: data.removeCoverImage,
                        removeLogoImage: data.removeLogoImage
                    )
                }
            }
        }
    }
}

private extension SettingsView {
    func profileSummarySection(_ profile: UserProfile) -> some View {
        ProfileSummaryCard(profile: profile)
    }

    func profileActionsSection(_ profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall) {
            if profile.accountType.isEngineer {
                NavigationLink {
                    EngineerDetailView(engineerId: profile.id, profile: profile)
                } label: {
                    liquidAction(title: "View Public Profile", icon: "person.text.rectangle", chevron: true)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EngineerAvailabilityManagementView(
                        engineer: profile,
                        firestore: di.firestoreService,
                        currentUserProvider: { appState.currentUser },
                        onProfileUpdate: { updated in
                            appState.currentUser = updated
                        }
                    )
                } label: {
                    liquidAction(title: "Manage Availability", icon: "calendar", chevron: true)
                }
                .buttonStyle(.plain)
            } else if profile.accountType.isArtistFamily {
                NavigationLink {
                    ArtistDetailView(artistId: profile.id, profile: profile)
                } label: {
                    liquidAction(title: "View Public Profile", icon: "person.text.rectangle", chevron: true)
                }
                .buttonStyle(.plain)
            }

            if profile.accountType.supportsProfileMediaLibrary {
                NavigationLink {
                    ProfileMediaLibraryView(
                        viewModel: ProfileMediaLibraryViewModel(
                            firestoreService: di.firestoreService,
                            storageService: di.storageService,
                            currentUserProvider: { appState.currentUser },
                            uploadManager: uploadManager
                        )
                    )
                } label: {
                    liquidAction(title: "Manage Media Library", icon: "tray.and.arrow.up", chevron: true)
                }
                .buttonStyle(.plain)
            }

            if profile.accountType == .producer {
                NavigationLink {
                    BeatCatalogManagerView(
                        viewModel: BeatCatalogManagerViewModel(
                            firestore: di.firestoreService,
                            storage: di.storageService,
                            currentUserProvider: { appState.currentUser }
                        )
                    )
                } label: {
                    liquidAction(title: "Manage Beat Catalog", icon: "music.note.list", chevron: true)
                }
                .buttonStyle(.plain)
            }

            Button {
                isPresentingProfileEditor = true
            } label: {
                liquidAction(title: "Edit Profile", icon: "square.and.pencil", chevron: false)
            }
            .buttonStyle(.plain)
        }
    }

    var ownerToolsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Text("Owner Tools")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                studioToEdit = ownedStudio
                isManagingStudio = true
            } label: {
                OwnerToolsActionCard(
                    title: ownedStudio == nil ? "Add Your Studio" : "Manage Your Studio",
                    icon: ownedStudio == nil ? "building.2" : "slider.horizontal.3",
                    chevron: false
                )
            }
            .buttonStyle(.plain)

            if let managedStudio = ownedStudio {
                NavigationLink {
                    EngineerRequestsView(studio: managedStudio, firestoreService: di.firestoreService)
                } label: {
                    OwnerToolsActionCard(
                        title: "Engineer Requests",
                        icon: "person.crop.circle.badge.questionmark",
                        chevron: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StudioAvailabilityManagementView(
                        studio: managedStudio,
                        firestore: di.firestoreService,
                        currentUserProvider: { appState.currentUser }
                    )
                } label: {
                    OwnerToolsActionCard(
                        title: "Availability & Hours",
                        icon: "calendar",
                        chevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var managementSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Text("Account")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                settingsViewModel.signOut()
            } label: {
                Text("Sign Out")
                    .fullWidth(alignment: .center)
                    .padding(.vertical, Theme.spacingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
        }
    }

    var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Text("About")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            infoRow(title: "App", value: Constants.appName)
            infoRow(title: "Version", value: Constants.appVersion)
        }
    }

    func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    func liquidAction(title: String, icon: String, chevron: Bool) -> some View {
        SettingsActionCard(title: title, icon: icon, chevron: chevron)
    }

    func reloadProfile() async -> Bool {
        var didUpdate = false

        if let userId = appState.currentUser?.id {
            do {
                if let refreshed = try await di.firestoreService.loadUserProfile(for: userId) {
                    appState.currentUser = refreshed
                    didUpdate = true
                }
            } catch {
                Logger.log("Failed to refresh profile: \(error.localizedDescription)")
            }
        }

        let studiosRefreshed: Bool
        if isOwner {
            studiosRefreshed = await studiosViewModel.refreshStudios()
        } else {
            studiosViewModel.stopListening()
            studiosRefreshed = false
        }
        return didUpdate || studiosRefreshed
    }

    @MainActor
    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }

    var ownedStudio: Studio? {
        guard let ownerId = appState.currentUser?.id else { return nil }
        return studiosViewModel.studios.first { $0.ownerId == ownerId }
    }

    var isOwner: Bool {
        appState.currentUser?.accountType.canViewStudioOwnerTools == true
    }
}

private struct SettingsActionCard: View {
    let title: String
    let icon: String
    var chevron: Bool

    private var isPrimary: Bool { !chevron }

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(isPrimary ? Color.white.opacity(0.95) : Theme.primaryColor.opacity(0.9))

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.white : .primary)

            Spacer()

            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, Theme.spacingSmall + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassBackground)
        .overlay(glassBorder)
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 8)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(primaryTint)
            )
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(borderGradient, lineWidth: isPrimary ? 1.4 : 0.8)
    }

    private var primaryTint: LinearGradient {
        LinearGradient(
            colors: isPrimary
                ? [Theme.primaryGradientStart.opacity(0.32), Theme.primaryGradientEnd.opacity(0.32)]
                : [Color.white.opacity(0.08), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: isPrimary
                ? [Color.white.opacity(0.5), Theme.primaryGradientEnd.opacity(0.5)]
                : [Color.white.opacity(0.3), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct OwnerToolsActionCard: View {
    let title: String
    let icon: String
    var chevron: Bool = true

    private var isPrimaryAction: Bool { !chevron }

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(textColor)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, Theme.spacingSmall + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassBackground)
        .overlay(glassBorder)
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 10)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(primaryTint)
            )
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(borderGradient, lineWidth: isPrimaryAction ? 1.6 : 1.0)
    }

    private var primaryTint: LinearGradient {
        LinearGradient(
            colors: isPrimaryAction
                ? [Theme.primaryGradientStart.opacity(0.32), Theme.primaryGradientEnd.opacity(0.32)]
                : [Color.white.opacity(0.08), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: isPrimaryAction
                ? [Color.white.opacity(0.55), Theme.primaryGradientEnd.opacity(0.55)]
                : [Color.white.opacity(0.35), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var textColor: Color {
        isPrimaryAction ? Color.white.opacity(0.96) : .primary
    }

    private var iconColor: Color {
        isPrimaryAction ? Color.white.opacity(0.96) : Theme.primaryColor.opacity(0.9)
    }
}

#Preview("Settings") {
    let appState = AppState()
    appState.currentUser = UserProfile.mock
    let di = DIContainer.makeMock()
    return SettingsView(
        viewModel: SettingsViewModel(authService: MockAuthService(), appState: appState),
        studiosViewModel: StudiosViewModel(
            firestoreService: MockFirestoreService(),
            storageService: MockStorageService()
        )
    )
    .environmentObject(appState)
    .environmentObject(ProfileMediaUploadManager(firestoreService: di.firestoreService))
    .environment(\.di, di)
}
