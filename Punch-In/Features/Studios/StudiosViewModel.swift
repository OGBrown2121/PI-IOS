import FirebaseStorage
import Foundation

/// Loads studios and exposes them to the studios list.
@MainActor
final class StudiosViewModel: ObservableObject {
    @Published var studios: [Studio] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let firestoreService: any FirestoreService
    private let storageService: any StorageService
    private var studiosTask: Task<Void, Never>?

    init(firestoreService: any FirestoreService, storageService: any StorageService) {
        self.firestoreService = firestoreService
        self.storageService = storageService
    }

    deinit {
        studiosTask?.cancel()
    }

    func listenForStudios() {
        guard studiosTask == nil else { return }
        isLoading = true
        errorMessage = nil

        studiosTask = Task {
            do {
                for try await studios in firestoreService.observeStudios() {
                    await MainActor.run {
                        self.studios = studios
                        self.isLoading = false
                        self.errorMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func stopListening() {
        studiosTask?.cancel()
        studiosTask = nil
    }

    func refreshStudios() async -> Bool {
        do {
            let latest = try await firestoreService.fetchStudios()
            studios = latest
            errorMessage = nil
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func saveStudio(
        name: String,
        city: String,
        ownerId: String,
        studioId: String?,
        address: String,
        hourlyRate: Double?,
        rooms: Int?,
        amenities: [String],
        coverImageData: Data?,
        logoImageData: Data?,
        coverImageContentType: String,
        logoImageContentType: String,
        existingCoverURL: URL?,
        existingLogoURL: URL?,
        removeCoverImage: Bool,
        removeLogoImage: Bool
    ) async -> String? {
        let trimmedName = name.trimmed
        let trimmedCity = city.trimmed

        guard !trimmedName.isEmpty else { return "Studio name is required." }
        guard !trimmedCity.isEmpty else { return "Studio city is required." }

        let studioIdentifier = studioId ?? UUID().uuidString

        if studioId == nil {
            let placeholder = Studio(
                id: studioIdentifier,
                ownerId: ownerId,
                name: trimmedName,
                city: trimmedCity,
                address: address.trimmed,
                hourlyRate: hourlyRate,
                rooms: rooms,
                amenities: amenities
            )

            do {
                try await firestoreService.upsertStudio(placeholder)
            } catch {
                return error.localizedDescription
            }
        }

        var resolvedCoverURL = existingCoverURL
        var resolvedLogoURL = existingLogoURL

        if removeCoverImage {
            await deleteFileIfExists(path: "studios/\(studioIdentifier)/cover.jpg")
            resolvedCoverURL = nil
        } else if let coverImageData {
            do {
                resolvedCoverURL = try await storageService.uploadImage(
                    data: coverImageData,
                    path: "studios/\(studioIdentifier)/cover.jpg",
                    contentType: coverImageContentType
                )
            } catch {
                return error.localizedDescription
            }
        }

        if removeLogoImage {
            await deleteFileIfExists(path: "studios/\(studioIdentifier)/logo.jpg")
            resolvedLogoURL = nil
        } else if let logoImageData {
            do {
                resolvedLogoURL = try await storageService.uploadImage(
                    data: logoImageData,
                    path: "studios/\(studioIdentifier)/logo.jpg",
                    contentType: logoImageContentType
                )
            } catch {
                return error.localizedDescription
            }
        }

        let studio = Studio(
            id: studioIdentifier,
            ownerId: ownerId,
            name: trimmedName,
            city: trimmedCity,
            address: address.trimmed,
            hourlyRate: hourlyRate,
            rooms: rooms,
            amenities: amenities,
            coverImageURL: resolvedCoverURL,
            logoImageURL: resolvedLogoURL,
            approvedEngineerIds: studios.first { $0.id == studioIdentifier }?.approvedEngineerIds ?? []
        )

        do {
            try await firestoreService.upsertStudio(studio)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func deleteFileIfExists(path: String) async {
        do {
            try await storageService.deleteFile(at: path)
        } catch {
            if let storageError = error as NSError?,
               storageError.domain == StorageErrorDomain,
               StorageErrorCode(rawValue: storageError.code) == .objectNotFound {
                return
            }
        }
    }
}
