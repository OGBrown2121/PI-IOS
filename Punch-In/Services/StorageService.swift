import FirebaseStorage
import Foundation

/// Handles app file storage responsibilities.
protocol StorageService {
    func uploadImage(data: Data, path: String, contentType: String) async throws -> URL
    func deleteFile(at path: String) async throws
}

struct FirebaseStorageService: StorageService {
    let storage: Storage

    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }

    func uploadImage(data: Data, path: String, contentType: String) async throws -> URL {
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        return try await withCheckedThrowingContinuation { continuation in
            reference.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                reference.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain download URL"]))
                    }
                }
            }
        }
    }

    func deleteFile(at path: String) async throws {
        let reference = storage.reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct MockStorageService: StorageService {
    func uploadImage(data: Data, path: String, contentType: String) async throws -> URL {
        URL(string: "https://example.com/mock-storage/\(UUID().uuidString).jpg")!
    }

    func deleteFile(at path: String) async throws {}
}
