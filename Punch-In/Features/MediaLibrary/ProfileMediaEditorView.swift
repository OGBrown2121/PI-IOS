import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct PickedVideo: Transferable {
    let url: URL
    let contentType: UTType

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { exported in
            SentTransferredFile(exported.url)
        } importing: { received in
            try Self.makeVideo(from: received)
        }
        FileRepresentation(contentType: .video) { exported in
            SentTransferredFile(exported.url)
        } importing: { received in
            try Self.makeVideo(from: received)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }

    private static func makeVideo(from received: ReceivedTransferredFile) throws -> PickedVideo {
        let originalExtension = received.file.pathExtension
        let fileExtension = originalExtension.isEmpty ? "mov" : originalExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: received.file, to: destinationURL)
        let contentType = UTType(filenameExtension: fileExtension) ?? .movie
        return PickedVideo(url: destinationURL, contentType: contentType)
    }
}

struct ProfileMediaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadManager: ProfileMediaUploadManager
    @State private var workingDraft: ProfileMediaDraft
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var coverArtPickerItem: PhotosPickerItem?
    @State private var isImportingFile = false
    @State private var isPresentingCollaboratorPicker = false
    @State private var localErrorMessage: String?
    @State private var pendingCoverArt: PendingCoverArt?
    @State private var isShowingCoverCropper = false

    let capabilities: ProfileMediaCapabilities
    let onSave: (ProfileMediaDraft) async -> Bool
    let onDelete: ((ProfileMediaItem) async -> Void)?
    let collaboratorSearchFactory: () -> ProfileMediaCollaboratorSearchViewModel
    let isPinLimitReached: Bool
    private let maxFileSizeBytes = ProfileMediaConstraints.maxFileSizeBytes

    init(
        draft: ProfileMediaDraft,
        capabilities: ProfileMediaCapabilities,
        onSave: @escaping (ProfileMediaDraft) async -> Bool,
        onDelete: ((ProfileMediaItem) async -> Void)? = nil,
        collaboratorSearchFactory: @escaping () -> ProfileMediaCollaboratorSearchViewModel,
        isPinLimitReached: Bool
    ) {
        _workingDraft = State(initialValue: draft)
        self.capabilities = capabilities
        self.onSave = onSave
        self.onDelete = onDelete
        self.collaboratorSearchFactory = collaboratorSearchFactory
        self.isPinLimitReached = isPinLimitReached
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLarge) {
                ProfileMediaEditorSection(
                    title: "Details",
                    subtitle: "Set the essentials so listeners know what they're about to play.",
                    icon: "square.and.pencil"
                ) {
                    VStack(spacing: Theme.spacingMedium) {
                        VStack(alignment: .leading, spacing: 8) {
                            ProfileMediaEditorLabel(title: "Title", systemImage: "textformat")
                            ProfileMediaEditorControlSurface {
                                TextField("Add a title", text: $workingDraft.title)
                                    .textFieldStyle(.plain)
                                    .font(.callout.weight(.semibold))
                                    .textInputAutocapitalization(.words)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ProfileMediaEditorLabel(title: "Caption", systemImage: "text.alignleft")
                            ProfileMediaEditorControlSurface {
                                TextField("Share context or lyrics", text: $workingDraft.caption, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                    .lineLimit(2...4)
                                    .multilineTextAlignment(.leading)
                                    .textInputAutocapitalization(.sentences)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ProfileMediaEditorLabel(title: "Category", systemImage: "tag")
                            Menu {
                                ForEach(capabilities.defaultCategories, id: \.self) { category in
                                    categoryMenuButton(for: category)
                                }
                                if otherCategories.isEmpty == false {
                                    Divider()
                                    ForEach(otherCategories, id: \.self) { category in
                                        categoryMenuButton(for: category)
                                    }
                                }
                            } label: {
                                ProfileMediaEditorControlSurface {
                                    ProfileMediaEditorMenuLabel(
                                        title: workingDraft.category.displayTitle,
                                        icon: "tag"
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ProfileMediaEditorLabel(title: "Format", systemImage: "waveform")
                            Menu {
                                ForEach(capabilities.allowedFormats, id: \.self) { format in
                                    Button {
                                        workingDraft.format = format
                                    } label: {
                                        ProfileMediaEditorMenuOption(
                                            title: formatLabel(for: format),
                                            systemImage: format.iconName,
                                            isSelected: workingDraft.format == format
                                        )
                                    }
                                }
                            } label: {
                                ProfileMediaEditorControlSurface {
                                    ProfileMediaEditorMenuLabel(
                                        title: formatLabel(for: workingDraft.format),
                                        icon: workingDraft.format.iconName
                                    )
                                }
                            }
                        }
                    }
                }

                ProfileMediaEditorSection(
                    title: "File",
                    subtitle: "Attach the media you’re ready to share with followers.",
                    icon: "paperclip"
                ) {
                    VStack(spacing: Theme.spacingMedium) {
                        ProfileMediaEditorControlSurface {
                            AttachmentPreview(draft: workingDraft)
                        }

                        if showMediaLibraryPicker {
                            PhotosPicker(
                                selection: $photoPickerItem,
                                matching: mediaLibraryFilter
                            ) {
                                ProfileMediaEditorControlSurface(
                                    background: Theme.highlightedCardBackground,
                                    overlayColor: Theme.primaryColor.opacity(0.18)
                                ) {
                                    ProfileMediaEditorActionLabel(
                                        icon: mediaPickerIcon,
                                        title: mediaPickerTitle
                                    )
                                }
                            }
                        }

                        if showAudioImporter {
                            Button {
                                isImportingFile = true
                            } label: {
                                ProfileMediaEditorControlSurface(
                                    background: Theme.highlightedCardBackground,
                                    overlayColor: Theme.primaryColor.opacity(0.18)
                                ) {
                                    ProfileMediaEditorActionLabel(
                                        icon: "waveform.badge.plus",
                                        title: "Import Audio or Document"
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if uploadManager.activeUpload != nil && workingDraft.requiresAssetUpload {
                            ProfileMediaEditorNote(
                                text: "Finish the current upload before starting another."
                            )
                        }
                    }
                }

                if workingDraft.format == .audio {
                    ProfileMediaEditorSection(
                        title: "Artwork",
                        subtitle: "Cover art helps your audio stand out in the feed and mini player.",
                        icon: "music.note"
                    ) {
                        VStack(spacing: Theme.spacingMedium) {
                            ProfileMediaEditorControlSurface {
                                HStack(alignment: .top, spacing: 12) {
                                    coverArtPreview
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Display artwork")
                                            .font(.subheadline.weight(.semibold))
                                        Text("This image appears on your media detail page and mini player.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }

                            PhotosPicker(selection: $coverArtPickerItem, matching: .images) {
                                ProfileMediaEditorControlSurface(
                                    background: Theme.highlightedCardBackground,
                                    overlayColor: Theme.primaryColor.opacity(0.18)
                                ) {
                                    ProfileMediaEditorActionLabel(icon: "photo", title: "Select Cover Art")
                                }
                            }

                            if workingDraft.thumbnailData != nil || workingDraft.remoteThumbnailURL != nil {
                                Button(role: .destructive) {
                                    workingDraft.thumbnailData = nil
                                    workingDraft.thumbnailContentType = nil
                                    workingDraft.remoteThumbnailURL = nil
                                } label: {
                                    ProfileMediaEditorControlSurface(
                                        background: Color.red.opacity(0.12),
                                        overlayColor: Color.red.opacity(0.2)
                                    ) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(Color.red)
                                            Text("Remove Cover Art")
                                                .font(.callout.weight(.semibold))
                                                .foregroundStyle(Color.red)
                                            Spacer()
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                ProfileMediaEditorSection(
                    title: "Collaborators",
                    subtitle: "Tag collaborators to spotlight who helped bring this piece to life.",
                    icon: "person.2.fill"
                ) {
                    VStack(spacing: Theme.spacingMedium) {
                        if workingDraft.collaborators.isEmpty {
                            ProfileMediaEditorNote(
                                text: "Tag collaborators to spotlight artists, engineers, or studios involved."
                            )
                        } else {
                            ProfileMediaEditorNote(
                                text: "Assign each collaborator’s contribution so listeners know who did what."
                            )
                            ForEach(workingDraft.collaborators) { collaborator in
                                ProfileMediaEditorControlSurface {
                                    collaboratorRow(for: collaborator)
                                }
                            }
                        }

                        Button {
                            isPresentingCollaboratorPicker = true
                        } label: {
                            ProfileMediaEditorControlSurface(
                                background: Theme.highlightedCardBackground,
                                overlayColor: Theme.primaryColor.opacity(0.18)
                            ) {
                                ProfileMediaEditorActionLabel(icon: "person.crop.circle.badge.plus", title: "Add collaborator")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                ProfileMediaEditorSection(
                    title: "Visibility",
                    subtitle: "Control how this upload appears across Punch In.",
                    icon: "sparkles"
                ) {
                    VStack(spacing: Theme.spacingMedium) {
                        ProfileMediaEditorNote(
                            text: "Uploads automatically appear on your profile."
                        )

                        ProfileMediaEditorControlSurface {
                            Toggle(isOn: $workingDraft.isPinned) {
                                Label("Pin to profile", systemImage: "star.fill")
                                    .font(.callout.weight(.semibold))
                            }
                            .disabled(pinToggleDisabled)
                            .tint(Theme.primaryColor)
                        }

                        if let reason = pinDisabledReason {
                            ProfileMediaEditorNote(text: reason)
                        }

                        if workingDraft.format == .audio {
                            ProfileMediaEditorControlSurface {
                                Toggle(isOn: $workingDraft.isRadioEligible) {
                                    Label("Feature on Local Artist Radio", systemImage: "dot.radiowaves.left.and.right")
                                        .font(.callout.weight(.semibold))
                                }
                                .tint(Theme.primaryColor)
                            }

                            ProfileMediaEditorNote(
                                text: "When enabled, this track can be surfaced in the in-app radio for listeners across Punch In."
                            )

                            Menu {
                                Button {
                                    workingDraft.primaryGenre = nil
                                } label: {
                                    ProfileMediaEditorMenuOption(
                                        title: "Not set",
                                        systemImage: nil,
                                        isSelected: workingDraft.primaryGenre == nil
                                    )
                                }
                                ForEach(MusicGenre.allCases) { genre in
                                    Button {
                                        workingDraft.primaryGenre = genre
                                    } label: {
                                        ProfileMediaEditorMenuOption(
                                            title: genre.displayName,
                                            systemImage: nil,
                                            isSelected: workingDraft.primaryGenre == genre
                                        )
                                    }
                                }
                            } label: {
                                ProfileMediaEditorControlSurface {
                                    ProfileMediaEditorMenuLabel(
                                        title: workingDraft.primaryGenre?.displayName ?? "Select genre",
                                        icon: "music.quarternote.3",
                                        isPlaceholder: workingDraft.primaryGenre == nil
                                    )
                                }
                            }

                            Menu {
                                Button {
                                    workingDraft.originState = nil
                                } label: {
                                    ProfileMediaEditorMenuOption(
                                        title: "Nationwide",
                                        systemImage: nil,
                                        isSelected: workingDraft.originState == nil
                                    )
                                }
                                ForEach(USState.allCases) { state in
                                    Button {
                                        workingDraft.originState = state
                                    } label: {
                                        ProfileMediaEditorMenuOption(
                                            title: state.displayName,
                                            systemImage: nil,
                                            isSelected: workingDraft.originState == state
                                        )
                                    }
                                }
                            } label: {
                                ProfileMediaEditorControlSurface {
                                    ProfileMediaEditorMenuLabel(
                                        title: workingDraft.originState?.displayName ?? "Nationwide",
                                        icon: "mappin.and.ellipse"
                                    )
                                }
                            }

                            ProfileMediaEditorNote(
                                text: "These fields help listeners discover tracks by genre and region inside Local Artist Radio."
                            )
                        }
                    }
                }

                if let message = localErrorMessage {
                    ProfileMediaEditorControlSurface(
                        background: Color.red.opacity(0.12),
                        overlayColor: Color.red.opacity(0.2)
                    ) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.red)
                            Text(message)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.red)
                            Spacer(minLength: 0)
                        }
                    }
                }

                if workingDraft.mediaItem != nil, let onDelete {
                    Button(role: .destructive) {
                        Task { await onDeleteCall(onDelete) }
                    } label: {
                        ProfileMediaEditorControlSurface(
                            background: Color.red.opacity(0.12),
                            overlayColor: Color.red.opacity(0.2)
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Delete media")
                                    .font(.callout.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingLarge)
        }
        .scrollIndicators(.hidden)
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle(workingDraft.mediaItem == nil ? "Add media" : "Edit media")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(saveButtonTitle) {
                    Task { await handleSave() }
                }
                .disabled(
                    workingDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (uploadManager.activeUpload != nil && workingDraft.requiresAssetUpload)
                )
            }
        }
        .task(id: photoPickerItem) {
            await handlePhotoPickerChange()
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: importableAudioTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        .task(id: coverArtPickerItem) {
            await loadCoverArt()
        }
        .sheet(isPresented: $isPresentingCollaboratorPicker) {
            NavigationStack {
                ProfileMediaCollaboratorPickerView(
                    searchViewModel: collaboratorSearchFactory(),
                    selectedCollaborators: $workingDraft.collaborators
                )
            }
        }
        .sheet(item: $pendingCoverArt) { pending in
            ImageCropperView(
                image: pending.image,
                aspectRatio: 1,
                onCancel: {
                    pendingCoverArt = nil
                },
                onComplete: { cropped in
                    pendingCoverArt = nil
                    assignCroppedCoverArt(image: cropped)
                }
            )
        }
        .onChange(of: workingDraft.format) { newFormat in
            if newFormat != .audio {
                workingDraft.isRadioEligible = false
            }
        }
    }

    private var saveButtonTitle: String {
        if workingDraft.mediaItem == nil || workingDraft.data != nil {
            return "Save & Upload"
        }
        return "Save Changes"
    }

    private var pinToggleDisabled: Bool {
        isPinLimitReached && workingDraft.isPinned == false
    }

    private var pinDisabledReason: String? {
        if isPinLimitReached && workingDraft.isPinned == false {
            return "Pin limit reached (\(capabilities.pinLimit)). Unpin another item to feature this upload."
        }
        return nil
    }

    private var otherCategories: [ProfileMediaCategory] {
        ProfileMediaCategory.allCases.filter { capabilities.defaultCategories.contains($0) == false }
    }

    private var importableAudioTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav]
        if let m4a = UTType(filenameExtension: "m4a") {
            types.append(m4a)
        }
        if let caf = UTType(filenameExtension: "caf") {
            types.append(caf)
        }
        return types
    }

    private var showMediaLibraryPicker: Bool {
        workingDraft.format != .audio
    }

    private var showAudioImporter: Bool {
        workingDraft.format == .audio
    }

    private var mediaLibraryFilter: PHPickerFilter {
        switch workingDraft.format {
        case .photo:
            return .images
        case .video:
            return .videos
        default:
            return .any(of: [.images, .videos])
        }
    }

    private var mediaPickerTitle: String {
        switch workingDraft.format {
        case .photo:
            return "Select Photo"
        case .video:
            return "Select Video"
        case .gallery:
            return "Select Media"
        default:
            return "Select Photo or Video"
        }
    }

    private var mediaPickerIcon: String {
        switch workingDraft.format {
        case .photo:
            return "photo"
        case .video:
            return "play.rectangle"
        case .gallery:
            return "square.grid.2x2"
        default:
            return "photo.on.rectangle"
        }
    }

    private func formatLabel(for format: ProfileMediaFormat) -> String {
        switch format {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .photo:
            return "Photo"
        case .gallery:
            return "Gallery"
        }
    }

    private func categoryMenuButton(for category: ProfileMediaCategory) -> some View {
        Button {
            workingDraft.category = category
        } label: {
            ProfileMediaEditorMenuOption(
                title: category.displayTitle,
                systemImage: nil,
                isSelected: workingDraft.category == category
            )
        }
    }

    @ViewBuilder
    private func collaboratorRow(for collaborator: ProfileMediaCollaborator) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProfileMediaCollaboratorAvatar(collaborator: collaborator)
                Text(collaborator.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    removeCollaborator(collaborator)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let binding = roleBinding(for: collaborator) {
                Menu {
                    Button {
                        binding.wrappedValue = nil
                    } label: {
                        roleMenuRow(
                            title: "No contribution",
                            systemImage: "line.3.horizontal.decrease.circle",
                            isSelected: binding.wrappedValue == nil
                        )
                    }

                    ForEach(ProfileMediaCollaborator.Role.suggested(for: collaborator.kind)) { role in
                        Button {
                            binding.wrappedValue = role
                        } label: {
                            roleMenuRow(
                                title: role.displayTitle,
                                systemImage: role.systemImageName,
                                isSelected: binding.wrappedValue == role
                            )
                        }
                    }
                } label: {
                    Label(
                        collaborator.role?.displayTitle ?? "Set contribution",
                        systemImage: collaborator.role?.systemImageName ?? "tag"
                    )
                    .font(.caption.weight(.semibold))
                }
            }

            Text(collaborator.role.map { "Contribution: \($0.displayTitle)" } ?? "Contribution not set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func removeCollaborator(_ collaborator: ProfileMediaCollaborator) {
        workingDraft.collaborators.removeAll { $0.id == collaborator.id && $0.kind == collaborator.kind }
    }

    private func roleBinding(for collaborator: ProfileMediaCollaborator) -> Binding<ProfileMediaCollaborator.Role?>? {
        guard let index = workingDraft.collaborators.firstIndex(where: { $0.id == collaborator.id && $0.kind == collaborator.kind }) else {
            return nil
        }
        return Binding(
            get: { workingDraft.collaborators[index].role },
            set: { workingDraft.collaborators[index].role = $0 }
        )
    }

    @ViewBuilder
    private func roleMenuRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primaryColor)
            }
        }
    }

    private func handleSave() async {
        localErrorMessage = nil
        let success = await onSave(workingDraft)
        if success {
            dismiss()
        } else if localErrorMessage == nil {
            localErrorMessage = "Unable to save media. Please try again."
        }
    }

    private func onDeleteCall(_ action: @escaping (ProfileMediaItem) async -> Void) async {
        guard let media = workingDraft.mediaItem else { return }
        await action(media)
        dismiss()
    }

    private func handlePhotoPickerChange() async {
        guard let item = photoPickerItem else { return }
        defer { photoPickerItem = nil }
        do {
            if let pickedVideo = try await item.loadTransferable(type: PickedVideo.self) {
                defer { pickedVideo.cleanup() }
                let data = try Data(contentsOf: pickedVideo.url)
                try validateFileSize(data.count)
                let duration = try await mediaDuration(for: pickedVideo.url)
                let thumbnail = try await generateThumbnail(for: pickedVideo.url)
                let mimeType = pickedVideo.contentType.preferredMIMEType
                    ?? MimeType.fromFileExtension(pickedVideo.url.pathExtension)
                    ?? "video/mp4"

                workingDraft.assignAsset(
                    data: data,
                    contentType: mimeType,
                    format: .video,
                    thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                    thumbnailContentType: thumbnail == nil ? nil : "image/jpeg",
                    duration: duration
                )
                return
            }

            if let imageData = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: imageData),
               let jpegData = image.jpegData(compressionQuality: 0.88) {
                try validateFileSize(jpegData.count)
                workingDraft.assignAsset(
                    data: jpegData,
                    contentType: "image/jpeg",
                    format: .photo
                )
                return
            }

            if let videoURL = try await item.loadTransferable(type: URL.self) {
                let data = try Data(contentsOf: videoURL)
                try validateFileSize(data.count)
                let duration = try await mediaDuration(for: videoURL)
                let thumbnail = try await generateThumbnail(for: videoURL)
                let mime = MimeType.fromFileExtension(videoURL.pathExtension) ?? "video/mp4"
                workingDraft.assignAsset(
                    data: data,
                    contentType: mime,
                    format: .video,
                    thumbnailData: thumbnail?.jpegData(compressionQuality: 0.7),
                    thumbnailContentType: thumbnail == nil ? nil : "image/jpeg",
                    duration: duration
                )
                return
            }

            localErrorMessage = "We couldn’t load that selection. Try a different file."
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func format(for utType: UTType) -> ProfileMediaFormat {
        if utType.conforms(to: .image) {
            return .photo
        } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return .video
        } else if utType.conforms(to: .audio) {
            return .audio
        }
        return .gallery
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task {
                await assignImportedFile(at: url)
            }
        case let .failure(error):
            localErrorMessage = error.localizedDescription
        }
    }

    private func assignImportedFile(at url: URL) async {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try validateFileSize(data.count)
            let contentType = MimeType.fromFileExtension(url.pathExtension) ?? "application/octet-stream"
            let utType = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .audio
            let format = format(for: utType)
            let duration = try await mediaDuration(for: url)
            var thumbnailData: Data?
            var thumbnailContentType: String?

            if format == .video {
                if let thumbnail = try await generateThumbnail(for: url)?.squareArtwork(maxDimension: 800) {
                    let data = thumbnail.jpegData(compressionQuality: 0.75)
                    if let size = data?.count {
                        try validateFileSize(size)
                    }
                    thumbnailData = data
                    thumbnailContentType = data == nil ? nil : "image/jpeg"
                }
            }

            workingDraft.assignAsset(
                data: data,
                contentType: contentType,
                format: format,
                thumbnailData: thumbnailData,
                thumbnailContentType: thumbnailContentType,
                duration: duration
            )
        } catch {
            localErrorMessage = error.localizedDescription.isEmpty
                ? "We couldn’t access that file. Try downloading it locally first."
                : error.localizedDescription
        }
    }

    private func loadCoverArt() async {
        guard let item = coverArtPickerItem else { return }
        defer { coverArtPickerItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try validateFileSize(data.count)

            if let image = UIImage(data: data) {
                pendingCoverArt = PendingCoverArt(image: image)
            } else {
                workingDraft.assignCoverArt(data: data, contentType: "image/jpeg")
            }
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private var coverArtPreview: some View {
        Group {
            if let data = workingDraft.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = workingDraft.remoteThumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground)
            Image(systemName: "music.note")
                .foregroundStyle(Theme.primaryColor)
        }
    }

    private func assignCroppedCoverArt(image: UIImage) {
        let normalized = image.normalized()
        let processed = normalized.resized(maxDimension: 800)
        guard let data = processed.jpegData(compressionQuality: 0.85) else { return }

        do {
            try validateFileSize(data.count)
            workingDraft.assignCoverArt(data: data, contentType: "image/jpeg")
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func validateFileSize(_ bytes: Int) throws {
        if bytes > maxFileSizeBytes {
            throw MediaLibraryError.fileTooLarge(maxBytes: maxFileSizeBytes)
        }
    }

    private func mediaDuration(for url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url, options: [:])
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    private func generateThumbnail(for url: URL) async throws -> UIImage? {
        let asset = AVURLAsset(url: url, options: [:])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                switch result {
                case .succeeded:
                    if let cgImage {
                        continuation.resume(returning: UIImage(cgImage: cgImage))
                    } else {
                        continuation.resume(returning: nil)
                    }
                case .failed:
                    continuation.resume(throwing: error ?? MediaLibraryError.missingAsset)
                case .cancelled:
                    continuation.resume(returning: nil)
                @unknown default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct ProfileMediaEditorSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let icon: String
    let content: Content

    init(title: String, subtitle: String? = nil, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMedium) {
            HStack(spacing: Theme.spacingMedium) {
                ZStack {
                    Circle()
                        .fill(Theme.primaryColor.opacity(colorScheme == .dark ? 0.3 : 0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primaryColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .shadow(color: shadowColor, radius: 14, y: 6)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.06)
    }
}

private struct ProfileMediaEditorLabel: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.7)
        }
    }
}

private struct ProfileMediaEditorControlSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let background: Color
    let overlayColor: Color?
    let content: Content

    init(background: Color = Theme.elevatedCardBackground, overlayColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.background = background
        self.overlayColor = overlayColor
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(resolvedOverlayColor, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var resolvedOverlayColor: Color {
        if let overlayColor {
            return overlayColor
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

private struct ProfileMediaEditorMenuLabel: View {
    let title: String
    let icon: String?
    var isPlaceholder: Bool

    init(title: String, icon: String? = nil, isPlaceholder: Bool = false) {
        self.title = title
        self.icon = icon
        self.isPlaceholder = isPlaceholder
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isPlaceholder ? .secondary : Color.primary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileMediaEditorMenuOption: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primaryColor)
            }
        }
        .font(.callout)
    }
}

private struct ProfileMediaEditorActionLabel: View {
    let icon: String
    let title: String
    var tint: Color

    init(icon: String, title: String, tint: Color = Theme.primaryColor) {
        self.icon = icon
        self.title = title
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.callout.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileMediaEditorNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(1.5)
    }
}

private struct PendingCoverArt: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct AttachmentPreview: View {
    let draft: ProfileMediaDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(statusColor)

            if let sizeText = sizeDescription {
                Text(sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let playCountText = playCountDescription {
                Text(playCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if draft.data != nil {
            return "Selected file ready to upload after saving"
        }
        if draft.remoteURL != nil {
            return "Current file is already uploaded"
        }
        return "No file attached"
    }

    private var statusColor: Color {
        (draft.data != nil || draft.remoteURL != nil) ? .primary : .secondary
    }

    private var sizeDescription: String? {
        guard let bytes = draft.fileSizeBytes else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if draft.data != nil {
            return "File size \(formatted)"
        }
        if draft.remoteURL != nil {
            return "Uploaded size \(formatted)"
        }
        return nil
    }

    private var playCountDescription: String? {
        guard draft.mediaItem != nil else { return nil }
        let count = draft.playCount
        return "\(formattedPlayCount(count)) \(count == 1 ? "play" : "plays")"
    }

    private func formattedPlayCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

private struct ProfileMediaCollaboratorAvatar: View {
    let collaborator: ProfileMediaCollaborator

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.primaryColor.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryColor)
        }
    }

    private var iconName: String {
        if let role = collaborator.role {
            return role.systemImageName
        }
        switch collaborator.kind {
        case .user:
            return "person.crop.circle.fill"
        case .studio:
            return "building.2.fill"
        }
    }
}
