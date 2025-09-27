import SwiftUI

struct AppRouter: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.di) private var di

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                NavigationStack {
                    AuthView(viewModel: AuthViewModel(
                        authService: di.authService,
                        firestoreService: di.firestoreService,
                        appState: appState
                    ))
                    .navigationTitle("Welcome")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if !appState.hasCompletedOnboarding {
                NavigationStack {
                    OnboardingView(viewModel: OnboardingViewModel(
                        appState: appState,
                        firestoreService: di.firestoreService,
                        storageService: di.storageService
                    ))
                    .navigationTitle("Onboarding")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                MainTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.default, value: appState.isAuthenticated)
        .animation(.default, value: appState.hasCompletedOnboarding)
    }
}

private struct MainTabView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .studios

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    StudioListView(viewModel: StudiosViewModel(
                        firestoreService: di.firestoreService,
                        storageService: di.storageService
                    ))
                }
                .tag(Tab.studios)

                NavigationStack {
                    ThreadsView(viewModel: ChatViewModel(chatService: di.chatService, appState: appState))
                }
                .tag(Tab.chat)

                NavigationStack {
                    BookingPlaceholderView()
                        .navigationTitle("Bookings")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tag(Tab.book)

                NavigationStack {
                    SettingsView(viewModel: SettingsViewModel(authService: di.authService, appState: appState))
                }
                .tag(Tab.settings)
            }
            .toolbar(.hidden, for: .tabBar)

            LiquidTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    fileprivate enum Tab: String, CaseIterable, Hashable {
        case studios, chat, book, settings

        var title: String {
            switch self {
            case .studios: return "Studios"
            case .chat: return "Chat"
            case .book: return "Book"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .studios: return "building.2"
            case .chat: return "bubble.left.and.bubble.right"
            case .book: return "calendar"
            case .settings: return "gear"
            }
        }
    }
}

private struct LiquidTabBar: View {
    @Binding var selectedTab: MainTabView.Tab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MainTabView.Tab.allCases, id: \.self) { tab in
                LiquidTabBarItem(title: tab.title, systemImage: tab.icon, isSelected: selectedTab == tab) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.2)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 18, y: 14)
        )
    }
}

private struct LiquidTabBarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(textColor)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
            .background(background)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.bounce, value: isSelected)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isSelected ? activeColors : inactiveColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 0.9 : 0.45)
            )
            .shadow(color: shadowColor, radius: isSelected ? 7 : 4, y: isSelected ? 4 : 2)
    }

    private var activeColors: [Color] {
        [Theme.primaryGradientStart.opacity(0.35), Theme.primaryGradientEnd.opacity(0.35)]
    }

    private var inactiveColors: [Color] {
        [Color.white.opacity(0.08), Color.white.opacity(0.02)]
    }

    private var iconColor: Color {
        isSelected ? Color.white : Color.white.opacity(0.65)
    }

    private var textColor: Color {
        isSelected ? Color.white : Color.white.opacity(0.7)
    }

    private var borderColor: Color {
        isSelected ? Theme.primaryGradientEnd.opacity(0.5) : Color.white.opacity(0.12)
    }

    private var shadowColor: Color {
        isSelected ? Theme.primaryGradientEnd.opacity(0.28) : Color.black.opacity(0.2)
    }
}
