import Foundation
import SwiftUI

@MainActor
final class ProfileMediaUploadManager: ObservableObject {
    struct UploadState: Identifiable, Equatable {
        enum Phase: Equatable {
            case preparing
            case uploading
            case processing
            case success
            case failed(String)
        }

        let id = UUID()
        let draftId: String
        let title: String
        let format: ProfileMediaFormat
        var progress: Double?
        var phase: Phase
    }

    @Published private(set) var activeUpload: UploadState?

    private let firestoreService: any FirestoreService
    private var uploadTask: Task<Void, Never>?

    init(
        firestoreService: any FirestoreService
    ) {
        self.firestoreService = firestoreService
    }

    func startUpload(
        draft: ProfileMediaDraft,
        resolver: @escaping (ProfileMediaDraft, @escaping (Double) -> Void) async throws -> ProfileMediaItem,
        onSuccess: @escaping @MainActor (ProfileMediaItem) async -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard activeUpload == nil else {
            return false
        }

        var state = UploadState(
            draftId: draft.id,
            title: draft.displayTitle,
            format: draft.format,
            progress: draft.requiresAssetUpload ? 0 : nil,
            phase: .preparing
        )
        activeUpload = state

        uploadTask = Task { [firestoreService] in
            do {
                let progressHandler: (Double) -> Void = { [weak self] fraction in
                    guard Task.isCancelled == false else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.activeUpload?.phase = .uploading
                        self.activeUpload?.progress = min(max(fraction, 0), 1)
                    }
                }

                await MainActor.run {
                    self.activeUpload?.phase = .uploading
                }

                let preparedItem = try await resolver(draft, progressHandler)

                try Task.checkCancellation()
                await MainActor.run {
                    self.activeUpload?.phase = .processing
                    self.activeUpload?.progress = draft.requiresAssetUpload ? 1 : self.activeUpload?.progress
                }

                try await firestoreService.upsertProfileMedia(preparedItem)

                try Task.checkCancellation()
                await onSuccess(preparedItem)

                await MainActor.run {
                    self.activeUpload?.phase = .success
                    self.activeUpload?.progress = 1
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if case .success = self.activeUpload?.phase {
                        self.activeUpload = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.activeUpload = nil
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    self.activeUpload?.phase = .failed(message)
                }
                await onFailure(message)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if case .failed = self.activeUpload?.phase {
                        self.activeUpload = nil
                    }
                }
            }

            await MainActor.run {
                self.uploadTask = nil
            }
        }

        return true
    }
}
