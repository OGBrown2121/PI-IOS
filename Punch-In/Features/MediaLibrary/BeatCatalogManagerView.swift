import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BeatCatalogManagerView: View {
    @StateObject var viewModel: BeatCatalogManagerViewModel
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    @State private var importerTarget: AttachmentImporterTarget?
    @State private var isShowingImporter = false

    private let allowedAudioTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let m4a = UTType(filenameExtension: "m4a") {
            types.append(m4a)
        }
        if let caf = UTType(filenameExtension: "caf") {
            types.append(caf)
        }
        if let flac = UTType(filenameExtension: "flac") {
            types.append(flac)
        }
        if let aifc = UTType(filenameExtension: "aifc") {
            types.append(aifc)
        }
        return types
    }()

    private let allowedStemsTypes: [UTType] = {
        var types: [UTType] = [.zip]
        if let zipx = UTType(filenameExtension: "zipx") {
            types.append(zipx)
        }
        return types
    }()

    init(viewModel: BeatCatalogManagerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                headerCard
                existingBeatsSection
                uploadSection
            }
            .padding(Theme.spacingLarge)
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("Beat Catalog")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isUploading)
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.successMessage {
                ToastBanner(message: message, style: .success)
                    .padding(.bottom, 24)
            } else if let error = viewModel.errorMessage {
                ToastBanner(message: error, style: .error)
                    .padding(.bottom, 24)
            }
        }
        .onChange(of: viewModel.isUploading) { uploading in
            if uploading == false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    viewModel.successMessage = nil
                    viewModel.errorMessage = nil
                }
            }
        }
        .onChange(of: viewModel.beats) { beats in
            syncPlayback(with: beats)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: activeImporterContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let target = importerTarget else {
                isShowingImporter = false
                return
            }
            handleImporterResult(result, for: target)
            importerTarget = nil
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Label("Batch Upload", systemImage: "waveform.badge.plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.primaryColor)

            Text("Upload up to three beats at once. Add a preview audio clip, set your licensing terms, and we’ll showcase them on your producer profile.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.isUploading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.uploadProgress ?? 0)
                    Text("Uploading…")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    @ViewBuilder
    private var existingBeatsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Label("Your Beats", systemImage: "music.note.list")
                .font(.headline.weight(.semibold))

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.beats.isEmpty {
                Text("No beats uploaded yet. Start a batch below to publish your first catalog.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Theme.spacingSmall) {
                    ForEach(viewModel.beats) { beat in
                        BeatCatalogManagerRow(beat: beat) {
                            Task { await viewModel.deleteBeat(beat) }
                        }
                    }
                }
            }
        }
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            Label("Add Beats", systemImage: "plus.rectangle.on.rectangle")
                .font(.headline.weight(.semibold))

            VStack(spacing: Theme.spacingMedium) {
                ForEach($viewModel.drafts) { $draft in
                    let draftID = draft.id
                    BeatDraftEditorCard(
                        draft: $draft,
                        isUploading: viewModel.uploadingDraftIDs.contains(draft.id),
                        ownerId: viewModel.currentUser?.id,
                        onRemove: {
                            stopDraftPlaybackIfNeeded(draft)
                            viewModel.removeDraft(draft)
                        },
                        onSelectAudio: {
                            importerTarget = .audio(draftID)
                            isShowingImporter = true
                        },
                        onSelectStems: {
                            importerTarget = .stems(draftID)
                            isShowingImporter = true
                        }
                    )
                }

                if viewModel.canAddDraft {
                    Button {
                        withAnimation {
                            viewModel.addDraft()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add another beat")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.primaryColor.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUploading)
                }

                PrimaryButton(title: viewModel.isUploading ? "Uploading…" : "Upload Beats") {
                    dismissKeyboard()
                    Task { await viewModel.uploadDrafts() }
                }
                .disabled(viewModel.isUploading || viewModel.uploadableDrafts.isEmpty)
            }
        }
    }

    private func syncPlayback(with beats: [ProducerBeat]) {
        guard let current = playbackManager.currentItem else { return }
        let draftPrefix = "beat-draft-"
        if current.id.hasPrefix(draftPrefix) {
            let identifier = String(current.id.dropFirst(draftPrefix.count))
            if let beat = beats.first(where: { $0.id == identifier }),
               let media = beat.previewMediaItem {
                playbackManager.play(media: media)
            }
            return
        }

        if let match = beats.first(where: { "beat-\($0.id)" == current.id }),
           let media = match.previewMediaItem {
            if playbackManager.isPlaying(media: media) {
                playbackManager.play(media: media)
            } else {
                playbackManager.updateMetadata(with: media)
            }
        }
    }

    private func stopDraftPlaybackIfNeeded(_ draft: BeatUploadDraft) {
        guard let ownerId = viewModel.currentUser?.id,
              let media = draft.previewMediaItem(ownerId: ownerId) else { return }
        if playbackManager.currentItem?.id == media.id {
            playbackManager.stop()
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func assignAudio(from url: URL, to draftID: UUID) async {
        let ownerId = viewModel.currentUser?.id
        let previousMedia = ownerId.flatMap { id in
            draft(withID: draftID)?.previewMediaItem(ownerId: id)
        }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let size = try fileSize(at: url)
            if size > viewModel.audioFileSizeLimit {
                updateDraft(id: draftID) {
                    $0.error = "\"\(url.lastPathComponent)\" is too large. Please select an audio file under 100 MB."
                }
                return
            }
            let tempURL = try persistFile(at: url)
            let utType = UTType(filenameExtension: tempURL.pathExtension.lowercased()) ?? .audio
            let contentType = MimeType.from(utType: utType)
            let attachment = BeatAudioAttachment(
                fileURL: tempURL,
                contentType: contentType,
                fileName: tempURL.lastPathComponent
            )
            updateDraft(id: draftID) {
                $0.audio = attachment
                $0.error = nil
            }

            if let previousMedia,
               playbackManager.currentItem?.id == previousMedia.id {
                playbackManager.stop()
            }
        } catch {
            updateDraft(id: draftID) { $0.error = error.localizedDescription }
        }
    }

    private func assignStems(from url: URL, to draftID: UUID) async {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let size = try fileSize(at: url)
            if size > viewModel.stemsFileSizeLimit {
                updateDraft(id: draftID) {
                    $0.error = "\"\(url.lastPathComponent)\" is too large. Keep stems under 400 MB."
                }
                return
            }
            let tempURL = try persistFile(at: url)
            let ext = tempURL.pathExtension.lowercased()
            let utType = UTType(filenameExtension: ext) ?? .zip
            let contentType: String
            if utType == .zip || utType.identifier.contains("zip") {
                contentType = "application/zip"
            } else {
                contentType = "application/octet-stream"
            }

            let attachment = BeatStemsAttachment(
                fileURL: tempURL,
                contentType: contentType,
                fileName: tempURL.lastPathComponent
            )

            updateDraft(id: draftID) {
                $0.stems = attachment
                $0.error = nil
            }
        } catch {
            updateDraft(id: draftID) { $0.error = error.localizedDescription }
        }
    }

    private func updateDraft(id: UUID, _ transform: (inout BeatUploadDraft) -> Void) {
        guard let index = viewModel.drafts.firstIndex(where: { $0.id == id }) else { return }
        var draft = viewModel.drafts[index]
        transform(&draft)
        viewModel.drafts[index] = draft
    }

    private func draft(withID id: UUID) -> BeatUploadDraft? {
        viewModel.drafts.first { $0.id == id }
    }

    private func persistFile(at sourceURL: URL) throws -> URL {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "tmp" : sourceURL.pathExtension)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }
}

private struct BeatCatalogManagerRow: View {
    let beat: ProducerBeat
    let onDelete: () -> Void
    @EnvironmentObject private var playbackManager: MediaPlaybackManager

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            BeatArtworkThumbnail(url: beat.artworkURL)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(beat.title)
                    .font(.headline.weight(.semibold))
                Text("\(beat.license.displayName) • \(beat.formattedPrice)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if beat.detailLine.isEmpty == false {
                    Text(beat.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Theme.primaryColor.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .disabled(mediaItem == nil)

            Button(role: .destructive) {
                stopPlaybackIfNeeded()
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }

    private var mediaItem: ProfileMediaItem? {
        beat.previewMediaItem
    }

    private var isPlaying: Bool {
        guard let mediaItem else { return false }
        return playbackManager.isPlaying(media: mediaItem)
    }

    private func togglePlayback() {
        guard let mediaItem else { return }
        if playbackManager.isPlaying(media: mediaItem) {
            playbackManager.pause()
        } else {
            playbackManager.play(media: mediaItem)
        }
    }

    private func stopPlaybackIfNeeded() {
        guard let mediaItem else { return }
        if playbackManager.currentItem?.id == mediaItem.id {
            playbackManager.stop()
        }
    }
}

private struct BeatDraftEditorCard: View {
    @Binding var draft: BeatUploadDraft
    let isUploading: Bool
    let ownerId: String?
    let onRemove: () -> Void
    let onSelectAudio: () -> Void
    let onSelectStems: () -> Void

    @State private var photoPickerItem: PhotosPickerItem?
    @EnvironmentObject private var playbackManager: MediaPlaybackManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack(alignment: .top) {
                Text(draft.trimmedTitle.isEmpty ? "New Beat" : draft.trimmedTitle)
                    .font(.headline.weight(.semibold))
                Spacer()
                if isUploading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: Theme.spacingSmall) {
                labeledField(title: "Title", systemImage: "textformat") {
                    TextField("Give this beat a title", text: $draft.title)
                        .textInputAutocapitalization(.words)
                }

                labeledField(title: "Summary", systemImage: "text.alignleft") {
                    TextField("Optional description", text: $draft.summary, axis: .vertical)
                        .lineLimit(1...3)
                }

                labeledField(title: "Price (USD)", systemImage: "dollarsign") {
                    TextField("e.g. 49 or 49.99", text: $draft.priceText)
                        .keyboardType(.decimalPad)
                }

                let allowFreeDownloadBinding = Binding<Bool>(
                    get: { draft.allowFreeDownload || draft.isFreePrice },
                    set: { newValue in draft.allowFreeDownload = newValue }
                )

                Toggle("Allow free download", isOn: allowFreeDownloadBinding)
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primaryColor))
                    .disabled(draft.isFreePrice)

                if draft.isFreePrice {
                    Text("Free beats are always downloadable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                labeledField(title: "License", systemImage: "doc.plaintext") {
                    BeatLicensePicker(selection: $draft.license)
                }

                labeledField(title: "Genre", systemImage: "guitars") {
                    Menu {
                        Button {
                            draft.genre = nil
                        } label: {
                            HStack {
                                Text("No genre")
                                if draft.genre == nil {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Divider()

                        ForEach(MusicGenre.allCases) { genre in
                            Button {
                                draft.genre = genre
                            } label: {
                                HStack {
                                    Text(genre.displayName)
                                    if draft.genre == genre {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(draft.genre?.displayName ?? "Select genre")
                                .foregroundStyle(draft.genre == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isUploading)
                }

                Toggle("Includes stems", isOn: $draft.stemsIncluded)
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primaryColor))

                HStack(spacing: Theme.spacingSmall) {
                    labeledField(title: "BPM", systemImage: "metronome") {
                        TextField("Optional", text: $draft.bpmText)
                            .keyboardType(.numberPad)
                    }

                    labeledField(title: "Key", systemImage: "music.note") {
                        TextField("Optional", text: $draft.key)
                            .textInputAutocapitalization(.characters)
                    }
                }

                labeledField(title: "Tags", systemImage: "tag") {
                    TextField("Comma separated (e.g. Trap, R&B)", text: $draft.tagsText)
                        .textInputAutocapitalization(.words)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Preview Audio")
                    .font(.subheadline.weight(.semibold))
                if let audio = draft.audio {
                    AttachmentBadge(
                        icon: "waveform",
                        title: audio.fileName,
                        subtitle: audio.contentType.uppercased()
                    ) {
                        draft.audio = nil
                    }
                }

                Button {
                    onSelectAudio()
                } label: {
                    attachmentButtonLabel(
                        title: draft.audio == nil ? "Select audio file" : "Replace audio",
                        systemImage: "waveform.badge.plus"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                if draft.audio != nil, let ownerId {
                    Button {
                        toggleDraftPlayback(ownerId: ownerId)
                    } label: {
                        attachmentButtonLabel(
                            title: isDraftPlaying(ownerId: ownerId) ? "Pause preview" : "Preview in player",
                            systemImage: isDraftPlaying(ownerId: ownerId) ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                }

                if draft.stemsIncluded {
                    Divider()

                    Text("Stems ZIP")
                        .font(.subheadline.weight(.semibold))

                    if let stems = draft.stems {
                        AttachmentBadge(
                            icon: "square.and.arrow.down.on.square",
                            title: stems.fileName,
                            subtitle: stems.contentType.uppercased()
                        ) {
                            draft.stems = nil
                        }
                    }

                    Button {
                        onSelectStems()
                    } label: {
                        attachmentButtonLabel(
                            title: draft.stems == nil ? "Select stems ZIP" : "Replace stems ZIP",
                            systemImage: "archivebox.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text("Artwork (optional)")
                    .font(.subheadline.weight(.semibold))

                if let artwork = draft.artwork, let image = UIImage(data: artwork.data) {
                    AttachmentImagePreview(image: Image(uiImage: image)) {
                        draft.artwork = nil
                    }
                }

                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    attachmentButtonLabel(
                        title: draft.artwork == nil ? "Add artwork" : "Replace artwork",
                        systemImage: "photo.badge.plus"
                    )
                }
                .disabled(isUploading)
            }

            if let error = draft.error, error.isEmpty == false {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
        )
        .task(id: photoPickerItem) {
            await loadArtwork()
        }
        .onChange(of: draft.priceText) { _ in
            if draft.isFreePrice {
                draft.allowFreeDownload = true
            }
        }
    }

    private func labeledField<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.highlightedCardBackground)
                )
        }
    }

    private func loadArtwork() async {
        guard let item = photoPickerItem else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let image = UIImage(data: data)
                let processedData: Data
                let contentType: String
                if let pngData = image?.pngData(), data.isPNG {
                    processedData = pngData
                    contentType = "image/png"
                } else if let jpegData = image?.jpegData(compressionQuality: 0.82) {
                    processedData = jpegData
                    contentType = "image/jpeg"
                } else {
                    processedData = data
                    contentType = "image/jpeg"
                }
                draft.artwork = BeatArtworkAttachment(data: processedData, contentType: contentType)
                draft.error = nil
            }
        } catch {
            draft.error = error.localizedDescription
        }
        photoPickerItem = nil
    }

    private func attachmentButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.highlightedCardBackground)
        )
    }

    private func isDraftPlaying(ownerId: String) -> Bool {
        guard let media = draft.previewMediaItem(ownerId: ownerId) else { return false }
        return playbackManager.isPlaying(media: media)
    }

    private func toggleDraftPlayback(ownerId: String) {
        guard let media = draft.previewMediaItem(ownerId: ownerId) else { return }
        if playbackManager.isPlaying(media: media) {
            playbackManager.pause()
        } else {
            playbackManager.play(media: media)
        }
    }
}

private struct AttachmentBadge: View {
    let icon: String
    let title: String
    let subtitle: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.primaryColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.highlightedCardBackground)
        )
    }
}

private struct AttachmentImagePreview: View {
    let image: Image
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            image
                .resizable()
                .scaledToFill()
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.primaryColor.opacity(0.1), lineWidth: 1)
                )

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.4))
            }
            .offset(x: -8, y: 8)
        }
    }
}

private struct ToastBanner: View {
    enum Style {
        case success
        case error

        var background: Color {
            switch self {
            case .success:
                return Theme.primaryColor
            case .error:
                return Color.red
            }
        }
    }

    let message: String
    let style: Style

    var body: some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(style.background.opacity(0.92))
            )
    }
}

private struct BeatLicensePicker: View {
    @Binding var selection: ProducerBeat.License

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingSmall) {
                ForEach(ProducerBeat.License.allCases) { license in
                    let isSelected = selection == license
                    Button {
                        selection = license
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: license.iconName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(license.displayName)
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSelected ? Theme.primaryColor : Theme.highlightedCardBackground)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.primaryColor.opacity(isSelected ? 0.0 : 0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private extension Data {
    var isPNG: Bool {
        starts(with: [0x89, 0x50, 0x4E, 0x47])
    }
}

private extension BeatCatalogManagerView {
    enum AttachmentImporterTarget {
        case audio(UUID)
        case stems(UUID)

        var draftID: UUID {
            switch self {
            case let .audio(id), let .stems(id):
                return id
            }
        }
    }

    var activeImporterContentTypes: [UTType] {
        guard let target = importerTarget else {
            return allowedAudioTypes
        }
        switch target {
        case .audio:
            return allowedAudioTypes
        case .stems:
            return allowedStemsTypes
        }
    }

    func handleImporterResult(_ result: Result<[URL], Error>, for target: AttachmentImporterTarget) {
        switch (target, result) {
        case let (.audio(draftID), .success(urls)):
            guard let url = urls.first else { return }
            Task { await assignAudio(from: url, to: draftID) }
        case let (.stems(draftID), .success(urls)):
            guard let url = urls.first else { return }
            Task { await assignStems(from: url, to: draftID) }
        case let (.audio(draftID), .failure(error)),
             let (.stems(draftID), .failure(error)):
            guard isCancellationError(error) == false else { break }
            updateDraft(id: draftID) { $0.error = error.localizedDescription }
        }
    }

    func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

#Preview("Beat Catalog Manager") {
    let di = DIContainer.makeMock()
    let viewModel = BeatCatalogManagerViewModel(
        firestore: di.firestoreService,
        storage: di.storageService,
        currentUserProvider: { UserProfile.previewProducer }
    )

    if let firestore = di.firestoreService as? MockFirestoreService {
        firestore.seedUserProfile(.previewProducer)
        firestore.seedBeatCatalog(
            for: UserProfile.previewProducer.id,
            beats: [
                ProducerBeat.mock,
                ProducerBeat.exclusiveMock
            ]
        )
    }

    return NavigationStack {
        BeatCatalogManagerView(viewModel: viewModel)
    }
    .environment(\.di, di)
    .environmentObject(MediaPlaybackManager(firestoreService: di.firestoreService))
}
