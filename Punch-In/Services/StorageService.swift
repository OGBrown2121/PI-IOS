import FirebaseStorage
import Foundation

/// Handles app file storage responsibilities.
protocol StorageService {
    func uploadImage(data: Data, path: String, contentType: String) async throws -> URL
    func uploadFile(
        data: Data,
        path: String,
        contentType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL
    func deleteFile(at path: String) async throws
}

struct FirebaseStorageService: StorageService {
    let storage: Storage

    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }

    func uploadImage(data: Data, path: String, contentType: String) async throws -> URL {
        try await uploadFile(data: data, path: path, contentType: contentType, progress: nil)
    }

    func uploadFile(
        data: Data,
        path: String,
        contentType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = reference.putData(data, metadata: metadata)

            var isFinished = false
            func finish(_ result: Result<URL, Error>) {
                guard isFinished == false else { return }
                isFinished = true
                uploadTask.removeAllObservers()
                switch result {
                case let .success(url):
                    continuation.resume(returning: url)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            if let progress {
                uploadTask.observe(.progress) { snapshot in
                    guard let fraction = snapshot.progress?.fractionCompleted else { return }
                    Task { @MainActor in
                        progress(min(max(fraction, 0), 1))
                    }
                }
            }

            uploadTask.observe(.failure) { snapshot in
                let error = snapshot.error ?? NSError(
                    domain: "StorageService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
                )
                finish(.failure(error))
            }

            uploadTask.observe(.success) { _ in
                Task { @MainActor in
                    progress?(1)
                }
                reference.downloadURL { url, error in
                    if let error {
                        finish(.failure(error))
                    } else if let url {
                        finish(.success(url))
                    } else {
                        finish(.failure(NSError(
                            domain: "StorageService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to obtain download URL"]
                        )))
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

    func uploadFile(
        data: Data,
        path: String,
        contentType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        progress?(1)
        return URL(string: "https://example.com/mock-storage/\(UUID().uuidString)")!
    }

    func deleteFile(at path: String) async throws {}
}

extension StorageService {
    func uploadFile(data: Data, path: String, contentType: String) async throws -> URL {
        try await uploadFile(data: data, path: path, contentType: contentType, progress: nil)
    }
}
