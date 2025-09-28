import SwiftUI

struct StudioListView: View {
    @StateObject private var viewModel: StudiosViewModel
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    init(viewModel: StudiosViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                heroBanner

                studiosSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
    }

    private var heroBanner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(heroGradient)
                .shadow(color: Theme.primaryColor.opacity(0.2), radius: 16, x: 0, y: 12)

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("PunchIn Studios")
                    .font(.title.weight(.heavy))
                Text("Find the perfect space, vibe, and engineering support for your next session.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(Theme.spacingLarge)
            .foregroundStyle(.white)
        }
    }

    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack {
                Text("Studios")
                    .font(.headline.weight(.semibold))
                Spacer()
                if !viewModel.studios.isEmpty {
                    Text("\(viewModel.studios.count) available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.bottom, Theme.spacingSmall)

            if viewModel.isLoading && viewModel.studios.isEmpty {
                loadingCard
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(message: errorMessage)
            } else if viewModel.studios.isEmpty {
                emptyStateCard
            } else {
                VStack(spacing: Theme.spacingXLarge) {
                    ForEach(viewModel.studios) { studio in
                        NavigationLink {
                            StudioDetailView(studio: studio)
                        } label: {
                            StudioCard(studio: studio)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Theme.spacingXLarge)
            }
        }
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay(
                VStack(spacing: Theme.spacingSmall) {
                    ProgressView()
                    Text("Loading studios…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
            )
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
    }

    private var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

private struct StudioCard: View {
    let studio: Studio

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundContent
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(studio.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(studio.city)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 8) {
                    if let rate = studio.hourlyRate {
                        infoTag(text: String(format: "$%.0f/hr", rate))
                    }
                    if let rooms = studio.rooms {
                        infoTag(text: "\(rooms) room\(rooms == 1 ? "" : "s")")
                    }
                    if studio.amenities.isEmpty == false {
                        infoTag(text: "\(studio.amenities.count) amenit\(studio.amenities.count == 1 ? "y" : "ies")")
                    }
                }
            }
            .padding(Theme.spacingLarge)
        }
        .overlay(alignment: .topLeading) {
            if let logoURL = studio.logoImageURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .progressViewStyle(.circular)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        logoFallback
                    @unknown default:
                        logoFallback
                    }
                }
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(Theme.spacingMedium)
            }
        }
        .frame(height: 200)
    }

    private var logoFallback: some View {
        Image(systemName: "music.note.house")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(Theme.primaryColor)
    }

    @ViewBuilder
    private var backgroundContent: some View {
        GeometryReader { proxy in
            ZStack {
                if let cover = studio.coverImageURL {
                    AsyncImage(url: cover) { phase in
                        backgroundImage(for: phase)
                    }
                } else {
                    placeholderBackground
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func backgroundImage(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .empty:
            placeholderBackground
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
                .overlay(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.25), .clear], startPoint: .bottom, endPoint: .top))
        case .failure:
            placeholderBackground
        @unknown default:
            placeholderBackground
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func infoTag(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
    }
}
