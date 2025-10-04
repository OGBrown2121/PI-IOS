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
    @State private var studiosPath = NavigationPath()
    @State private var chatPath = NavigationPath()
    @State private var bookPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            content(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, tabBarHeight)

            LiquidTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: TabBarHeightPreferenceKey.self, value: proxy.size.height)
                    }
                    .allowsHitTesting(false)
                }
        }
        .onPreferenceChange(TabBarHeightPreferenceKey.self) { newValue in
            tabBarHeight = newValue
        }
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .studios:
            NavigationStack(path: $studiosPath) {
                StudioListView(viewModel: StudiosViewModel(
                    firestoreService: di.firestoreService,
                    storageService: di.storageService
                ))
            }
        case .chat:
            NavigationStack(path: $chatPath) {
                ThreadsView(viewModel: ChatViewModel(chatService: di.chatService, appState: appState))
            }
        case .book:
            NavigationStack(path: $bookPath) {
                BookingInboxView(
                    bookingService: di.bookingService,
                    firestoreService: di.firestoreService,
                    reviewService: di.reviewService,
                    currentUserProvider: { appState.currentUser }
                )
            }
        case .settings:
            NavigationStack(path: $settingsPath) {
                SettingsView(
                    viewModel: SettingsViewModel(authService: di.authService, appState: appState),
                    studiosViewModel: StudiosViewModel(
                        firestoreService: di.firestoreService,
                        storageService: di.storageService
                    )
                )
            }
        }
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

private enum TabBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LiquidTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
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
        .background(.ultraThinMaterial, in: backgroundShape)
        .overlay {
            backgroundShape
                .stroke(borderStrokeColor, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            backgroundShape
                .stroke(topHighlightColor, lineWidth: 0.6)
        }
        .clipShape(backgroundShape)
    }

    private var overlayOpacity: Double {
        colorScheme == .dark ? 0.06 : 0.12
    }

    private var borderStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.09)
    }

    private var topHighlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(overlayOpacity) : Color.white.opacity(0.35)
    }

    private var backgroundShape: RoundedRectangle {
        .init(cornerRadius: 22, style: .continuous)
    }
}

private struct LiquidTabBarItem: View {
    @Environment(\.colorScheme) private var colorScheme
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
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(highlightOverlayColor, lineWidth: 0.5)
            )
    }

    private var activeColors: [Color] {
        if colorScheme == .dark {
            return [Theme.primaryGradientStart.opacity(0.35), Theme.primaryGradientEnd.opacity(0.35)]
        }
        return [Theme.primaryGradientStart.opacity(0.95), Theme.primaryGradientEnd.opacity(0.95)]
    }

    private var inactiveColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.white.opacity(0.02)]
        }
        return [Color.black.opacity(0.05), Color.black.opacity(0.015)]
    }

    private var iconColor: Color {
        if isSelected { return Color.white }
        return colorScheme == .dark ? Color.white.opacity(0.65) : Color.primary.opacity(0.7)
    }

    private var textColor: Color {
        if isSelected { return Color.white }
        return colorScheme == .dark ? Color.white.opacity(0.7) : Color.primary.opacity(0.7)
    }

    private var borderColor: Color {
        if isSelected {
            return colorScheme == .dark ? Theme.primaryGradientEnd.opacity(0.5) : Theme.primaryGradientEnd.opacity(0.7)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }

    private var highlightOverlayColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.3)
    }
}
