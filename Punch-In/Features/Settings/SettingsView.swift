import SwiftUI

struct SettingsView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: SettingsViewModel
    @State private var isPresentingProfileEditor = false
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                if let profile = appState.currentUser {
                    profileSummarySection(profile)
                    profileActionsSection(profile)
                }

                managementSection
                aboutSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .refreshable {
            let refreshed = await reloadProfile()
            await MainActor.run { showToast(refreshed ? "Profile updated" : "Up to date") }
        }
        .toast(message: $toastMessage, bottomInset: 120)
        .onDisappear { toastDismissTask?.cancel() }
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
    }
}

private extension SettingsView {
    func profileSummarySection(_ profile: UserProfile) -> some View {
        ProfileSummaryCard(profile: profile)
    }

    func profileActionsSection(_ profile: UserProfile) -> some View {
        VStack(spacing: Theme.spacingSmall) {
            if profile.accountType == .engineer {
                NavigationLink {
                    EngineerDetailView(engineerId: profile.id, profile: profile)
                } label: {
                    liquidAction(title: "View Public Profile", icon: "person.text.rectangle", chevron: true)
                }
                .buttonStyle(.plain)
            } else if profile.accountType == .artist {
                NavigationLink {
                    ArtistDetailView(artistId: profile.id, profile: profile)
                } label: {
                    liquidAction(title: "View Public Profile", icon: "person.text.rectangle", chevron: true)
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

    var managementSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Text("Account")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                viewModel.signOut()
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
        guard let userId = appState.currentUser?.id else { return false }
        do {
            if let refreshed = try await di.firestoreService.loadUserProfile(for: userId) {
                appState.currentUser = refreshed
                return true
            }
        } catch {
            Logger.log("Failed to refresh profile: \(error.localizedDescription)")
        }
        return false
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

#Preview("Settings") {
    let appState = AppState()
    appState.currentUser = UserProfile.mock
    return SettingsView(viewModel: SettingsViewModel(authService: MockAuthService(), appState: appState))
        .environmentObject(appState)
        .environment(\.di, DIContainer.makeMock())
}
