import FirebaseFirestore
import Foundation

enum FirestoreServiceError: LocalizedError {
    case engineerAlreadyMember
    case engineerRequestNotFound
    case bookingConflict
    case roomNotFound
    case availabilityNotFound

    var errorDescription: String? {
        switch self {
        case .engineerAlreadyMember:
            return "This engineer is already approved to work at this studio."
        case .engineerRequestNotFound:
            return "We couldn't find that request anymore."
        case .bookingConflict:
            return "That time is no longer available. Please pick a different slot."
        case .roomNotFound:
            return "We couldn't find that room."
        case .availabilityNotFound:
            return "We couldn't locate the availability entry."
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

    func fetchRooms(for studioId: String) async throws -> [Room]
    func upsertRoom(_ room: Room) async throws
    func deleteRoom(roomId: String, studioId: String) async throws

    func fetchAvailability(scope: AvailabilityScope, ownerId: String) async throws -> [AvailabilityEntry]
    func upsertAvailability(scope: AvailabilityScope, entry: AvailabilityEntry) async throws
    func deleteAvailability(scope: AvailabilityScope, ownerId: String, entryId: String) async throws

    func fetchBookings(for participantId: String, role: BookingParticipantRole) async throws -> [Booking]
    func createBooking(_ booking: Booking) async throws
    func updateBooking(_ booking: Booking) async throws

    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review]
    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review]
    func upsertReview(_ review: Review) async throws
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

        data["autoApproveRequests"] = studio.autoApproveRequests

        if studio.operatingSchedule.recurringHours.isEmpty && studio.operatingSchedule.blackoutDates.isEmpty {
            data["operatingSchedule"] = FieldValue.delete()
        } else {
            data["operatingSchedule"] = encodeOperatingSchedule(studio.operatingSchedule)
        }

        try await database.collection("studios")
            .document(studio.id)
            .setData(data, merge: true)
    }

    func loadUserProfile(for userID: String) async throws -> UserProfile? {
        let document = try await database.collection("users").document(userID).getDocument()
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

        data["contact"] = [
            "email": profile.contact.email,
            "phoneNumber": profile.contact.phoneNumber
        ]

        var engineerSettingsData: [String: Any] = [
            "isPremium": profile.engineerSettings.isPremium,
            "instantBookEnabled": profile.engineerSettings.instantBookEnabled,
            "allowOtherStudios": profile.engineerSettings.allowOtherStudios,
            "defaultSessionDurationMinutes": profile.engineerSettings.defaultSessionDurationMinutes
        ]

        if let mainStudioId = profile.engineerSettings.mainStudioId {
            engineerSettingsData["mainStudioId"] = mainStudioId
        }

        if let mainStudioSelectedAt = profile.engineerSettings.mainStudioSelectedAt {
            engineerSettingsData["mainStudioSelectedAt"] = Timestamp(date: mainStudioSelectedAt)
        }

        data["engineerSettings"] = engineerSettingsData

        if let profileImageURL = profile.profileImageURL?.absoluteString {
            data["profileImageURL"] = profileImageURL
        } else {
            data["profileImageURL"] = FieldValue.delete()
        }

        try await database.collection("users").document(profile.id).setData(data, merge: true)
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
                .collection("users")
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

    func fetchRooms(for studioId: String) async throws -> [Room] {
        let snapshot = try await database
            .collection("studios")
            .document(studioId)
            .collection("rooms")
            .order(by: "name")
            .getDocuments()

        return snapshot.documents.map { decodeRoom(studioId: studioId, documentID: $0.documentID, data: $0.data()) }
    }

    func upsertRoom(_ room: Room) async throws {
        let reference = database
            .collection("studios")
            .document(room.studioId)
            .collection("rooms")
            .document(room.id)

        try await reference.setData(encodeRoom(room), merge: true)
    }

    func deleteRoom(roomId: String, studioId: String) async throws {
        let reference = database
            .collection("studios")
            .document(studioId)
            .collection("rooms")
            .document(roomId)
        try await reference.delete()
    }

    func fetchAvailability(scope: AvailabilityScope, ownerId: String) async throws -> [AvailabilityEntry] {
        let snapshot = try await availabilityCollection(scope: scope, ownerId: ownerId)
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.map { decodeAvailability(scope: scope, ownerId: ownerId, documentID: $0.documentID, data: $0.data()) }
    }

    func upsertAvailability(scope: AvailabilityScope, entry: AvailabilityEntry) async throws {
        let reference = availabilityCollection(scope: scope, ownerId: entry.ownerId)
            .document(entry.id)
        try await reference.setData(encodeAvailability(entry), merge: true)
    }

    func deleteAvailability(scope: AvailabilityScope, ownerId: String, entryId: String) async throws {
        let reference = availabilityCollection(scope: scope, ownerId: ownerId)
            .document(entryId)
        try await reference.delete()
    }

    func fetchBookings(for participantId: String, role: BookingParticipantRole) async throws -> [Booking] {
        let collection = database.collection("bookings")
        let query: Query
        switch role {
        case .artist:
            query = collection.whereField("artistId", isEqualTo: participantId)
        case .studio:
            query = collection.whereField("studioId", isEqualTo: participantId)
        case .engineer:
            query = collection.whereField("engineerId", isEqualTo: participantId)
        }

        let snapshot = try await query.order(by: "requestedStart", descending: false).getDocuments()
        return snapshot.documents.map { decodeBooking(documentID: $0.documentID, data: $0.data()) }
    }

    func createBooking(_ booking: Booking) async throws {
        let reference = database.collection("bookings").document(booking.id)
        let payload = encodeBooking(booking)
#if DEBUG
        print("[FirestoreService] createBooking payload:", payload)
        print("[FirestoreService] createBooking field types:", [
            "requestedStart": typeDescription(payload["requestedStart"]),
            "requestedEnd": typeDescription(payload["requestedEnd"]),
            "createdAt": typeDescription(payload["createdAt"]),
            "updatedAt": typeDescription(payload["updatedAt"])
        ])
#endif
        try await reference.setData(payload)
    }

    func updateBooking(_ booking: Booking) async throws {
        let reference = database.collection("bookings").document(booking.id)
        var payload = encodeBooking(booking)

        if booking.confirmedStart == nil {
            payload["confirmedStart"] = NSNull()
        }

        if booking.confirmedEnd == nil {
            payload["confirmedEnd"] = NSNull()
        }

        if var approval = payload["approval"] as? [String: Any] {
            if booking.approval.resolvedBy == nil {
                approval["resolvedBy"] = NSNull()
            }
            if booking.approval.resolvedAt == nil {
                approval["resolvedAt"] = NSNull()
            }
            payload["approval"] = approval
        }
#if DEBUG
        print("[FirestoreService] updateBooking payload:", payload)
        print("[FirestoreService] updateBooking field types:", [
            "requestedStart": typeDescription(payload["requestedStart"]),
            "requestedEnd": typeDescription(payload["requestedEnd"]),
            "createdAt": typeDescription(payload["createdAt"]),
            "updatedAt": typeDescription(payload["updatedAt"]),
            "confirmedStart": typeDescription(payload["confirmedStart"]),
            "confirmedEnd": typeDescription(payload["confirmedEnd"])
        ])
#endif
        try await reference.setData(payload, merge: true)
    }

    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review] {
        let snapshot = try await database
            .collection("reviews")
            .whereField("revieweeId", isEqualTo: revieweeId)
            .whereField("revieweeKind", isEqualTo: kind.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { decodeReview(documentID: $0.documentID, data: $0.data()) }
    }

    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review] {
        let snapshot = try await database
            .collection("reviews")
            .whereField("reviewerId", isEqualTo: reviewerId)
            .getDocuments()

        return snapshot.documents.compactMap { decodeReview(documentID: $0.documentID, data: $0.data()) }
    }

    func upsertReview(_ review: Review) async throws {
        var data = encodeReview(review)
        data["updatedAt"] = Timestamp(date: review.updatedAt)
        try await database.collection("reviews").document(review.id).setData(data, merge: true)
    }

    private func encodeReview(_ review: Review) -> [String: Any] {
        [
            "bookingId": review.bookingId,
            "reviewerId": review.reviewerId,
            "reviewerAccountType": review.reviewerAccountType.rawValue,
            "revieweeId": review.revieweeId,
            "revieweeKind": review.revieweeKind.rawValue,
            "rating": review.rating,
            "comment": review.comment,
            "createdAt": Timestamp(date: review.createdAt),
            "updatedAt": Timestamp(date: review.updatedAt)
        ]
    }

    private func decodeReview(documentID: String, data: [String: Any]) -> Review? {
        guard
            let bookingId = data["bookingId"] as? String,
            let reviewerId = data["reviewerId"] as? String,
            let reviewerAccountTypeRaw = data["reviewerAccountType"] as? String,
            let revieweeId = data["revieweeId"] as? String,
            let revieweeKindRaw = data["revieweeKind"] as? String,
            let reviewerAccountType = AccountType(rawValue: reviewerAccountTypeRaw),
            let revieweeKind = ReviewSubjectKind(rawValue: revieweeKindRaw)
        else {
            return nil
        }

        let rating = intValue(data["rating"]) ?? 0
        let comment = data["comment"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return Review(
            id: documentID,
            bookingId: bookingId,
            reviewerId: reviewerId,
            reviewerAccountType: reviewerAccountType,
            revieweeId: revieweeId,
            revieweeKind: revieweeKind,
            rating: rating,
            comment: comment,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeUserProfile(id: String, data: [String: Any]) -> UserProfile {
        let profileData = data["profileDetails"] as? [String: Any] ?? [:]
        let accountTypeRawValue = data["accountType"] as? String ?? AccountType.artist.rawValue
        let accountType = AccountType(rawValue: accountTypeRawValue) ?? .artist
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let username = data["username"] as? String ?? ""
        let displayName = data["displayName"] as? String ?? username
        let profileImageURL = (data["profileImageURL"] as? String).flatMap(URL.init(string:))
        let contactData = data["contact"] as? [String: Any] ?? [:]
        let engineerSettingsData = data["engineerSettings"] as? [String: Any] ?? [:]

        let details = AccountProfileDetails(
            bio: profileData["bio"] as? String ?? "",
            fieldOne: profileData["fieldOne"] as? String ?? "",
            fieldTwo: profileData["fieldTwo"] as? String ?? ""
        )

        let contact = UserContactInfo(
            email: contactData["email"] as? String ?? "",
            phoneNumber: contactData["phoneNumber"] as? String ?? ""
        )

        let engineerSettings = EngineerSettings(
            isPremium: engineerSettingsData["isPremium"] as? Bool ?? false,
            instantBookEnabled: engineerSettingsData["instantBookEnabled"] as? Bool ?? false,
            mainStudioId: engineerSettingsData["mainStudioId"] as? String,
            allowOtherStudios: engineerSettingsData["allowOtherStudios"] as? Bool ?? false,
            mainStudioSelectedAt: (engineerSettingsData["mainStudioSelectedAt"] as? Timestamp)?.dateValue(),
            defaultSessionDurationMinutes: engineerSettingsData["defaultSessionDurationMinutes"] as? Int ?? 120
        )

        return UserProfile(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt,
            profileImageURL: profileImageURL,
            accountType: accountType,
            profileDetails: details,
            contact: contact,
            engineerSettings: engineerSettings
        )
    }

    private func decodeStudio(documentID: String, data: [String: Any]) -> Studio {
        let schedule = decodeOperatingSchedule(data["operatingSchedule"] as? [String: Any])
        let autoApproveRequests = data["autoApproveRequests"] as? Bool ?? false
        return Studio(
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
            approvedEngineerIds: data["approvedEngineerIds"] as? [String] ?? [],
            operatingSchedule: schedule,
            autoApproveRequests: autoApproveRequests
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

    private func encodeOperatingSchedule(_ schedule: StudioOperatingSchedule) -> [String: Any] {
        [
            "timeZoneIdentifier": schedule.timeZoneIdentifier,
            "recurringHours": schedule.recurringHours.map { range in
                [
                    "id": range.id,
                    "weekday": range.weekday,
                    "startTimeMinutes": range.startTimeMinutes,
                    "durationMinutes": range.durationMinutes
                ]
            },
            "blackoutDates": schedule.blackoutDates.map { Timestamp(date: $0) }
        ]
    }

    private func decodeOperatingSchedule(_ payload: [String: Any]?) -> StudioOperatingSchedule {
        guard let payload else { return StudioOperatingSchedule() }
        let timeZoneIdentifier = payload["timeZoneIdentifier"] as? String ?? TimeZone.current.identifier
        let recurringHoursPayload = payload["recurringHours"] as? [[String: Any]] ?? []
        let blackoutPayload = payload["blackoutDates"] as? [Any] ?? []

        let recurringHours = recurringHoursPayload.compactMap { item -> RecurringTimeRange? in
            guard
                let weekday = item["weekday"] as? Int,
                let startTimeMinutes = item["startTimeMinutes"] as? Int,
                let durationMinutes = item["durationMinutes"] as? Int
            else { return nil }
            let identifier = item["id"] as? String ?? UUID().uuidString
            return RecurringTimeRange(
                id: identifier,
                weekday: weekday,
                startTimeMinutes: startTimeMinutes,
                durationMinutes: durationMinutes
            )
        }

        let blackoutDates = blackoutPayload.compactMap { value -> Date? in
            if let timestamp = value as? Timestamp {
                return timestamp.dateValue()
            }
            if let date = value as? Date {
                return date
            }
            return nil
        }

        return StudioOperatingSchedule(
            timeZoneIdentifier: timeZoneIdentifier,
            recurringHours: recurringHours,
            blackoutDates: blackoutDates
        )
    }

    private func availabilityCollection(scope: AvailabilityScope, ownerId: String) -> CollectionReference {
        switch scope {
        case .studio:
            return database.collection("studios").document(ownerId).collection("availability")
        case .engineer:
            return database.collection("users").document(ownerId).collection("availability")
        }
    }

    private func encodeRoom(_ room: Room) -> [String: Any] {
        var data: [String: Any] = [
            "name": room.name,
            "description": room.description,
            "amenities": room.amenities,
            "isDefault": room.isDefault
        ]

        if let hourlyRate = room.hourlyRate {
            data["hourlyRate"] = hourlyRate
        }

        if let capacity = room.capacity {
            data["capacity"] = capacity
        }

        return data
    }

    private func decodeRoom(studioId: String, documentID: String, data: [String: Any]) -> Room {
        Room(
            id: documentID,
            studioId: studioId,
            name: data["name"] as? String ?? "Room",
            description: data["description"] as? String ?? "",
            hourlyRate: data["hourlyRate"] as? Double,
            capacity: data["capacity"] as? Int,
            amenities: data["amenities"] as? [String] ?? [],
            isDefault: data["isDefault"] as? Bool ?? false
        )
    }

    private func encodeAvailability(_ entry: AvailabilityEntry) -> [String: Any] {
        var data: [String: Any] = [
            "kind": entry.kind.rawValue,
            "ownerId": entry.ownerId,
            "durationMinutes": entry.durationMinutes,
            "createdBy": entry.createdBy,
            "createdAt": Timestamp(date: entry.createdAt),
            "updatedAt": Timestamp(date: entry.updatedAt)
        ]

        if let studioId = entry.studioId {
            data["studioId"] = studioId
        }

        if let roomId = entry.roomId {
            data["roomId"] = roomId
        }

        if let engineerId = entry.engineerId {
            data["engineerId"] = engineerId
        }

        if let weekday = entry.weekday {
            data["weekday"] = weekday
        }

        if let startTimeMinutes = entry.startTimeMinutes {
            data["startTimeMinutes"] = startTimeMinutes
        }

        if let startDate = entry.startDate {
            data["startDate"] = Timestamp(date: startDate)
        }

        if let endDate = entry.endDate {
            data["endDate"] = Timestamp(date: endDate)
        }

        if let sourceBookingId = entry.sourceBookingId {
            data["sourceBookingId"] = sourceBookingId
        }

        if let notes = entry.notes {
            data["notes"] = notes
        }

        return data
    }

    private func decodeAvailability(
        scope: AvailabilityScope,
        ownerId: String,
        documentID: String,
        data: [String: Any]
    ) -> AvailabilityEntry {
        let kindRaw = data["kind"] as? String ?? AvailabilityKind.recurring.rawValue
        let startDate = (data["startDate"] as? Timestamp)?.dateValue()
        let endDate = (data["endDate"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return AvailabilityEntry(
            id: documentID,
            kind: AvailabilityKind(rawValue: kindRaw) ?? .recurring,
            ownerId: ownerId,
            studioId: data["studioId"] as? String,
            roomId: data["roomId"] as? String,
            engineerId: data["engineerId"] as? String,
            weekday: intValue(data["weekday"]),
            startTimeMinutes: intValue(data["startTimeMinutes"]),
            durationMinutes: intValue(data["durationMinutes"]) ?? 60,
            startDate: startDate,
            endDate: endDate,
            sourceBookingId: data["sourceBookingId"] as? String,
            createdBy: data["createdBy"] as? String ?? ownerId,
            notes: data["notes"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func encodeBooking(_ booking: Booking) -> [String: Any] {
        var approval: [String: Any] = [
            "requiresStudioApproval": booking.approval.requiresStudioApproval,
            "requiresEngineerApproval": booking.approval.requiresEngineerApproval
        ]

        if let resolvedBy = booking.approval.resolvedBy {
            approval["resolvedBy"] = resolvedBy
        }

        if let resolvedAt = booking.approval.resolvedAt {
            approval["resolvedAt"] = Timestamp(date: resolvedAt)
        }

        var data: [String: Any] = [
            "artistId": booking.artistId,
            "studioId": booking.studioId,
            "roomId": booking.roomId,
            "engineerId": booking.engineerId,
            "status": booking.status.rawValue,
            "requestedStart": Timestamp(date: booking.requestedStart),
            "requestedEnd": Timestamp(date: booking.requestedEnd),
            "durationMinutes": booking.durationMinutes,
            "instantBook": booking.instantBook,
            "approval": approval,
            "notes": booking.notes,
            "createdAt": Timestamp(date: booking.createdAt),
            "updatedAt": Timestamp(date: booking.updatedAt)
        ]

        if let confirmedStart = booking.confirmedStart {
            data["confirmedStart"] = Timestamp(date: confirmedStart)
        }

        if let confirmedEnd = booking.confirmedEnd {
            data["confirmedEnd"] = Timestamp(date: confirmedEnd)
        }

        if let pricing = booking.pricing {
            data["pricing"] = [
                "hourlyRate": pricing.hourlyRate,
                "total": pricing.total,
                "currency": pricing.currency
            ]
        }

        if let conversationId = booking.conversationId {
            data["conversationId"] = conversationId
        }

        return data
    }

    private func decodeBooking(documentID: String, data: [String: Any]) -> Booking {
        let statusRaw = data["status"] as? String ?? BookingStatus.pending.rawValue
        let approvalData = data["approval"] as? [String: Any] ?? [:]
        let pricingData = data["pricing"] as? [String: Any]

        let approval = BookingApprovalState(
            requiresStudioApproval: approvalData["requiresStudioApproval"] as? Bool ?? true,
            requiresEngineerApproval: approvalData["requiresEngineerApproval"] as? Bool ?? true,
            resolvedBy: approvalData["resolvedBy"] as? String,
            resolvedAt: (approvalData["resolvedAt"] as? Timestamp)?.dateValue()
        )

        let pricing: BookingPricing?
        if let pricingData {
            pricing = BookingPricing(
                hourlyRate: pricingData["hourlyRate"] as? Double ?? 0,
                total: pricingData["total"] as? Double ?? 0,
                currency: pricingData["currency"] as? String ?? "USD"
            )
        } else {
            pricing = nil
        }

        return Booking(
            id: documentID,
            artistId: data["artistId"] as? String ?? "",
            studioId: data["studioId"] as? String ?? "",
            roomId: data["roomId"] as? String ?? "",
            engineerId: data["engineerId"] as? String ?? "",
            status: BookingStatus(rawValue: statusRaw) ?? .pending,
            requestedStart: (data["requestedStart"] as? Timestamp)?.dateValue() ?? Date(),
            requestedEnd: (data["requestedEnd"] as? Timestamp)?.dateValue() ?? Date(),
            confirmedStart: (data["confirmedStart"] as? Timestamp)?.dateValue(),
            confirmedEnd: (data["confirmedEnd"] as? Timestamp)?.dateValue(),
            durationMinutes: intValue(data["durationMinutes"]) ?? 60,
            pricing: pricing,
            instantBook: data["instantBook"] as? Bool ?? false,
            approval: approval,
            conversationId: data["conversationId"] as? String,
            notes: data["notes"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let intValue = raw as? Int {
            return intValue
        }
        if let doubleValue = raw as? Double {
            return Int(doubleValue)
        }
        if let stringValue = raw as? String, let intFromString = Int(stringValue) {
            return intFromString
        }
        return nil
    }

#if DEBUG
    private func typeDescription(_ value: Any?) -> String {
        guard let value else { return "nil" }
        return String(describing: Swift.type(of: value))
    }
#endif

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
    private var studioRooms: [String: [Room]] = [:]
    private var studioAvailabilityStore: [String: [AvailabilityEntry]] = [:]
    private var engineerAvailabilityStore: [String: [AvailabilityEntry]] = [:]
    private var bookingsStore: [String: Booking] = [:]
    private var reviewsStore: [String: Review] = [:]

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

    func fetchRooms(for studioId: String) async throws -> [Room] {
        if studioRooms[studioId] == nil {
            studioRooms[studioId] = [Room(studioId: studioId, name: "Main Room", isDefault: true)]
        }
        return studioRooms[studioId]?.sorted(by: { $0.name < $1.name }) ?? []
    }

    func upsertRoom(_ room: Room) async throws {
        var rooms = studioRooms[room.studioId] ?? []
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.append(room)
        }
        studioRooms[room.studioId] = rooms
    }

    func deleteRoom(roomId: String, studioId: String) async throws {
        var rooms = studioRooms[studioId] ?? []
        rooms.removeAll { $0.id == roomId }
        studioRooms[studioId] = rooms
    }

    func fetchAvailability(scope: AvailabilityScope, ownerId: String) async throws -> [AvailabilityEntry] {
        switch scope {
        case .studio:
            return (studioAvailabilityStore[ownerId] ?? []).sorted { $0.createdAt < $1.createdAt }
        case .engineer:
            return (engineerAvailabilityStore[ownerId] ?? []).sorted { $0.createdAt < $1.createdAt }
        }
    }

    func upsertAvailability(scope: AvailabilityScope, entry: AvailabilityEntry) async throws {
        switch scope {
        case .studio:
            var entries = studioAvailabilityStore[entry.ownerId] ?? []
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            studioAvailabilityStore[entry.ownerId] = entries
        case .engineer:
            var entries = engineerAvailabilityStore[entry.ownerId] ?? []
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            engineerAvailabilityStore[entry.ownerId] = entries
        }
    }

    func deleteAvailability(scope: AvailabilityScope, ownerId: String, entryId: String) async throws {
        switch scope {
        case .studio:
            var entries = studioAvailabilityStore[ownerId] ?? []
            entries.removeAll { $0.id == entryId }
            studioAvailabilityStore[ownerId] = entries
        case .engineer:
            var entries = engineerAvailabilityStore[ownerId] ?? []
            entries.removeAll { $0.id == entryId }
            engineerAvailabilityStore[ownerId] = entries
        }
    }

    func fetchBookings(for participantId: String, role: BookingParticipantRole) async throws -> [Booking] {
        let bookings = bookingsStore.values.filter { booking in
            switch role {
            case .artist:
                return booking.artistId == participantId
            case .studio:
                return booking.studioId == participantId
            case .engineer:
                return booking.engineerId == participantId
            }
        }

        return bookings.sorted { $0.requestedStart < $1.requestedStart }
    }

    func createBooking(_ booking: Booking) async throws {
        if hasConflict(for: booking) {
            throw FirestoreServiceError.bookingConflict
        }
        bookingsStore[booking.id] = booking
    }

    func updateBooking(_ booking: Booking) async throws {
        if hasConflict(for: booking) {
            throw FirestoreServiceError.bookingConflict
        }
        bookingsStore[booking.id] = booking
    }

    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review] {
        reviewsStore.values
            .filter { $0.revieweeId == revieweeId && $0.revieweeKind == kind }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review] {
        reviewsStore.values
            .filter { $0.reviewerId == reviewerId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func upsertReview(_ review: Review) async throws {
        reviewsStore[review.id] = review
    }

    private func hasConflict(for booking: Booking) -> Bool {
        let relevantStatuses: Set<BookingStatus> = [.pending, .confirmed, .rescheduled]
        guard relevantStatuses.contains(booking.status) else { return false }

        let targetInterval = bookingInterval(booking)

        for existing in bookingsStore.values where existing.id != booking.id {
            guard relevantStatuses.contains(existing.status) else { continue }
            guard existing.studioId == booking.studioId else { continue }

            let sameRoom = existing.roomId == booking.roomId
            let sameEngineer = existing.engineerId == booking.engineerId

            guard sameRoom || sameEngineer else { continue }

            if bookingInterval(existing).overlaps(targetInterval) {
                return true
            }
        }

        return false
    }

    private func bookingInterval(_ booking: Booking) -> ClosedRange<Date> {
        let start = booking.confirmedStart ?? booking.requestedStart
        let end = booking.confirmedEnd ?? booking.requestedEnd
        return start...end
    }

    private func notifyStudioStreams() {
        for continuation in studioStreams.values {
            continuation.yield(storedStudios)
        }
    }
}
