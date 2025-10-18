import SwiftUI

struct DriveDownloadRequestsCard: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    let profile: UserProfile

    @State private var requests: [BeatDownloadRequest] = []
    @State private var producerProfiles: [String: UserProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var deletingRequestIds: Set<String> = []

    var body: some View {
        Group {
            if shouldShowCard {
                VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                    header
                    content
                }
                .padding(Theme.spacingLarge)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.cardBackground.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.primaryColor.opacity(0.12), lineWidth: 1)
                )
                .task {
                    await loadRequests(force: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.spacingSmall) {
            Label("Downloads", systemImage: "arrow.down.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if isLoading && requests.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Button {
                    Task { await loadRequests(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh downloads")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && requests.isEmpty {
            ProgressView("Checking downloads…")
                .progressViewStyle(.circular)
        } else if let errorMessage, requests.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if requests.isEmpty {
            Text("Request downloads from producers and you'll see them here once they're approved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: Theme.spacingSmall) {
                ForEach(requests) { request in
                    requestRow(for: request)
                }
            }
        }
    }

    private func requestRow(for request: BeatDownloadRequest) -> some View {
        let isDeleting = deletingRequestIds.contains(request.id)

        return VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(beatTitle(for: request))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(request.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("from \(producerDisplayName(for: request))")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch request.status {
            case .fulfilled:
                if let url = request.downloadURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.headline)
                            Text("Download files")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.primaryColor)
                    )
                    .foregroundStyle(.white)
                    .overlay {
                        if isDeleting {
                            ZStack {
                                Color.black.opacity(0.35)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .disabled(isDeleting)
                } else {
                    Text("Files are ready, but the download link is missing.")
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.75))
                }
            case .pending:
                Text("Waiting on the producer to share files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .rejected:
                Text("The producer declined this request.")
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.75))
            }

            Button(role: .destructive) {
                Task { await deleteRequest(request) }
            } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.red.opacity(0.9))
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.caption.weight(.semibold))
                    }
                    Text(isDeleting ? "Removing…" : "Remove request")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
            .foregroundStyle(Color.red.opacity(0.9))
            .disabled(isDeleting)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
        .swipeActions {
            Button(role: .destructive) {
                Task { await deleteRequest(request) }
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Label("Remove", systemImage: "trash")
                }
            }
            .disabled(isDeleting)
        }
    }

    private var shouldShowCard: Bool {
        appState.currentUser?.id == profile.id
    }

    private func beatTitle(for request: BeatDownloadRequest) -> String {
        if let storedTitle = request.beatTitle?.trimmingCharacters(in: .whitespacesAndNewlines), storedTitle.isEmpty == false {
            return storedTitle
        }
        return "Untitled Beat"
    }

    private func producerDisplayName(for request: BeatDownloadRequest) -> String {
        if let profile = producerProfiles[request.producerId] {
            let trimmedDisplay = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDisplay.isEmpty == false {
                return trimmedDisplay
            }

            let trimmedUsername = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUsername.isEmpty == false {
                return "@\(trimmedUsername)"
            }
        }
        return "the producer"
    }

    @MainActor
    private func loadRequests(force: Bool) async {
        guard shouldShowCard else { return }
        guard force || hasLoaded == false else { return }
        guard isLoading == false else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await di.firestoreService.fetchDriveDownloadRequests(for: profile.id, status: nil)
            requests = fetched
            hasLoaded = true
            errorMessage = nil

            let producerIds = Set(fetched.map { $0.producerId })
            if producerIds.isEmpty {
                producerProfiles = [:]
            } else if let profiles = try? await di.firestoreService.fetchUserProfiles(for: Array(producerIds)) {
                producerProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            } else {
                producerProfiles = [:]
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if hasLoaded == false {
                requests = []
                producerProfiles = [:]
            }
        }
    }

    @MainActor
    private func deleteRequest(_ request: BeatDownloadRequest) async {
        guard shouldShowCard else { return }
        guard deletingRequestIds.contains(request.id) == false else { return }
        deletingRequestIds.insert(request.id)
        defer { deletingRequestIds.remove(request.id) }

        do {
            try await di.firestoreService.deleteDriveDownloadRequest(requestId: request.id, requesterId: profile.id)
            withAnimation {
                requests.removeAll { $0.id == request.id }
            }
            if requests.isEmpty {
                errorMessage = nil
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
