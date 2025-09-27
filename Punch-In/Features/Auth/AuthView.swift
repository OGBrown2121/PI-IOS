import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel: AuthViewModel

    // Provide a video file (default AuthBackground.mp4) in the bundle to enable the looping backdrop.
    private let backgroundVideoFileName: String?
    private let backgroundVideoFileExtension: String

    init(
        viewModel: AuthViewModel,
        backgroundVideoFileName: String? = "AuthBackground",
        backgroundVideoFileExtension: String = "mp4"
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.backgroundVideoFileName = backgroundVideoFileName
        self.backgroundVideoFileExtension = backgroundVideoFileExtension
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundView
                .ignoresSafeArea()

            content
        }
        .foregroundStyle(.white)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLarge) {
            header

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }

            VStack(spacing: Theme.spacingSmall) {
                PrimaryButton(title: "Continue with Apple") {
                    Task { await viewModel.signInWithApple() }
                }
                .disabled(viewModel.isLoading)

                PrimaryButton(title: "Continue with Google") {
                    Task { await viewModel.signInWithGoogle() }
                }
                .disabled(viewModel.isLoading)
            }

            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .fullWidth()
            }

            Spacer()
        }
        .padding(Theme.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Welcome")
                .font(.title.weight(.heavy))

            Text("PunchIn")
                .font(.system(size: 44, weight: .black, design: .rounded))

            Text("Clock into your creative flow.")
                .font(Theme.bodyFont())
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }

    private var backgroundView: some View {
        Group {
            if let url = backgroundVideoURL {
                LoopingVideoView(url: url)
                    .allowsHitTesting(false)
                    .overlay(overlayGradient)
            } else {
                overlayGradient
            }
        }
    }

    private var overlayGradient: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.85), Color.black.opacity(0.55), Color.black.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var backgroundVideoURL: URL? {
        guard let resourceName = backgroundVideoFileName else { return nil }
        return Bundle.main.url(forResource: resourceName, withExtension: backgroundVideoFileExtension)
    }
}

#Preview("Auth View") {
    let appState = AppState()
    return AuthView(
        viewModel: AuthViewModel(
            authService: MockAuthService(),
            firestoreService: MockFirestoreService(),
            appState: appState
        )
    )
    .environmentObject(appState)
    .environment(\.di, DIContainer.makeMock())
}
