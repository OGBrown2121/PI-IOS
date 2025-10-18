import SwiftUI

struct AppRouter: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var alertsCenter: AlertsCenter
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
        .background(Theme.appBackground)
        .animation(.default, value: appState.isAuthenticated)
        .animation(.default, value: appState.hasCompletedOnboarding)
        .task {
            if let userId = appState.currentUser?.id {
                alertsCenter.start(for: userId)
            } else {
                alertsCenter.stop()
            }
        }
        .onChange(of: appState.currentUser?.id) { _, newValue in
            if let newValue {
                alertsCenter.start(for: newValue)
            } else {
                alertsCenter.stop()
            }
        }
    }
}

private struct MainTabView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager
    @State private var discoveryPath = NavigationPath()
    @State private var eventsPath = NavigationPath()
    @State private var bookPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var tabBarHeight: CGFloat = 0
    @State private var miniPlayerHeight: CGFloat = 0
    @State private var uploadBannerHeight: CGFloat = 0
    @State private var isShowingNowPlaying = false
    @State private var deepLinkMediaItem: ProfileMediaItem?
    @State private var radioProgress: CGFloat = 0
    @State private var radioDragStartProgress: CGFloat = 0
    @State private var isDraggingRadio = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .leading) {
                baseStack
                    .frame(width: width)
                    .offset(x: -radioProgress * width)
                    .allowsHitTesting(radioProgress < 0.99)

                if shouldShowRadioOverlay {
                    LocalArtistRadioView(
                        viewModel: LocalArtistRadioViewModel(
                            firestoreService: di.firestoreService,
                            playbackManager: playbackManager,
                            currentUserProvider: { appState.currentUser }
                        ),
                        onClose: {
                            withAnimation(radioSnapAnimation) {
                                radioProgress = 0
                            }
                        }
                    )
                    .frame(width: width, height: geometry.size.height)
                    .offset(x: (1 - radioProgress) * width)
                    .environmentObject(playbackManager)
                    .environmentObject(appState)
                    .environment(\.di, di)
                    .opacity(max(radioProgress, 0.001))
                    .zIndex(50)
                    .allowsHitTesting(radioProgress > 0.02)
                    .transition(.identity)
                }
            }
            .background(Theme.appBackground.ignoresSafeArea())
            .gesture(radioDragGesture(width: width))
        }
        .onPreferenceChange(TabBarHeightPreferenceKey.self) { newValue in
            tabBarHeight = newValue
        }
        .onPreferenceChange(UploadBannerHeightPreferenceKey.self) { newValue in
            uploadBannerHeight = newValue
        }
        .onPreferenceChange(MiniPlayerHeightPreferenceKey.self) { newValue in
            miniPlayerHeight = newValue
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            if let item = playbackManager.currentItem {
                NavigationStack {
                    ProfileMediaDetailView(
                        media: item,
                        firestoreService: di.firestoreService,
                        storageService: di.storageService,
                        reportService: di.reportService,
                        currentUserProvider: { appState.currentUser }
                    )
                }
                .environmentObject(uploadManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingChat },
            set: { appState.isShowingChat = $0 }
        )) {
            NavigationStack {
                ThreadsView(viewModel: ChatViewModel(chatService: di.chatService, appState: appState))
            }
        }
        .sheet(item: $deepLinkMediaItem) { media in
            NavigationStack {
                ProfileMediaDetailView(
                    media: media,
                    firestoreService: di.firestoreService,
                    storageService: di.storageService,
                    reportService: di.reportService,
                    currentUserProvider: { appState.currentUser }
                )
            }
            .environmentObject(playbackManager)
            .environmentObject(appState)
            .environmentObject(uploadManager)
        }
        .onChange(of: appState.targetChatThreadID) { _, newValue in
            guard let threadId = newValue else { return }
            Task {
                do {
                    let thread = try await di.chatService.thread(withId: threadId)
                    await MainActor.run {
                        if appState.isShowingChat == false {
                            appState.isShowingChat = true
                        }
                        appState.pendingChatThread = thread
                        appState.targetChatThreadID = nil
                    }
                } catch {
                    await MainActor.run {
                        Logger.log("Failed to open chat thread \(threadId): \(error.localizedDescription)")
                        appState.pendingChatThread = nil
                        appState.targetChatThreadID = nil
                    }
                }
            }
        }
        .onChange(of: appState.targetBookingID) { _, newValue in
            guard newValue != nil else { return }
            if appState.selectedTab != .book {
                appState.selectedTab = .book
            }
        }
        .onChange(of: appState.targetMediaID) { _, newValue in
            guard let mediaId = newValue else { return }
            guard let ownerId = appState.currentUser?.id else {
                appState.targetMediaID = nil
                return
            }
            Task {
                do {
                    if let media = try await di.firestoreService.loadProfileMedia(ownerId: ownerId, mediaId: mediaId) {
                        await MainActor.run {
                            deepLinkMediaItem = media
                            if appState.selectedTab != .profile {
                                appState.selectedTab = .profile
                            }
                        }
                    } else {
                        await MainActor.run {
                            Logger.log("Profile media item not found for id=\(mediaId)")
                        }
                    }
                } catch {
                    await MainActor.run {
                        Logger.log("Failed to load profile media \(mediaId): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    appState.targetMediaID = nil
                }
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .discovery:
            NavigationStack(path: $discoveryPath) {
                StudioListView(viewModel: StudiosViewModel(
                    firestoreService: di.firestoreService,
                    storageService: di.storageService
                ))
            }
        case .events:
            NavigationStack(path: $eventsPath) {
                EventsView()
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
        case .profile:
            NavigationStack(path: $profilePath) {
                ProfileTabView()
            }
        }
    }
}

extension MainTabView {
    private var shouldShowRadioOverlay: Bool {
        radioProgress > 0.001 || isDraggingRadio
    }

    private var radioSnapAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.15)
    }

    @ViewBuilder
    private var baseStack: some View {
        ZStack(alignment: .bottom) {
            content(for: appState.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(
                    .bottom,
                    tabBarHeight
                        + (uploadManager.activeUpload == nil ? 0 : uploadBannerHeight + 12)
                        + (playbackManager.currentItem == nil ? 0 : miniPlayerHeight + 12)
                )

            if shouldShowRadioOverlay == false {
                VStack(spacing: 12) {
                    if uploadManager.activeUpload != nil {
                        ProfileMediaUploadBanner()
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: UploadBannerHeightPreferenceKey.self, value: proxy.size.height)
                                }
                            )
                    }

                    if playbackManager.currentItem != nil {
                        ProfileMediaMiniPlayer { _ in
                            isShowingNowPlaying = true
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: MiniPlayerHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                    }

                    LiquidTabBar(selectedTab: Binding(
                        get: { appState.selectedTab },
                        set: { appState.selectedTab = $0 }
                    ))
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
            }
        }
    }

    private func clampProgress(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func radioDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                if isDraggingRadio == false {
                    radioDragStartProgress = radioProgress
                }
            }
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if isDraggingRadio == false {
                    guard abs(horizontal) > abs(vertical) else { return }
                    isDraggingRadio = true
                }
                guard isDraggingRadio else { return }

                let delta = -horizontal / width
                let updated = radioDragStartProgress + delta
                radioProgress = clampProgress(updated)
            }
            .onEnded { value in
                guard isDraggingRadio else { return }
                isDraggingRadio = false

                let predicted = radioDragStartProgress + (-value.predictedEndTranslation.width / width)
                let current = radioDragStartProgress + (-value.translation.width / width)
                let clampedPredicted = clampProgress(predicted)
                let clampedCurrent = clampProgress(current)
                let shouldOpen = clampedPredicted > 0.45 || clampedCurrent > 0.45
                withAnimation(radioSnapAnimation) {
                    radioProgress = shouldOpen ? 1 : 0
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

private enum MiniPlayerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum UploadBannerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LiquidTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                LiquidTabBarItem(tab: tab, isSelected: selectedTab == tab) {
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
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon

                Text(tab.title)
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
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.bounce, value: isSelected)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: tab.icon)
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
