import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProfileMediaLibraryViewModel: ObservableObject {
    @Published private(set) var mediaItems: [ProfileMediaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var uploadErrorMessage: String?
    @Published var selectedDraft: ProfileMediaDraft?

    let firestoreService: any FirestoreService
    let storageService: any StorageService
    let currentUserProvider: () -> UserProfile?
    let uploadManager: ProfileMediaUploadManager
    private let maxFileSizeBytes = ProfileMediaConstraints.maxFileSizeBytes

    init(
        firestoreService: any FirestoreService,
        storageService: any StorageService,
        currentUserProvider: @escaping () -> UserProfile?,
        uploadManager: ProfileMediaUploadManager
    ) {
        self.firestoreService = firestoreService
        self.storageService = storageService
        self.currentUserProvider = currentUserProvider
        self.uploadManager = uploadManager
    }

    var currentUser: UserProfile? {
        currentUserProvider()
    }

    var mediaCapabilities: ProfileMediaCapabilities? {
        currentUser?.mediaCapabilities
    }

    var pinnedItems: [ProfileMediaItem] {
        mediaItems.filter { $0.pinnedRank != nil }.sorted(by: mediaSort)
    }

    var libraryItems: [ProfileMediaItem] {
        mediaItems.filter { $0.pinnedRank == nil }.sorted(by: mediaSort)
    }

    private var pinLimit: Int {
        mediaCapabilities?.pinLimit ?? 0
    }

    var isPinLimitReached: Bool {
        pinLimit > 0 && pinnedItemsCount() >= pinLimit
    }

    func refresh() async {
        guard let ownerId = currentUser?.id else {
            errorMessage = "Unable to load media without an authenticated user."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await firestoreService.fetchProfileMedia(for: ownerId)
            mediaItems = items
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func makeDraft(for item: ProfileMediaItem? = nil) -> ProfileMediaDraft {
        guard let owner = currentUser else {
            return ProfileMediaDraft(ownerId: "", title: "", category: .song, format: .audio)
        }

        if let item {
            return ProfileMediaDraft(mediaItem: item, ownerId: owner.id)
        }

        let defaultCategory = owner.mediaCapabilities.defaultCategories.first ?? .song
        return ProfileMediaDraft(ownerId: owner.id, title: "", category: defaultCategory, format: defaultCategory.defaultFormat)
    }

    func save(
        draft: ProfileMediaDraft,
        onCompletion: (@MainActor (ProfileMediaItem) async -> Void)? = nil
    ) async -> Bool {
        guard let owner = currentUser else {
            uploadErrorMessage = "You must be signed in to upload media."
            return false
        }

        var workingDraft = draft
        workingDraft.ownerId = owner.id
        workingDraft.isShared = true

        if workingDraft.requiresAssetUpload {
            return enqueueBackgroundUpload(with: workingDraft, onCompletion: onCompletion)
        } else {
            return await performImmediateSave(with: workingDraft, onCompletion: onCompletion)
        }
    }

    private func enqueueBackgroundUpload(
        with draft: ProfileMediaDraft,
        onCompletion: (@MainActor (ProfileMediaItem) async -> Void)?
    ) -> Bool {
        let scheduled = uploadManager.startUpload(
            draft: draft,
            resolver: { draft, progressHandler in
                try await self.resolveMediaItem(from: draft, progressHandler: progressHandler)
            },
            onSuccess: { item in
                self.mergeUpdatedItem(item)
                await self.reorderPinsIfNeeded()
                self.uploadErrorMessage = nil
                if let onCompletion {
                    await onCompletion(item)
                }
            },
            onFailure: { message in
                self.uploadErrorMessage = message
            }
        )

        if scheduled == false {
            uploadErrorMessage = "Finish the current upload before starting another upload."
            return false
        }

        uploadErrorMessage = nil
        return true
    }

    private func performImmediateSave(
        with draft: ProfileMediaDraft,
        onCompletion: (@MainActor (ProfileMediaItem) async -> Void)?
    ) async -> Bool {
        do {
            let preparedItem = try await resolveMediaItem(from: draft, progressHandler: nil)
            try await firestoreService.upsertProfileMedia(preparedItem)
            mergeUpdatedItem(preparedItem)
            await reorderPinsIfNeeded()
            uploadErrorMessage = nil
            if let onCompletion {
                await onCompletion(preparedItem)
            }
            return true
        } catch {
            uploadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func delete(_ media: ProfileMediaItem) async {
        guard let owner = currentUser else { return }
        do {
            try await firestoreService.deleteProfileMedia(ownerId: owner.id, mediaId: media.id)
            mediaItems.removeAll { $0.id == media.id }
            await reorderPinsIfNeeded()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setPinned(_ isPinned: Bool, for media: ProfileMediaItem) async {
        if isPinned && pinLimit > 0 && pinnedItemsCount(excluding: media.id) >= pinLimit && media.isPinned == false {
            uploadErrorMessage = "You can pin up to \(pinLimit) items."
            return
        }

        var updated = media
        if isPinned {
            updated.isShared = true
            updated.pinnedRank = nextPinIndex()
        } else {
            updated.pinnedRank = nil
        }
        _ = await save(draft: ProfileMediaDraft(mediaItem: updated, ownerId: updated.ownerId))
    }

    func updatePinnedOrder(_ orderedIds: [String]) async {
        guard let owner = currentUser else { return }
        do {
            try await firestoreService.reorderProfileMediaPins(ownerId: owner.id, orderedPinnedIds: orderedIds)
            let lookup = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($1, $0) })
            mediaItems = mediaItems.map { item in
                var copy = item
                copy.pinnedRank = lookup[item.id]
                return copy
            }
            mediaItems.sort(by: mediaSort)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reorderPinsIfNeeded() async {
        let orderedPinnedIds = mediaItems
            .filter { $0.pinnedRank != nil }
            .sorted(by: mediaSort)
            .compactMap { $0.id }

        guard let owner = currentUser else { return }
        do {
            try await firestoreService.reorderProfileMediaPins(ownerId: owner.id, orderedPinnedIds: orderedPinnedIds)
        } catch {
            Logger.log("Failed to persist pin order: \(error.localizedDescription)")
        }
    }

    private func mergeUpdatedItem(_ item: ProfileMediaItem) {
        if let index = mediaItems.firstIndex(where: { $0.id == item.id }) {
            mediaItems[index] = item
        } else {
            mediaItems.append(item)
        }
        mediaItems.sort(by: mediaSort)
    }

    func refreshItem(_ item: ProfileMediaItem) {
        mergeUpdatedItem(item)
    }

    func removeItem(withId mediaId: String) {
        mediaItems.removeAll { $0.id == mediaId }
    }

    private func mediaSort(lhs: ProfileMediaItem, rhs: ProfileMediaItem) -> Bool {
        switch (lhs.pinnedRank, rhs.pinnedRank) {
        case let (lhsRank?, rhsRank?):
            if lhsRank == rhsRank {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsRank < rhsRank
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func resolveMediaItem(
        from draft: ProfileMediaDraft,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> ProfileMediaItem {
        let mediaId = draft.id ?? UUID().uuidString
        guard draft.hasRemoteAsset else {
            throw MediaLibraryError.missingAsset
        }

        var mediaURL = draft.remoteURL ?? draft.mediaItem?.mediaURL
        var thumbnailURL = draft.remoteThumbnailURL ?? draft.mediaItem?.thumbnailURL
        var coverArtURL = draft.mediaItem?.coverArtURL

        if let uploadData = draft.data {
            try validateFileSize(bytes: uploadData.count)
            guard let contentType = draft.contentType else {
                throw MediaLibraryError.missingAsset
            }
            mediaURL = try await storageService.uploadFile(
                data: uploadData,
                path: "users/\(draft.ownerId)/media/\(mediaId)/original",
                contentType: contentType,
                progress: progressHandler
            )
        } else {
            progressHandler?(1)
        }

        if let thumbData = draft.thumbnailData {
            try validateFileSize(bytes: thumbData.count)
            guard let thumbType = draft.thumbnailContentType else {
                throw MediaLibraryError.missingAsset
            }
            thumbnailURL = try await storageService.uploadFile(
                data: thumbData,
                path: "users/\(draft.ownerId)/media/\(mediaId)/thumbnail",
                contentType: thumbType,
                progress: nil
            )
            if draft.format == .audio {
                coverArtURL = thumbnailURL
            } else if coverArtURL == nil {
                coverArtURL = thumbnailURL
            }
        }

        let createdAt = draft.createdAt ?? Date()
        let pinnedRank: Int?
        if draft.isPinned {
            pinnedRank = draft.pinnedRank ?? nextPinIndex()
        } else {
            pinnedRank = nil
        }

        return ProfileMediaItem(
            id: mediaId,
            ownerId: draft.ownerId,
            title: draft.title,
            caption: draft.caption,
            format: draft.format,
            category: draft.category,
            mediaURL: mediaURL,
            thumbnailURL: thumbnailURL,
            coverArtURL: coverArtURL ?? thumbnailURL,
            durationSeconds: draft.durationSeconds,
            fileSizeBytes: draft.fileSizeBytes ?? draft.data?.count,
            collaborators: draft.collaborators,
            playCount: draft.playCount,
            ratings: draft.mediaItem?.ratings ?? [:],
            pinnedRank: pinnedRank,
            isShared: draft.isShared || pinnedRank != nil,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    private func nextPinIndex() -> Int {
        let pinnedRanks = mediaItems.compactMap(\.pinnedRank)
        guard let maxRank = pinnedRanks.max() else { return 0 }
        return maxRank + 1
    }

    private func pinnedItemsCount(excluding mediaId: String? = nil) -> Int {
        mediaItems.filter { $0.pinnedRank != nil && $0.id != mediaId }.count
    }

    func makeCollaboratorSearchViewModel() -> ProfileMediaCollaboratorSearchViewModel {
        ProfileMediaCollaboratorSearchViewModel(firestoreService: firestoreService)
    }

    private func validateFileSize(bytes: Int) throws {
        if bytes > maxFileSizeBytes {
            throw MediaLibraryError.fileTooLarge(maxBytes: maxFileSizeBytes)
        }
    }
}

struct ProfileMediaDraft: Identifiable, Equatable {
    var id: String {
        mediaItem?.id ?? identifier
    }

    private let identifier: String
    var mediaItem: ProfileMediaItem?
    var ownerId: String
    var title: String
    var caption: String
    var category: ProfileMediaCategory
    var format: ProfileMediaFormat
    var collaborators: [ProfileMediaCollaborator]
    var isPinned: Bool
    var pinnedRank: Int?
    var isShared: Bool
    var createdAt: Date?
    var remoteURL: URL?
    var remoteThumbnailURL: URL?
    var durationSeconds: Double?
    var fileSizeBytes: Int?
    var playCount: Int

    var data: Data?
    var thumbnailData: Data?
    var contentType: String?
    var thumbnailContentType: String?

    init(
        mediaItem: ProfileMediaItem,
        ownerId: String
    ) {
        self.mediaItem = mediaItem
        identifier = mediaItem.id
        self.ownerId = ownerId
        title = mediaItem.title
        caption = mediaItem.caption
        category = mediaItem.category
        format = mediaItem.format
        collaborators = mediaItem.collaborators
        isPinned = mediaItem.isPinned
        pinnedRank = mediaItem.pinnedRank
        isShared = mediaItem.isShared
        createdAt = mediaItem.createdAt
        remoteURL = mediaItem.mediaURL
        remoteThumbnailURL = mediaItem.thumbnailURL
        durationSeconds = mediaItem.durationSeconds
        fileSizeBytes = mediaItem.fileSizeBytes
        playCount = mediaItem.playCount
    }

    init(
        ownerId: String,
        title: String,
        caption: String = "",
        category: ProfileMediaCategory,
        format: ProfileMediaFormat
    ) {
        identifier = UUID().uuidString
        self.ownerId = ownerId
        self.title = title
        self.caption = caption
        self.category = category
        self.format = format
        collaborators = []
        isPinned = false
        pinnedRank = nil
        isShared = true
        playCount = 0
    }

    var hasRemoteAsset: Bool {
        remoteURL != nil || data != nil
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.displayTitle : trimmed
    }

    var requiresAssetUpload: Bool {
        data != nil || thumbnailData != nil
    }

    mutating func assignAsset(
        data: Data,
        contentType: String,
        format: ProfileMediaFormat,
        thumbnailData: Data? = nil,
        thumbnailContentType: String? = nil,
        duration: Double? = nil
    ) {
        self.data = data
        self.contentType = contentType
        self.format = format
        fileSizeBytes = data.count
        remoteURL = nil

        if let duration {
            durationSeconds = duration
        }

        if let thumbnailData, let thumbnailContentType {
            self.thumbnailData = thumbnailData
            self.thumbnailContentType = thumbnailContentType
            remoteThumbnailURL = nil
        }
    }

    mutating func assignCoverArt(data: Data, contentType: String) {
        thumbnailData = data
        thumbnailContentType = contentType
        remoteThumbnailURL = nil
    }
}

enum MediaLibraryError: LocalizedError {
    case missingAsset
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .missingAsset:
            return "Please attach a file before saving."
        case let .fileTooLarge(maxBytes):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .binary)
            return "This file is too large. Please choose a file under \(formatted)."
        }
    }
}
