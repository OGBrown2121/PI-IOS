import SwiftUI

struct EngineerRequestsView: View {
    let studio: Studio

    @StateObject private var viewModel: EngineerRequestsViewModel

    init(studio: Studio, firestoreService: any FirestoreService) {
        self.studio = studio
        _viewModel = StateObject(
            wrappedValue: EngineerRequestsViewModel(studioId: studio.id, firestoreService: firestoreService)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                headerSection
                pendingSection
                processedSection
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
        }
        .background(Theme.appBackground)
        .navigationTitle("Engineer Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadRequests() }
        .refreshable { await viewModel.loadRequests() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(studio.name)
                .font(.title3.weight(.semibold))
            Text("Manage engineers who want to work at your studio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.top, Theme.spacingSmall)
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
                .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack {
                Label("Pending", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                Spacer()
                if !viewModel.pending.isEmpty {
                    Text("\(viewModel.pending.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isLoading && viewModel.pending.isEmpty && viewModel.processed.isEmpty {
                HStack(spacing: Theme.spacingSmall) {
                    ProgressView()
                    Text("Loading requests…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.pending.isEmpty {
                Text("No pending requests right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Theme.spacingMedium) {
                    ForEach(viewModel.pending) { entry in
                        EngineerRequestCard(
                            entry: entry,
                            isProcessing: viewModel.isProcessing(entry)
                        ) {
                            Task { await viewModel.accept(entry) }
                        } denyAction: {
                            Task { await viewModel.deny(entry) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var processedSection: some View {
        if !viewModel.processed.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                Label("Recently processed", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                VStack(spacing: Theme.spacingMedium) {
                    ForEach(viewModel.processed) { entry in
                        EngineerHistoryCard(entry: entry)
                    }
                }
            }
        }
    }
}

private struct EngineerRequestCard: View {
    let entry: EngineerRequestsViewModel.RequestEntry
    let isProcessing: Bool
    let acceptAction: () -> Void
    let denyAction: () -> Void

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var profile: UserProfile? { entry.profile }

    private var displayName: String {
        profile?.displayName.isEmpty == false ? (profile?.displayName ?? "") : (profile?.username ?? "Engineer")
    }

    private var subtitle: String {
        if let profile, !profile.profileDetails.fieldOne.isEmpty {
            return profile.profileDetails.fieldOne
        }
        if let profile, !profile.profileDetails.fieldTwo.isEmpty {
            return profile.profileDetails.fieldTwo
        }
        return "Request sent \(relativeFormatter.localizedString(for: entry.request.createdAt, relativeTo: Date()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            NavigationLink {
                EngineerDetailView(engineerId: entry.request.engineerId, profile: profile)
            } label: {
                HStack(spacing: Theme.spacingMedium) {
                    AvatarView(profile: profile, fallback: displayName)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName.isEmpty ? "Engineer" : displayName)
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: Theme.spacingMedium) {
                Button(action: denyAction) {
                    Label("Deny", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.8))
                .disabled(isProcessing)

                Button(action: acceptAction) {
                    Label("Accept", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryColor)
                .disabled(isProcessing)
            }

            if isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct EngineerHistoryCard: View {
    let entry: EngineerRequestsViewModel.RequestEntry

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var profile: UserProfile? { entry.profile }

    private var displayName: String {
        profile?.displayName.isEmpty == false ? (profile?.displayName ?? "") : (profile?.username ?? "Engineer")
    }

    private var statusColor: Color {
        switch entry.request.status {
        case .accepted:
            return .green
        case .denied:
            return .red
        case .pending:
            return Theme.primaryColor
        }
    }

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            AvatarView(profile: profile, fallback: displayName)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.isEmpty ? "Engineer" : displayName)
                    .font(.subheadline.weight(.semibold))

                Text("\(entry.request.status.displayName) • \(relativeFormatter.localizedString(for: entry.request.updatedAt, relativeTo: Date()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(statusColor.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: entry.request.status == .accepted ? "checkmark" : "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(statusColor)
                )
        }
        .padding(Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.elevatedCardBackground)
        )
    }
}

private struct AvatarView: View {
    let profile: UserProfile?
    let fallback: String

    private var initials: String {
        let name = profile?.displayName ?? fallback
        let components = name.split(separator: " ")
        if components.isEmpty {
            return String(name.prefix(2)).uppercased()
        }
        let first = components.first.map { String($0.prefix(1)).uppercased() } ?? ""
        let second = components.dropFirst().first.map { String($0.prefix(1)).uppercased() } ?? ""
        let combined = (first + second)
        return combined.isEmpty ? String(name.prefix(2)).uppercased() : combined
    }

    var body: some View {
        if let url = profile?.profileImageURL {
            AsyncImage(url: url) { phase in
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
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Theme.primaryColor.opacity(0.15))
            .frame(width: 54, height: 54)
            .overlay(
                Text(initials)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor)
            )
    }
}

#Preview("Engineer Requests") {
    NavigationStack {
        EngineerRequestsView(studio: .mock(), firestoreService: MockFirestoreService())
    }
}
