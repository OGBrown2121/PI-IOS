import SwiftUI

struct ProfileTabView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var alertsCenter: AlertsCenter
    @State private var isShowingAlerts = false
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if let profile = appState.currentUser {
                if profile.accountType.isEngineer {
                    EngineerDetailView(engineerId: profile.id, profile: profile, heroStyle: .compact)
                } else if profile.accountType.isStudioOwner {
                    ArtistDetailView(artistId: profile.id, profile: profile, heroStyle: .compact)
                } else {
                    ArtistDetailView(artistId: profile.id, profile: profile, heroStyle: .compact)
                }
            } else {
                ContentUnavailableView(
                    "Profile unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Sign in to view and share your public profile.")
                )
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AlertsButton { isShowingAlerts = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ChatPillButton()
                settingsButton
            }
        }
        .sheet(isPresented: $isShowingAlerts) {
            NavigationStack {
                AlertsView()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(
                    viewModel: SettingsViewModel(authService: di.authService, appState: appState),
                    studiosViewModel: StudiosViewModel(
                        firestoreService: di.firestoreService,
                        storageService: di.storageService
                    )
                )
            }
            .environment(\.di, di)
            .environmentObject(appState)
            .environmentObject(alertsCenter)
        }
    }
}

private extension ProfileTabView {
    var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 18, height: 18)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.cardBackground)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
    }
}
