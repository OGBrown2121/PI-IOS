import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BeatAudioAttachment: Equatable {
    let fileURL: URL
    let contentType: String
    let fileName: String
}

struct BeatArtworkAttachment: Equatable {
    let data: Data
    let contentType: String
}

struct BeatStemsAttachment: Equatable {
    let fileURL: URL
    let contentType: String
    let fileName: String
}

struct BeatUploadDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var license: ProducerBeat.License
    var priceText: String
    var stemsIncluded: Bool
    var bpmText: String
    var key: String
    var tagsText: String
    var genre: MusicGenre?
    var allowFreeDownload: Bool
    var audio: BeatAudioAttachment?
    var artwork: BeatArtworkAttachment?
    var stems: BeatStemsAttachment?
    var error: String?

    init(
        id: UUID = UUID(),
        title: String = "",
        summary: String = "",
        license: ProducerBeat.License = .nonExclusive,
        priceText: String = "",
        stemsIncluded: Bool = false,
        bpmText: String = "",
        key: String = "",
        tagsText: String = "",
        genre: MusicGenre? = nil,
        allowFreeDownload: Bool = false,
        audio: BeatAudioAttachment? = nil,
        artwork: BeatArtworkAttachment? = nil,
        stems: BeatStemsAttachment? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.license = license
        self.priceText = priceText
        self.stemsIncluded = stemsIncluded
        self.bpmText = bpmText
        self.key = key
        self.tagsText = tagsText
        self.genre = genre
        self.allowFreeDownload = allowFreeDownload
        self.audio = audio
        self.artwork = artwork
        self.stems = stems
        self.error = error
    }

    static func == (lhs: BeatUploadDraft, rhs: BeatUploadDraft) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.license == rhs.license
            && lhs.priceText == rhs.priceText
            && lhs.stemsIncluded == rhs.stemsIncluded
            && lhs.bpmText == rhs.bpmText
            && lhs.key == rhs.key
            && lhs.tagsText == rhs.tagsText
            && lhs.genre == rhs.genre
            && lhs.allowFreeDownload == rhs.allowFreeDownload
            && lhs.audio == rhs.audio
            && lhs.artwork == rhs.artwork
            && lhs.stems == rhs.stems
            && lhs.error == rhs.error
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var bpmValue: Int? {
        let trimmed = bpmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Int(trimmed)
    }

    func previewMediaItem(ownerId: String) -> ProfileMediaItem? {
        guard let audio else { return nil }
        return ProfileMediaItem(
            id: "beat-draft-\(id.uuidString)",
            ownerId: ownerId,
            title: trimmedTitle.isEmpty ? audio.fileName : trimmedTitle,
            caption: trimmedSummary,
            format: .audio,
            category: .song,
            mediaURL: audio.fileURL,
            durationSeconds: nil,
            isShared: true
        )
    }

    var requiresStemsAttachment: Bool {
        stemsIncluded
    }

    var isFreePrice: Bool {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) {
            return value <= 0
        }
        return false
    }
}

@MainActor
final class BeatCatalogManagerViewModel: ObservableObject {
    @Published private(set) var beats: [ProducerBeat] = []
    @Published var drafts: [BeatUploadDraft] = [BeatUploadDraft()]
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var uploadProgress: Double?
    @Published private(set) var uploadingDraftIDs: Set<UUID> = []

    let firestore: any FirestoreService
    let storage: any StorageService
    let currentUserProvider: () -> UserProfile?
    let maxDrafts = 3
    private let maxAudioFileSizeBytes: Int = 100 * 1024 * 1024
    private let maxStemsFileSizeBytes: Int = 400 * 1024 * 1024

    var audioFileSizeLimit: Int { maxAudioFileSizeBytes }
    var stemsFileSizeLimit: Int { maxStemsFileSizeBytes }

    init(
        firestore: any FirestoreService,
        storage: any StorageService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.firestore = firestore
        self.storage = storage
        self.currentUserProvider = currentUserProvider
    }

    var currentUser: UserProfile? {
        currentUserProvider()
    }

    var canAddDraft: Bool {
        drafts.count < maxDrafts
    }

    var uploadableDrafts: [BeatUploadDraft] {
        drafts.filter {
            $0.audio != nil
                && $0.trimmedTitle.isEmpty == false
                && parsePriceCents(from: $0.priceText) != nil
                && ($0.requiresStemsAttachment == false || $0.stems != nil)
        }
    }

    func refresh() async {
        guard let producer = currentUser else {
            errorMessage = "You need to be signed in to manage your catalog."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            beats = try await firestore.fetchBeatCatalog(for: producer.id, includeUnpublished: true)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func addDraft() {
        guard canAddDraft else { return }
        drafts.append(BeatUploadDraft())
    }

    func removeDraft(_ draft: BeatUploadDraft) {
        drafts.removeAll { $0.id == draft.id }
        if drafts.isEmpty {
            drafts = [BeatUploadDraft()]
        }
    }

    func replaceDraft(_ draft: BeatUploadDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
    }

    func resetMessages() {
        errorMessage = nil
        successMessage = nil
    }

    func uploadDrafts() async {
        guard let producer = currentUser else {
            errorMessage = "You need to be signed in to upload beats."
            return
        }

        let candidates = uploadableDrafts.prefix(maxDrafts)
        guard candidates.isEmpty == false else {
            errorMessage = "Add at least one beat with a title, price, and audio file."
            return
        }

        isUploading = true
        uploadProgress = 0
        uploadingDraftIDs = Set(candidates.map(\.id))
        defer {
            isUploading = false
            uploadProgress = nil
            uploadingDraftIDs = []
        }

        do {
            let totalCount = Double(candidates.count)
            for (index, draft) in candidates.enumerated() {
                let base = Double(index) / totalCount
                uploadProgress = base
                try await uploadDraft(draft, producer: producer) { beatFraction in
                    let normalized = min(max(beatFraction, 0), 1)
                    self.uploadProgress = base + (normalized / totalCount)
                }
                uploadProgress = Double(index + 1) / totalCount
            }
            successMessage = candidates.count == 1 ? "Beat uploaded successfully." : "Uploaded \(candidates.count) beats."
            errorMessage = nil
            drafts = [BeatUploadDraft()]
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteBeat(_ beat: ProducerBeat) async {
        guard let producer = currentUser else { return }
        do {
            try await firestore.deleteProducerBeat(producerId: producer.id, beatId: beat.id)
            beats.removeAll { $0.id == beat.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uploadDraft(
        _ draft: BeatUploadDraft,
        producer: UserProfile,
        progressHandler: @MainActor @escaping (Double) -> Void
    ) async throws {
        guard let attachment = draft.audio else {
            throw ValidationError("Select an audio file for \(draft.trimmedTitle.isEmpty ? "your beat" : draft.trimmedTitle).")
        }

        let priceCents = try parsePriceCentsOrThrow(from: draft.priceText)
        try validateAudioSize(at: attachment.fileURL)
        if draft.requiresStemsAttachment {
            guard let stemsAttachment = draft.stems else {
                throw ValidationError("Attach a ZIP of stems for \"\(draft.trimmedTitle.isEmpty ? attachment.fileName : draft.trimmedTitle)\".")
            }
            try validateStemsSize(at: stemsAttachment.fileURL)
        }

        let beatId = draft.id.uuidString
        let previewPath = makePreviewStoragePath(ownerId: producer.id, beatId: beatId, attachment: attachment)
        let previewData = try Data(contentsOf: attachment.fileURL)
        let totalSegments = Double(1 + (draft.artwork != nil ? 1 : 0) + (draft.requiresStemsAttachment ? 1 : 0))
        var completedSegments: Double = 0

        Task { @MainActor in
            progressHandler(0)
        }

        let previewURL = try await storage.uploadFile(
            data: previewData,
            path: previewPath,
            contentType: attachment.contentType
        ) { fraction in
            Task { @MainActor in
                guard totalSegments > 0 else { return }
                let normalized = (completedSegments + min(max(fraction, 0), 1)) / totalSegments
                progressHandler(normalized)
            }
        }

        completedSegments += 1
        Task { @MainActor in
            guard totalSegments > 0 else { return }
            progressHandler(completedSegments / totalSegments)
        }

        var artworkURL: URL?
        if let artwork = draft.artwork {
            let path = makeArtworkStoragePath(ownerId: producer.id, beatId: beatId, contentType: artwork.contentType)
            artworkURL = try await storage.uploadFile(
                data: artwork.data,
                path: path,
                contentType: artwork.contentType
            ) { fraction in
                Task { @MainActor in
                    guard totalSegments > 0 else { return }
                    let normalized = (completedSegments + min(max(fraction, 0), 1)) / totalSegments
                    progressHandler(normalized)
                }
            }
            completedSegments += 1
            Task { @MainActor in
                guard totalSegments > 0 else { return }
                progressHandler(completedSegments / totalSegments)
            }
        }

        var stemsURL: URL?
        if draft.requiresStemsAttachment, let stemsAttachment = draft.stems {
            let stemsData = try Data(contentsOf: stemsAttachment.fileURL)
            let stemsPath = makeStemsStoragePath(ownerId: producer.id, beatId: beatId, attachment: stemsAttachment)
            stemsURL = try await storage.uploadFile(
                data: stemsData,
                path: stemsPath,
                contentType: stemsAttachment.contentType
            ) { fraction in
                Task { @MainActor in
                    guard totalSegments > 0 else { return }
                    let normalized = (completedSegments + min(max(fraction, 0), 1)) / totalSegments
                    progressHandler(normalized)
                }
            }
            completedSegments += 1
            Task { @MainActor in
                guard totalSegments > 0 else { return }
                progressHandler(completedSegments / totalSegments)
            }
        }

        let durationSeconds = audioDuration(for: attachment.fileURL)

        var beat = ProducerBeat(
            id: beatId,
            producerId: producer.id,
            title: draft.trimmedTitle,
            summary: draft.trimmedSummary,
            license: draft.license,
            primaryGenre: draft.genre,
            priceCents: priceCents,
            currencyCode: "USD",
            bpm: draft.bpmValue,
            musicalKey: draft.trimmedKey.isEmpty ? nil : draft.trimmedKey,
            durationSeconds: durationSeconds,
            stemsIncluded: draft.stemsIncluded,
            tags: draft.tags,
            allowFreeDownload: priceCents == 0 ? true : draft.allowFreeDownload,
            isPublished: true
        )

        beat.tags = beat.sanitizedTags
        beat = beat.updatingMedia(previewURL: previewURL, artworkURL: artworkURL, stemsZipURL: stemsURL)
        beat.durationSeconds = durationSeconds
        beat.stemsIncluded = draft.stemsIncluded
        beat.tags = beat.sanitizedTags
        beat.updatedAt = Date()

        try await firestore.upsertProducerBeat(beat)
    }

    private func makePreviewStoragePath(ownerId: String, beatId: String, attachment: BeatAudioAttachment) -> String {
        let ext = attachment.fileURL.pathExtension.isEmpty ? guessExtension(from: attachment.contentType) : attachment.fileURL.pathExtension
        return "beats/\(ownerId)/\(beatId)/preview.\(ext)"
    }

    private func makeArtworkStoragePath(ownerId: String, beatId: String, contentType: String) -> String {
        let fileExtension: String
        switch contentType {
        case "image/png":
            fileExtension = "png"
        case "image/jpeg":
            fallthrough
        default:
            fileExtension = "jpg"
        }
        return "beats/\(ownerId)/\(beatId)/artwork.\(fileExtension)"
    }

    private func makeStemsStoragePath(ownerId: String, beatId: String, attachment: BeatStemsAttachment) -> String {
        let ext = attachment.fileURL.pathExtension.isEmpty ? "zip" : attachment.fileURL.pathExtension
        return "beats/\(ownerId)/\(beatId)/stems.\(ext)"
    }

    private func parsePriceCentsOrThrow(from text: String) throws -> Int {
        if let cents = parsePriceCents(from: text) {
            return cents
        }
        throw ValidationError("Enter a valid price for your beat (like 49 or 49.99).")
    }

    private func parsePriceCents(from text: String) -> Int? {
        let filtered = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filtered.isEmpty == false else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal

        if let number = formatter.number(from: filtered) {
            return Int(round(number.doubleValue * 100))
        }

        let normalized = filtered.replacingOccurrences(of: ",", with: ".")
        if let doubleValue = Double(normalized) {
            return Int(round(doubleValue * 100))
        }

        return nil
    }

    private func validateAudioSize(at url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize else { return }
        if fileSize > maxAudioFileSizeBytes {
            throw ValidationError("\"\(url.lastPathComponent)\" is too large. Please select an audio file under 100 MB.")
        }
    }

    private func validateStemsSize(at url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize else { return }
        if fileSize > maxStemsFileSizeBytes {
            throw ValidationError("Stems archive \"\(url.lastPathComponent)\" is too large. Keep stems under 400 MB.")
        }
    }

    private func audioDuration(for url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        guard duration.isNumeric else { return nil }
        return CMTimeGetSeconds(duration)
    }

    private func guessExtension(from contentType: String) -> String {
        switch contentType {
        case "audio/wav":
            return "wav"
        case "audio/mp4":
            return "m4a"
        case "audio/mpeg":
            return "mp3"
        default:
            return "mp3"
        }
    }

    enum ValidationError: LocalizedError {
        case message(String)

        init(_ message: String) {
            self = .message(message)
        }

        var errorDescription: String? {
            switch self {
            case let .message(message):
                return message
            }
        }
    }
}
