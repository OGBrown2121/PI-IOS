import FirebaseFirestore
import Foundation

enum FirestoreServiceError: LocalizedError {
    case engineerAlreadyMember
    case engineerRequestNotFound

    var errorDescription: String? {
        switch self {
        case .engineerAlreadyMember:
            return "This engineer is already approved to work at this studio."
        case .engineerRequestNotFound:
            return "We couldn't find that request anymore."
        }
    }
}

/// Provides access to Firestore-backed data models.
protocol FirestoreService {
    func fetchStudios() async throws -> [Studio]
    func observeStudios() -> AsyncThrowingStream<[Studio], Error>
    func upsertStudio(_ studio: Studio) async throws

    func loadUserProfile(for userID: String) async throws -> UserProfile?
    func saveUserProfile(_ profile: UserProfile) async throws

    func fetchEngineerRequest(studioId: String, engineerId: String) async throws -> StudioEngineerRequest?
    func submitEngineerRequest(studioId: String, studioOwnerId: String, engineerId: String) async throws
    func withdrawEngineerRequest(studioId: String, engineerId: String) async throws
    func updateEngineerRequestStatus(
        studioId: String,
        engineerId: String,
        status: StudioEngineerRequest.Status
    ) async throws
    func fetchEngineerRequests(studioId: String) async throws -> [StudioEngineerRequest]
    func fetchUserProfiles(for userIDs: [String]) async throws -> [UserProfile]
}

struct FirebaseFirestoreService: FirestoreService {
    private let database: Firestore

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func fetchStudios() async throws -> [Studio] {
        let snapshot = try await database.collection("studios").getDocuments()
        return snapshot.documents.map { decodeStudio(documentID: $0.documentID, data: $0.data()) }
    }

    func observeStudios() -> AsyncThrowingStream<[Studio], Error> {
        AsyncThrowingStream { continuation in
            let listener = database.collection("studios").addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                let studios = snapshot.documents.map { decodeStudio(documentID: $0.documentID, data: $0.data()) }
                continuation.yield(studios)
            }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func upsertStudio(_ studio: Studio) async throws {
        var data: [String: Any] = [
            "name": studio.name,
            "city": studio.city,
            "ownerId": studio.ownerId,
            "address": studio.address,
            "amenities": studio.amenities
        ]

        if let hourlyRate = studio.hourlyRate {
            data["hourlyRate"] = hourlyRate
        }

        if let rooms = studio.rooms {
            data["rooms"] = rooms
        }

        if let coverImageURL = studio.coverImageURL?.absoluteString {
            data["coverImageURL"] = coverImageURL
        }

        if let logoImageURL = studio.logoImageURL?.absoluteString {
            data["logoImageURL"] = logoImageURL
        }

        try await database.collection("studios")
            .document(studio.id)
            .setData(data, merge: true)
    }

    func loadUserProfile(for userID: String) async throws -> UserProfile? {
        let document = try await database.collection("profiles").document(userID).getDocument()
        guard let data = document.data() else { return nil }

        return decodeUserProfile(id: document.documentID, data: data)
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        var data: [String: Any] = [
            "username": profile.username,
            "displayName": profile.displayName,
            "createdAt": Timestamp(date: profile.createdAt),
            "accountType": profile.accountType.rawValue
        ]

        data["profileDetails"] = [
            "bio": profile.profileDetails.bio,
            "fieldOne": profile.profileDetails.fieldOne,
            "fieldTwo": profile.profileDetails.fieldTwo
        ]

        if let profileImageURL = profile.profileImageURL?.absoluteString {
            data["profileImageURL"] = profileImageURL
        } else {
            data["profileImageURL"] = FieldValue.delete()
        }

        try await database.collection("profiles").document(profile.id).setData(data, merge: true)
    }

    func fetchEngineerRequest(studioId: String, engineerId: String) async throws -> StudioEngineerRequest? {
        let reference = database
            .collection("studios")
            .document(studioId)
            .collection("engineerRequests")
            .document(engineerId)

        let snapshot = try await reference.getDocument()
        guard let data = snapshot.data() else { return nil }
        return decodeEngineerRequest(
            studioId: studioId,
            documentID: snapshot.documentID,
            data: data
        )
    }

    func submitEngineerRequest(studioId: String, studioOwnerId: String, engineerId: String) async throws {
        let reference = database
            .collection("studios")
            .document(studioId)
            .collection("engineerRequests")
            .document(engineerId)

        let existingSnapshot = try await reference.getDocument()
        let existingData = existingSnapshot.data()

        if let statusRaw = existingData?["status"] as? String,
           let status = StudioEngineerRequest.Status(rawValue: statusRaw),
           status == .accepted {
            throw FirestoreServiceError.engineerAlreadyMember
        }

        let now = Timestamp(date: Date())
        let createdAt = (existingData?["createdAt"] as? Timestamp) ?? now

        try await reference.setData([
            "engineerId": engineerId,
            "studioOwnerId": studioOwnerId,
            "status": StudioEngineerRequest.Status.pending.rawValue,
            "createdAt": createdAt,
            "updatedAt": now
        ], merge: true)
    }

    func updateEngineerRequestStatus(
        studioId: String,
        engineerId: String,
        status: StudioEngineerRequest.Status
    ) async throws {
        let studioReference = database.collection("studios").document(studioId)
        let requestReference = studioReference
            .collection("engineerRequests")
            .document(engineerId)

        let now = Timestamp(date: Date())

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let requestSnapshot = try transaction.getDocument(requestReference)
                guard requestSnapshot.exists else {
                    errorPointer?.pointee = makeNSError(FirestoreServiceError.engineerRequestNotFound)
                    return nil
                }

                _ = try transaction.getDocument(studioReference)

                transaction.updateData([
                    "status": status.rawValue,
                    "updatedAt": now
                ], forDocument: requestReference)

                switch status {
            case .accepted:
                transaction.updateData([
                    "approvedEngineerIds": FieldValue.arrayUnion([engineerId])
                ], forDocument: studioReference)
            case .denied, .pending:
                transaction.updateData([
                        "approvedEngineerIds": FieldValue.arrayRemove([engineerId])
                    ], forDocument: studioReference)
                }
            } catch {
                errorPointer?.pointee = makeNSError(error)
            }

            return nil
        }
    }

    func withdrawEngineerRequest(studioId: String, engineerId: String) async throws {
        let studioReference = database.collection("studios").document(studioId)
        let requestReference = studioReference
            .collection("engineerRequests")
            .document(engineerId)

        do {
            let snapshot = try await requestReference.getDocument()
            guard snapshot.exists else { return }
            try await requestReference.delete()
        } catch {
            throw error
        }
    }

    func fetchEngineerRequests(studioId: String) async throws -> [StudioEngineerRequest] {
        let snapshot = try await database
            .collection("studios")
            .document(studioId)
            .collection("engineerRequests")
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.map { document in
            decodeEngineerRequest(
                studioId: studioId,
                documentID: document.documentID,
                data: document.data()
            )
        }
    }

    func fetchUserProfiles(for userIDs: [String]) async throws -> [UserProfile] {
        let uniqueIDs = Array(Set(userIDs))
        guard !uniqueIDs.isEmpty else { return [] }

        var collected: [UserProfile] = []
        for chunk in chunked(uniqueIDs, size: 10) {
            let query = database
                .collection("profiles")
                .whereField(FieldPath.documentID(), in: chunk)
            let snapshot = try await query.getDocuments()
            collected.append(contentsOf: snapshot.documents.map { document in
                decodeUserProfile(id: document.documentID, data: document.data())
            })
        }

        let ordering = userIDs
        return collected.sorted { lhs, rhs in
            guard let leftIndex = ordering.firstIndex(of: lhs.id) else { return false }
            guard let rightIndex = ordering.firstIndex(of: rhs.id) else { return true }
            return leftIndex < rightIndex
        }
    }

    private func decodeUserProfile(id: String, data: [String: Any]) -> UserProfile {
        let profileData = data["profileDetails"] as? [String: Any] ?? [:]
        let accountTypeRawValue = data["accountType"] as? String ?? AccountType.artist.rawValue
        let accountType = AccountType(rawValue: accountTypeRawValue) ?? .artist
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let username = data["username"] as? String ?? ""
        let displayName = data["displayName"] as? String ?? username
        let profileImageURL = (data["profileImageURL"] as? String).flatMap(URL.init(string:))

        let details = AccountProfileDetails(
            bio: profileData["bio"] as? String ?? "",
            fieldOne: profileData["fieldOne"] as? String ?? "",
            fieldTwo: profileData["fieldTwo"] as? String ?? ""
        )

        return UserProfile(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt,
            profileImageURL: profileImageURL,
            accountType: accountType,
            profileDetails: details
        )
    }

    private func decodeStudio(documentID: String, data: [String: Any]) -> Studio {
        Studio(
            id: documentID,
            ownerId: data["ownerId"] as? String ?? "",
            name: data["name"] as? String ?? "",
            city: data["city"] as? String ?? "",
            address: data["address"] as? String ?? "",
            hourlyRate: data["hourlyRate"] as? Double,
            rooms: data["rooms"] as? Int,
            amenities: data["amenities"] as? [String] ?? [],
            coverImageURL: (data["coverImageURL"] as? String).flatMap(URL.init(string:)),
            logoImageURL: (data["logoImageURL"] as? String).flatMap(URL.init(string:)),
            approvedEngineerIds: data["approvedEngineerIds"] as? [String] ?? []
        )
    }

    private func decodeEngineerRequest(
        studioId: String,
        documentID: String,
        data: [String: Any]
    ) -> StudioEngineerRequest {
        let statusRaw = data["status"] as? String ?? StudioEngineerRequest.Status.pending.rawValue
        let status = StudioEngineerRequest.Status(rawValue: statusRaw) ?? .pending
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let engineerId = data["engineerId"] as? String ?? documentID

        return StudioEngineerRequest(
            id: documentID,
            studioId: studioId,
            engineerId: engineerId,
            studioOwnerId: data["studioOwnerId"] as? String ?? "",
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        var result: [[T]] = []
        var index = 0
        while index < array.count {
            let end = Swift.min(index + size, array.count)
            result.append(Array(array[index..<end]))
            index += size
        }
        return result
    }

    private func makeNSError(_ error: Error) -> NSError {
        if let nsError = error as NSError? {
            return nsError
        }
        return NSError(
            domain: "FirebaseFirestoreService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
}

final class MockFirestoreService: FirestoreService {
    private var storedProfiles: [String: UserProfile] = [:]
    private var storedStudios: [Studio] = Studio.mockList
    private var studioStreams: [UUID: AsyncThrowingStream<[Studio], Error>.Continuation] = [:]
    private var studioEngineerRequests: [String: [StudioEngineerRequest]] = [:]

    func fetchStudios() async throws -> [Studio] {
        storedStudios
    }

    func observeStudios() -> AsyncThrowingStream<[Studio], Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            continuation.yield(storedStudios)
            studioStreams[token] = continuation
            continuation.onTermination = { [self] _ in
                studioStreams.removeValue(forKey: token)
            }
        }
    }

    func upsertStudio(_ studio: Studio) async throws {
        if let index = storedStudios.firstIndex(where: { $0.id == studio.id }) {
            storedStudios[index] = studio
        } else {
            storedStudios.append(studio)
        }
        notifyStudioStreams()
    }

    func loadUserProfile(for userID: String) async throws -> UserProfile? {
        storedProfiles[userID]
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        storedProfiles[profile.id] = profile
    }

    func fetchEngineerRequest(studioId: String, engineerId: String) async throws -> StudioEngineerRequest? {
        studioEngineerRequests[studioId]?.first { $0.engineerId == engineerId }
    }

    func submitEngineerRequest(studioId: String, studioOwnerId: String, engineerId: String) async throws {
        var requests = studioEngineerRequests[studioId] ?? []
        if let index = requests.firstIndex(where: { $0.engineerId == engineerId }) {
            let existing = requests[index]
            guard existing.status != .accepted else {
                throw FirestoreServiceError.engineerAlreadyMember
            }
            var updated = existing
            updated.status = .pending
            updated.updatedAt = Date()
            requests[index] = updated
        } else {
            requests.append(
                StudioEngineerRequest(
                    id: engineerId,
                    studioId: studioId,
                    engineerId: engineerId,
                    studioOwnerId: studioOwnerId,
                    status: .pending,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        }
        studioEngineerRequests[studioId] = requests
    }

    func withdrawEngineerRequest(studioId: String, engineerId: String) async throws {
        var requests = studioEngineerRequests[studioId] ?? []
        requests.removeAll { $0.engineerId == engineerId }
        studioEngineerRequests[studioId] = requests

        if let studioIndex = storedStudios.firstIndex(where: { $0.id == studioId }) {
            var studio = storedStudios[studioIndex]
            studio.approvedEngineerIds.removeAll { $0 == engineerId }
            storedStudios[studioIndex] = studio
            notifyStudioStreams()
        }
    }

    func updateEngineerRequestStatus(
        studioId: String,
        engineerId: String,
        status: StudioEngineerRequest.Status
    ) async throws {
        guard var requests = studioEngineerRequests[studioId],
              let index = requests.firstIndex(where: { $0.engineerId == engineerId }) else {
            throw FirestoreServiceError.engineerRequestNotFound
        }

        var request = requests[index]
        request.status = status
        request.updatedAt = Date()
        requests[index] = request
        studioEngineerRequests[studioId] = requests

        if let studioIndex = storedStudios.firstIndex(where: { $0.id == studioId }) {
            var studio = storedStudios[studioIndex]
            switch status {
            case .accepted:
                if studio.approvedEngineerIds.contains(engineerId) == false {
                    studio.approvedEngineerIds.append(engineerId)
                }
            case .denied, .pending:
                studio.approvedEngineerIds.removeAll { $0 == engineerId }
            }
            storedStudios[studioIndex] = studio
            notifyStudioStreams()
        }
    }

    func fetchEngineerRequests(studioId: String) async throws -> [StudioEngineerRequest] {
        let requests = studioEngineerRequests[studioId] ?? []
        return requests.sorted { $0.createdAt < $1.createdAt }
    }

    func fetchUserProfiles(for userIDs: [String]) async throws -> [UserProfile] {
        userIDs.compactMap { storedProfiles[$0] }
    }

    private func notifyStudioStreams() {
        for continuation in studioStreams.values {
            continuation.yield(storedStudios)
        }
    }
}
