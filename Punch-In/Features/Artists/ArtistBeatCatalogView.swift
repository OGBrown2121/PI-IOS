import SwiftUI

struct ArtistBeatCatalogView: View {
    let profile: UserProfile
    @Binding var beats: [ProducerBeat]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    @Binding var pendingDownloadIds: Set<String>
    @Binding var downloadErrorMessage: String?
    let reloadAction: () async -> Void
    let onRequestDownload: (ProducerBeat) async -> Bool
    @State private var selectedGenre: MusicGenre?
    @Environment(\.openURL) private var openURL
    @State private var lastRequestedBeatId: String?
    @State private var requestConfirmationMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                header
                catalogBody
            }
            .padding(Theme.spacingLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("Beat Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await reloadAction() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh beat catalog")
                }
            }
        }
        .task {
            await reloadAction()
        }
        .onChange(of: beats) { _ in
            guard let selectedGenre else { return }
            if availableGenres.contains(selectedGenre) == false {
                self.selectedGenre = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Browse preview clips, licensing details, and request downloads from this producer.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if availableGenres.isEmpty == false {
                Menu {
                    Button {
                        selectedGenre = nil
                    } label: {
                        HStack {
                            Text("All genres")
                            if selectedGenre == nil {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(availableGenres) { genre in
                        Button {
                            selectedGenre = genre
                        } label: {
                            HStack {
                                Text(genre.displayName)
                                if selectedGenre == genre {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(selectedGenre?.displayName ?? "All genres")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, Theme.spacingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.highlightedCardBackground)
                    )
                }
                .menuStyle(.automatic)
                .accessibilityLabel("Filter catalog by genre")
            }
        }
    }

    @ViewBuilder
    private var catalogBody: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            if isLoading {
                ProgressView("Loading catalog…")
                    .progressViewStyle(.circular)
            } else if let message = errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if beats.isEmpty {
                Text("No beats listed yet. Producers can add beats from their catalog manager.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if let message = requestConfirmationMessage, message.isEmpty == false {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.primaryColor)
                }

                if let downloadMessage = downloadErrorMessage, downloadMessage.isEmpty == false {
                    Text(downloadMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red.opacity(0.85))
                }

                let catalog = filteredBeats

                if catalog.isEmpty {
                    Text("No beats match this genre yet. Try a different filter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.spacingMedium) {
                        ForEach(Array(catalog.enumerated()), id: \.element.id) { entry in
                            let beat = entry.element
                            ArtistBeatCatalogRow(
                                beat: beat,
                                isPending: pendingDownloadIds.contains(beat.id),
                                didRequestSuccess: lastRequestedBeatId == beat.id,
                                onRequestDownload: {
                                    Task {
                                        let success = await onRequestDownload(beat)
                                        if success {
                                            await MainActor.run {
                                                lastRequestedBeatId = beat.id
                                                requestConfirmationMessage = "Request sent! We'll notify you once the producer shares the files."
                                                downloadErrorMessage = nil
                                            }
                                        }
                                    }
                                },
                                onFreeDownload: (beat.isFreeDownloadEnabled && beat.stemsZipURL != nil) ? {
                                    handleFreeDownload(for: beat)
                                } : nil
                            )

                            if entry.offset < catalog.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
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
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private var availableGenres: [MusicGenre] {
        let unique = Set(beats.compactMap(\.primaryGenre))
        return unique.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var filteredBeats: [ProducerBeat] {
        guard let selectedGenre else { return beats }
        return beats.filter { $0.primaryGenre == selectedGenre }
    }

    private func handleFreeDownload(for beat: ProducerBeat) {
        let candidateURL = beat.stemsZipURL ?? beat.previewURL
        guard let downloadURL = candidateURL else {
            downloadErrorMessage = "Producer hasn’t uploaded downloadable files yet."
            return
        }
        downloadErrorMessage = nil
        openURL(downloadURL)
    }
}

private struct ArtistBeatCatalogRow: View {
    let beat: ProducerBeat
    let isPending: Bool
    let didRequestSuccess: Bool
    let onRequestDownload: () -> Void
    let onFreeDownload: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium * 0.75) {
            HStack(alignment: .top, spacing: Theme.spacingMedium) {
                BeatArtworkThumbnail(url: beat.artworkURL, cornerRadius: 18)
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 6) {
                    Text(beat.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if beat.summary.isEmpty == false {
                        Text(beat.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if beat.detailLine.isEmpty == false {
                        Text(beat.detailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let genreName = beat.genreDisplayName {
                        Label(genreName, systemImage: "guitars")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.primaryColor.opacity(0.85))
                    }

            if beat.displayTags.isEmpty == false {
                Text(beat.displayTags.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor.opacity(0.8))
            }

                    if beat.isFreeDownloadEnabled {
                        Label("Free download", systemImage: "arrow.down.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.green.opacity(0.8))
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(beat.formattedPrice)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)

                    Label(beat.license.displayName, systemImage: beat.license.iconName)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.primaryColor.opacity(0.1))
                        .foregroundStyle(Theme.primaryColor)
                        .clipShape(Capsule())
                }
            }

            if let previewURL = beat.previewURL {
                InlineAudioPlayerView(url: previewURL)
            } else {
                Text("Preview unavailable. Contact the producer to request a sample.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if beat.isFreeDownloadEnabled && onFreeDownload == nil {
                Text("Download link isn’t available yet. Try requesting access from the producer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let onFreeDownload {
                Button(action: onFreeDownload) {
                    HStack(spacing: 10) {
                        Text("Download")
                            .font(.subheadline.weight(.semibold))

                        Image(systemName: "arrow.down.circle")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.primaryColor)
                )
                .foregroundStyle(Color.white)
            } else {
                Button(action: onRequestDownload) {
                    HStack(spacing: 10) {
                        if isPending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }

                        Text(isPending ? "Sending…" : "Request Download")
                            .font(.subheadline.weight(.semibold))

                        if isPending == false {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.subheadline.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isPending ? Theme.primaryColor.opacity(0.6) : Theme.primaryColor)
                )
                .foregroundStyle(Color.white)
                .disabled(isPending)

                if didRequestSuccess {
                    Text("Request sent! Check your notifications for updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}
