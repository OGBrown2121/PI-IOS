import Foundation
import FirebaseFirestore
import FirebaseStorage

@MainActor
protocol ChatService {
    func fetchThreads() async throws -> [ChatThread]
    func thread(withId id: String) async throws -> ChatThread
    func createThread(
        creator: ChatParticipant,
        participants: [ChatParticipant],
        kind: ChatThread.Kind,
        groupSettings: ChatThread.GroupSettings?,
        project: ChatThread.Project?
    ) async throws -> ChatThread
    func sendMessage(
        threadId: String,
        sender: ChatParticipant,
        content: ChatMessage.Content
    ) async throws -> ChatMessage
    func updateGroupSettings(
        threadId: String,
        groupSettings: ChatThread.GroupSettings
    ) async throws -> ChatThread
    func updateProject(
        threadId: String,
        project: ChatThread.Project
    ) async throws -> ChatThread
    func setThreadMuted(threadId: String, isMuted: Bool) async throws -> ChatThread
    func deleteThread(threadId: String) async throws
    func searchParticipants(query: String, excludingIds: Set<String>) async throws -> [ChatParticipant]
}

@MainActor
final class MockChatService: ChatService {
    private var threads: [ChatThread]
    private var participants: [ChatParticipant]
    private let currentUserId: String

    init(
        participants: [ChatParticipant] = ChatParticipant.sampleAll,
        threads: [ChatThread] = ChatThread.mockList,
        currentUserId: String? = nil
    ) {
        self.participants = participants
        self.threads = threads
        if let currentUserId {
            self.currentUserId = currentUserId
        } else if let userId = participants.first?.id {
            self.currentUserId = userId
        } else if let threadOwner = threads.first?.creatorId {
            self.currentUserId = threadOwner
        } else {
            self.currentUserId = UUID().uuidString
        }
    }

    func fetchThreads() async throws -> [ChatThread] {
        threads
            .filter { !$0.deletedParticipantIds.contains(currentUserId) }
            .sorted { lhs, rhs in
            (lhs.lastMessageAt ?? .distantPast) > (rhs.lastMessageAt ?? .distantPast)
        }
    }

    func thread(withId id: String) async throws -> ChatThread {
        guard let thread = threads.first(where: { $0.id == id }) else {
            throw ChatServiceError.threadNotFound
        }
        return thread
    }

    func createThread(
        creator: ChatParticipant,
        participants: [ChatParticipant],
        kind: ChatThread.Kind,
        groupSettings: ChatThread.GroupSettings?,
        project: ChatThread.Project?
    ) async throws -> ChatThread {
        var uniqueParticipants: [ChatParticipant] = []
        var seen = Set<String>()
        for participant in participants + [creator] {
            if seen.insert(participant.id).inserted {
                uniqueParticipants.append(participant)
            }
        }

        let thread = ChatThread(
            creatorId: creator.id,
            participants: uniqueParticipants,
            kind: kind,
            groupSettings: groupSettings,
            lastMessageAt: nil,
            messages: [],
            project: project
        )
        threads.append(thread)
        return thread
    }

    func sendMessage(
        threadId: String,
        sender: ChatParticipant,
        content: ChatMessage.Content
    ) async throws -> ChatMessage {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatServiceError.threadNotFound
        }
        let message = ChatMessage(
            threadId: threadId,
            sender: sender,
            sentAt: Date(),
            content: content
        )
        threads[index].messages.append(message)
        threads[index].lastMessageAt = message.sentAt
        return message
    }

    func updateGroupSettings(
        threadId: String,
        groupSettings: ChatThread.GroupSettings
    ) async throws -> ChatThread {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatServiceError.threadNotFound
        }
        threads[index] = threads[index].updating(groupSettings: groupSettings)
        return threads[index]
    }

    func updateProject(
        threadId: String,
        project: ChatThread.Project
    ) async throws -> ChatThread {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatServiceError.threadNotFound
        }
        threads[index] = threads[index].updating(project: project)
        return threads[index]
    }

    func setThreadMuted(threadId: String, isMuted: Bool) async throws -> ChatThread {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatServiceError.threadNotFound
        }

        if isMuted {
            threads[index].mutedParticipantIds.insert(currentUserId)
        } else {
            threads[index].mutedParticipantIds.remove(currentUserId)
        }
        return threads[index]
    }

    func deleteThread(threadId: String) async throws {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatServiceError.threadNotFound
        }
        threads[index].deletedParticipantIds.insert(currentUserId)
    }

    func searchParticipants(query: String, excludingIds: Set<String>) async throws -> [ChatParticipant] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return participants.filter { !excludingIds.contains($0.id) }
        }

        let loweredQuery = query.lowercased()
        return participants.filter { participant in
            guard !excludingIds.contains(participant.id) else { return false }
            if participant.displayName.lowercased().contains(loweredQuery) {
                return true
            }
            return participant.searchableKeywords.contains { keyword in
                keyword.lowercased().contains(loweredQuery)
            }
        }
    }
}

@MainActor
final class FirestoreChatService: ChatService {
    private enum Field {
        static let conversations = "conversations"
        static let messages = "messages"
        static let participantIds = "participantIds"
        static let participants = "participants"
        static let creatorId = "creatorId"
        static let kind = "kind"
        static let groupSettings = "groupSettings"
        static let mutedParticipantIds = "mutedParticipantIds"
        static let deletedParticipantIds = "deletedParticipantIds"
        static let lastMessageAt = "lastMessageAt"
        static let lastMessage = "lastMessage"
        static let allowsParticipantEditing = "allowsParticipantEditing"
        static let name = "name"
        static let photo = "photo"
        static let remoteURL = "remoteURL"
        static let allowsEditing = "allowsParticipantEditing"
        static let project = "project"
        static let projectTitle = "title"
        static let projectSummary = "summary"
        static let projectSharedDriveURL = "sharedDriveURL"
        static let projectTasks = "tasks"
        static let projectFiles = "files"
        static let projectTaskId = "id"
        static let projectTaskTitle = "title"
        static let projectTaskIsComplete = "isComplete"
        static let projectFileId = "id"
        static let projectFileName = "name"
        static let projectFileURL = "url"
        static let projectFileStoragePath = "storagePath"
        static let projectFileContentType = "contentType"
        static let projectFileSize = "fileSize"
        static let projectFileUploadedAt = "uploadedAt"
        static let projectFileUploadedBy = "uploadedBy"
        static let projectAllowsDownloads = "allowsDownloads"
        static let createdAt = "createdAt"
        static let sentAt = "sentAt"
        static let sender = "sender"
        static let senderId = "senderId"
        static let contentType = "contentType"
        static let text = "text"
        static let caption = "caption"
        static let media = "media"
        static let threadId = "threadId"
        static let dataVersion = "dataVersion"
        static let type = "type"
        static let id = "id"
        static let username = "username"
        static let displayName = "displayName"
        static let accountType = "accountType"
        static let drivePlan = "drivePlan"
        static let profileImageURL = "profileImageURL"
        static let profileDetails = "profileDetails"
        static let bio = "bio"
        static let fieldOne = "fieldOne"
        static let fieldTwo = "fieldTwo"
        static let upcomingProjects = "upcomingProjects"
        static let upcomingEvents = "upcomingEvents"
        static let category = "category"
        static let detail = "detail"
        static let location = "location"
        static let callToActionTitle = "callToActionTitle"
        static let callToActionURL = "callToActionURL"
        static let scheduledAt = "scheduledAt"
        static let title = "title"
        static let city = "city"
        static let address = "address"
        static let ownerId = "ownerId"
        static let amenities = "amenities"
        static let logoImageURL = "logoImageURL"
        static let coverImageURL = "coverImageURL"
    }

    private enum ParticipantType: String {
        case user
        case studio
    }

    private enum MessageContentType: String {
        case text
        case photo
    }

    private let firestore: Firestore
    private let storage: Storage
    private let currentUserId: () -> String?
    private let dateProvider: () -> Date

    init(
        firestore: Firestore,
        storage: Storage,
        currentUserId: @escaping () -> String?,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.firestore = firestore
        self.storage = storage
        self.currentUserId = currentUserId
        self.dateProvider = dateProvider
    }

    func fetchThreads() async throws -> [ChatThread] {
        guard let userId = currentUserId() else { return [] }
        let snapshot = try await firestore
            .collection(Field.conversations)
            .whereField(Field.participantIds, arrayContains: userId)
            .order(by: Field.lastMessageAt, descending: true)
            .getDocuments()

        var threads: [ChatThread] = []
        for document in snapshot.documents {
            if let thread = try decodeThread(from: document) {
                if let userId = currentUserId(), thread.deletedParticipantIds.contains(userId) {
                    continue
                }
                threads.append(thread)
            }
        }
        return threads
    }

    func thread(withId id: String) async throws -> ChatThread {
        let doc = try await firestore.collection(Field.conversations).document(id).getDocument()
        guard let thread = try decodeThread(from: doc) else {
            throw ChatServiceError.threadNotFound
        }

        let messagesSnapshot = try await firestore
            .collection(Field.conversations)
            .document(id)
            .collection(Field.messages)
            .order(by: Field.sentAt)
            .getDocuments()

        let messages = messagesSnapshot.documents.compactMap { decodeMessage(from: $0, threadId: id) }
        return thread.updating(messages: messages)
    }

    func createThread(
        creator: ChatParticipant,
        participants: [ChatParticipant],
        kind: ChatThread.Kind,
        groupSettings: ChatThread.GroupSettings?,
        project: ChatThread.Project?
    ) async throws -> ChatThread {
        let authUserId = currentUserId() ?? creator.id

        var uniqueParticipants: [ChatParticipant] = []
        var seen = Set<String>()
        for participant in participants + [creator] {
            if seen.insert(participant.id).inserted {
                uniqueParticipants.append(participant)
            }
        }

        let normalizedParticipants: [ChatParticipant] = uniqueParticipants.map { participant in
            guard participant.id == creator.id else { return participant }
            guard case let .user(profile) = participant.kind else { return participant }
            guard profile.id != authUserId else { return participant }

            let normalizedProfile = UserProfile(
                id: authUserId,
                username: profile.username,
                displayName: profile.displayName,
                createdAt: profile.createdAt,
                profileImageURL: profile.profileImageURL,
                accountType: profile.accountType,
                profileDetails: profile.profileDetails,
                contact: profile.contact,
                engineerSettings: profile.engineerSettings,
                drivePlan: profile.drivePlan
            )
            return ChatParticipant(user: normalizedProfile)
        }

        let document = firestore.collection(Field.conversations).document()

        var finalGroupSettings = groupSettings
        var finalProject = project
        let creationGroupSettings: ChatThread.GroupSettings? = {
            guard var settings = groupSettings,
                  let media = settings.photo,
                  media.remoteURL == nil,
                  media.imageData != nil else {
                return groupSettings
            }
            settings.photo = nil
            return settings
        }()

        let participantIds = normalizedParticipants.map(\.id)

        Logger.log("Resolved auth uid: \(authUserId)")
        Logger.log("Resolved participant ids: \(participantIds)")

        var data: [String: Any] = [
            Field.creatorId: authUserId,
            Field.kind: encodeKind(kind),
            Field.participantIds: participantIds,
            Field.participants: normalizedParticipants.map(encodeParticipant(_:)),
            Field.createdAt: Timestamp(date: dateProvider()),
            Field.dataVersion: 1,
            Field.mutedParticipantIds: [],
            Field.deletedParticipantIds: []
        ]

        if let participantIdsValue = data[Field.participantIds] {
            Logger.log("participantIds value type: \(type(of: participantIdsValue))")
        }

        if let settings = creationGroupSettings {
            data[Field.groupSettings] = encodeGroupSettings(settings)
        } else {
            data[Field.groupSettings] = NSNull()
        }

        if let project {
            data[Field.project] = encodeProject(project)
        } else {
            data[Field.project] = NSNull()
        }

        Logger.log(
            "Creating conversation \(document.documentID) as \(authUserId) with participants \(participantIds.joined(separator: ",")) kind=\(encodeKind(kind))"
        )

        try await document.setData(data)

        if var settings = groupSettings,
           let media = settings.photo,
           media.remoteURL == nil,
           media.imageData != nil {
            let uploaded = try await ensureMediaUploaded(media, conversationId: document.documentID, messageId: "group-photo")
            settings.photo = uploaded
            do {
                try await document.updateData([
                    Field.groupSettings: encodeGroupSettings(settings)
                ])
                finalGroupSettings = settings
            } catch {
                Logger.log("Failed to persist uploaded group photo for conversation \(document.documentID): \(error.localizedDescription)")
            }
        }

        let thread = ChatThread(
            id: document.documentID,
            creatorId: authUserId,
            participants: normalizedParticipants,
            kind: kind,
            groupSettings: finalGroupSettings,
            lastMessageAt: nil,
            messages: [],
            project: finalProject
        )
        return thread
    }

    func sendMessage(
        threadId: String,
        sender: ChatParticipant,
        content: ChatMessage.Content
    ) async throws -> ChatMessage {
        let conversationRef = firestore.collection(Field.conversations).document(threadId)
        let messageId = UUID().uuidString
        let sentAt = dateProvider()

        let snapshot = try await conversationRef.getDocument()
        guard let conversationData = snapshot.data(), let participantIds = conversationData[Field.participantIds] as? [String] else {
            throw ChatServiceError.threadNotFound
        }

        let (contentType, payload, media) = try await encodeContent(content, conversationId: threadId, messageId: messageId)

        var data: [String: Any] = [
            Field.contentType: contentType.rawValue,
            Field.sentAt: Timestamp(date: sentAt),
            Field.sender: encodeParticipant(sender),
            Field.senderId: sender.id,
            Field.threadId: threadId,
            Field.participantIds: participantIds,
            Field.dataVersion: 1
        ]


        data.merge(payload) { $1 }

        try await conversationRef
            .collection(Field.messages)
            .document(messageId)
            .setData(data)

        let storedContent = decodeContent(type: contentType, payload: payload, media: media)
        let storedMessage = ChatMessage(
            id: messageId,
            threadId: threadId,
            sender: sender,
            sentAt: sentAt,
            content: storedContent
        )

        var lastMessagePayload = payload
        lastMessagePayload[Field.id] = messageId
        lastMessagePayload[Field.sentAt] = Timestamp(date: sentAt)
        lastMessagePayload[Field.sender] = encodeParticipant(sender)
        lastMessagePayload[Field.contentType] = contentType.rawValue

        try await conversationRef.updateData([
            Field.lastMessageAt: Timestamp(date: sentAt),
            Field.lastMessage: lastMessagePayload,
            Field.participantIds: participantIds
        ])
        return storedMessage
    }

    func updateGroupSettings(
        threadId: String,
        groupSettings: ChatThread.GroupSettings
    ) async throws -> ChatThread {
        var normalizedSettings = groupSettings
        if let photo = normalizedSettings.photo,
           photo.remoteURL == nil,
           photo.imageData != nil {
            let uploaded = try await ensureMediaUploaded(
                photo,
                conversationId: threadId,
                messageId: "group-photo-\(UUID().uuidString)"
            )
            normalizedSettings.photo = uploaded
        }

        let conversationRef = firestore.collection(Field.conversations).document(threadId)
        try await conversationRef.updateData([
            Field.groupSettings: encodeGroupSettings(normalizedSettings)
        ])

        let document = try await conversationRef.getDocument()
        guard var thread = try decodeThread(from: document) else {
            throw ChatServiceError.threadNotFound
        }
        thread = thread.updating(groupSettings: normalizedSettings)
        return thread
    }

    func updateProject(
        threadId: String,
        project: ChatThread.Project
    ) async throws -> ChatThread {
        let conversationRef = firestore.collection(Field.conversations).document(threadId)
        try await conversationRef.updateData([
            Field.project: encodeProject(project)
        ])

        let document = try await conversationRef.getDocument()
        guard var thread = try decodeThread(from: document) else {
            throw ChatServiceError.threadNotFound
        }
        thread = thread.updating(project: project)
        return thread
    }

    func setThreadMuted(threadId: String, isMuted: Bool) async throws -> ChatThread {
        guard let userId = currentUserId() else {
            throw ChatServiceError.unauthorized
        }
        let conversationRef = firestore.collection(Field.conversations).document(threadId)
        let mutation: [String: Any]
        if isMuted {
            mutation = [Field.mutedParticipantIds: FieldValue.arrayUnion([userId])]
        } else {
            mutation = [Field.mutedParticipantIds: FieldValue.arrayRemove([userId])]
        }
        try await conversationRef.updateData(mutation)

        let document = try await conversationRef.getDocument()
        guard let thread = try decodeThread(from: document) else {
            throw ChatServiceError.threadNotFound
        }
        return thread
    }

    func deleteThread(threadId: String) async throws {
        guard let userId = currentUserId() else {
            throw ChatServiceError.unauthorized
        }
        let conversationRef = firestore.collection(Field.conversations).document(threadId)
        try await conversationRef.updateData([
            Field.deletedParticipantIds: FieldValue.arrayUnion([userId])
        ])
    }

    func searchParticipants(query: String, excludingIds: Set<String>) async throws -> [ChatParticipant] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        async let profilesTask: [ChatParticipant] = searchProfiles(matching: trimmed)
        async let studiosTask: [ChatParticipant] = searchStudios(matching: trimmed)

        let results = try await profilesTask + studiosTask
        let unique = results.reduce(into: [String: ChatParticipant]()) { dict, participant in
            guard !excludingIds.contains(participant.id) else { return }
            dict[participant.id] = participant
        }
        return Array(unique.values)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Encoding helpers

    private func encodeKind(_ kind: ChatThread.Kind) -> String {
        switch kind {
        case .direct:
            return "direct"
        case .group:
            return "group"
        case .project:
            return "project"
        }
    }

    private func encodeParticipant(_ participant: ChatParticipant) -> [String: Any] {
        var base: [String: Any] = [
            Field.id: participant.id
        ]

        switch participant.kind {
        case let .user(profile):
            base[Field.type] = ParticipantType.user.rawValue
            base[Field.username] = profile.username
            base[Field.displayName] = profile.displayName
            base[Field.accountType] = profile.accountType.rawValue
            base[Field.drivePlan] = profile.drivePlan.rawValue
            base[Field.profileImageURL] = profile.profileImageURL?.absoluteString
            base[Field.createdAt] = Timestamp(date: profile.createdAt)
            let sanitizedProjects = profile.profileDetails.upcomingProjects.sanitized()
            let sanitizedEvents = profile.profileDetails.upcomingEvents.sanitized()
            base[Field.profileDetails] = [
                Field.bio: profile.profileDetails.bio,
                Field.fieldOne: profile.profileDetails.fieldOne,
                Field.fieldTwo: profile.profileDetails.fieldTwo,
                Field.upcomingProjects: sanitizedProjects.map(encodeProfileSpotlight),
                Field.upcomingEvents: sanitizedEvents.map(encodeProfileSpotlight)
            ]
        case let .studio(studio):
            base[Field.type] = ParticipantType.studio.rawValue
            base[Field.displayName] = studio.name
            base[Field.city] = studio.city
            base[Field.address] = studio.address
            base[Field.ownerId] = studio.ownerId
            base[Field.amenities] = studio.amenities
            base[Field.logoImageURL] = studio.logoImageURL?.absoluteString
            base[Field.coverImageURL] = studio.coverImageURL?.absoluteString
        }

        return base
    }

    private func encodeGroupSettings(_ settings: ChatThread.GroupSettings) -> [String: Any] {
        var payload: [String: Any] = [
            Field.name: settings.name,
            Field.allowsEditing: settings.allowsParticipantEditing
        ]
        if let media = settings.photo {
            payload[Field.photo] = encodeMedia(media)
        }
        return payload
    }

    private func encodeProject(_ project: ChatThread.Project) -> [String: Any] {
        var payload: [String: Any] = [
            Field.projectTitle: project.title,
            Field.projectTasks: project.tasks.map { task in
                [
                    Field.projectTaskId: task.id,
                    Field.projectTaskTitle: task.title,
                    Field.projectTaskIsComplete: task.isComplete
                ]
            },
            Field.projectFiles: project.files.map { file in
                var filePayload: [String: Any] = [
                    Field.projectFileId: file.id,
                    Field.projectFileName: file.name,
                    Field.projectFileUploadedAt: Timestamp(date: file.uploadedAt),
                    Field.projectFileUploadedBy: encodeParticipant(file.uploadedBy)
                ]
                if let url = file.url?.absoluteString {
                    filePayload[Field.projectFileURL] = url
                }
                if let storagePath = file.storagePath {
                    filePayload[Field.projectFileStoragePath] = storagePath
                }
                if let contentType = file.contentType {
                    filePayload[Field.projectFileContentType] = contentType
                }
                if let fileSize = file.fileSize {
                    filePayload[Field.projectFileSize] = fileSize
                }
                return filePayload
            }
        ]
        if let summary = project.summary {
            payload[Field.projectSummary] = summary
        }
        if let driveURL = project.sharedDriveURL?.absoluteString {
            payload[Field.projectSharedDriveURL] = driveURL
        }
        payload[Field.projectAllowsDownloads] = project.allowsDownloads
        return payload
    }

    private func encodeMedia(_ media: ChatMedia) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let url = media.remoteURL?.absoluteString {
            payload[Field.remoteURL] = url
        }
        if let data = media.imageData {
            payload["fallbackSize"] = data.count
        }
        return payload
    }

    private func encodeProfileSpotlight(_ item: ProfileSpotlight) -> [String: Any] {
        var payload: [String: Any] = [
            Field.id: item.id,
            Field.category: item.category.rawValue,
            Field.title: item.title,
            Field.detail: item.detail,
            Field.location: item.location,
            Field.callToActionTitle: item.callToActionTitle
        ]

        if let scheduledAt = item.scheduledAt {
            payload[Field.scheduledAt] = Timestamp(date: scheduledAt)
        }

        if let url = item.callToActionURL?.absoluteString {
            payload[Field.callToActionURL] = url
        }

        return payload
    }

    private func encodeContent(
        _ content: ChatMessage.Content,
        conversationId: String,
        messageId: String
    ) async throws -> (MessageContentType, [String: Any], ChatMedia?) {
        switch content {
        case let .text(text):
            return (.text, [Field.text: text], nil)
        case let .photo(media, caption):
            let uploadedMedia = try await ensureMediaUploaded(media, conversationId: conversationId, messageId: messageId)
            var payload: [String: Any] = [Field.media: encodeMedia(uploadedMedia)]
            if let caption, !caption.isEmpty {
                payload[Field.caption] = caption
            }
            return (.photo, payload, uploadedMedia)
        }
    }

    private func decodeContent(type: MessageContentType, payload: [String: Any], media: ChatMedia?) -> ChatMessage.Content {
        switch type {
        case .text:
            let text = payload[Field.text] as? String ?? ""
            return .text(text)
        case .photo:
            let caption = payload[Field.caption] as? String
            let mediaValue = media ?? decodeMedia(payload[Field.media]) ?? ChatMedia()
            return .photo(mediaValue, caption: caption)
        }
    }

    // MARK: - Decoding helpers

    private func decodeKind(from value: Any?) -> ChatThread.Kind {
        guard let raw = value as? String else { return .direct }
        switch raw {
        case "group":
            return .group
        case "project":
            return .project
        default:
            return .direct
        }
    }

    private func decodeThread(from document: DocumentSnapshot) throws -> ChatThread? {
        guard let data = document.data() else { return nil }
        guard let creatorId = data[Field.creatorId] as? String else { return nil }
        guard let participantPayload = data[Field.participants] as? [[String: Any]] else { return nil }
        let participants = participantPayload.compactMap(decodeParticipant(_:))
        guard !participants.isEmpty else { return nil }

        let kind = decodeKind(from: data[Field.kind])

        var settings: ChatThread.GroupSettings?
        if let settingsRaw = data[Field.groupSettings] as? [String: Any] {
            settings = decodeGroupSettings(settingsRaw)
        }
        let project = decodeProject(from: data[Field.project])

        let lastMessageAt = (data[Field.lastMessageAt] as? Timestamp)?.dateValue()

        var messages: [ChatMessage] = []
        if let lastMessageRaw = data[Field.lastMessage] as? [String: Any],
           let message = decodeMessage(from: lastMessageRaw, fallbackThreadId: document.documentID) {
            messages = [message]
        }

        let mutedIds = Set(data[Field.mutedParticipantIds] as? [String] ?? [])
        let deletedIds = Set(data[Field.deletedParticipantIds] as? [String] ?? [])

        return ChatThread(
            id: document.documentID,
            creatorId: creatorId,
            participants: participants,
            kind: kind,
            groupSettings: settings,
            lastMessageAt: lastMessageAt,
            messages: messages,
            project: project,
            mutedParticipantIds: mutedIds,
            deletedParticipantIds: deletedIds
        )
    }

    private func decodeGroupSettings(_ data: [String: Any]) -> ChatThread.GroupSettings {
        let name = data[Field.name] as? String ?? ""
        let allowsEditing = data[Field.allowsEditing] as? Bool ?? true
        var photo: ChatMedia?
        if let mediaRaw = data[Field.photo] {
            photo = decodeMedia(mediaRaw)
        }
        return ChatThread.GroupSettings(name: name, photo: photo, allowsParticipantEditing: allowsEditing)
    }

    private func decodeProject(from value: Any?) -> ChatThread.Project? {
        guard let data = value as? [String: Any] else { return nil }
        guard let title = data[Field.projectTitle] as? String, !title.isEmpty else { return nil }

        let summary = data[Field.projectSummary] as? String
        let sharedDriveURL: URL?
        if let urlString = data[Field.projectSharedDriveURL] as? String {
            sharedDriveURL = URL(string: urlString)
        } else {
            sharedDriveURL = nil
        }
        let allowsDownloads = data[Field.projectAllowsDownloads] as? Bool ?? true

        let tasks: [ChatThread.Project.Task]
        if let rawTasks = data[Field.projectTasks] as? [[String: Any]] {
            tasks = rawTasks.compactMap { rawTask in
                guard let id = rawTask[Field.projectTaskId] as? String,
                      let title = rawTask[Field.projectTaskTitle] as? String else {
                    return nil
                }
                let isComplete = rawTask[Field.projectTaskIsComplete] as? Bool ?? false
                return ChatThread.Project.Task(id: id, title: title, isComplete: isComplete)
            }
        } else {
            tasks = []
        }

        let files: [ChatThread.Project.FileReference]
        if let rawFiles = data[Field.projectFiles] as? [[String: Any]] {
            files = rawFiles.compactMap { rawFile in
                guard let id = rawFile[Field.projectFileId] as? String,
                      let name = rawFile[Field.projectFileName] as? String,
                      let uploadedAtTimestamp = rawFile[Field.projectFileUploadedAt] as? Timestamp,
                      let uploaderRaw = rawFile[Field.projectFileUploadedBy] as? [String: Any],
                      let uploader = decodeParticipant(uploaderRaw) else {
                    return nil
                }
                let url = (rawFile[Field.projectFileURL] as? String).flatMap(URL.init(string:))
                let storagePath = rawFile[Field.projectFileStoragePath] as? String
                let contentType = rawFile[Field.projectFileContentType] as? String
                let fileSize: Int?
                if let intValue = rawFile[Field.projectFileSize] as? Int {
                    fileSize = intValue
                } else if let doubleValue = rawFile[Field.projectFileSize] as? Double {
                    fileSize = Int(doubleValue)
                } else {
                    fileSize = nil
                }
                return ChatThread.Project.FileReference(
                    id: id,
                    name: name,
                    url: url,
                    storagePath: storagePath,
                    contentType: contentType,
                    fileSize: fileSize,
                    uploadedAt: uploadedAtTimestamp.dateValue(),
                    uploadedBy: uploader
                )
            }
        } else {
            files = []
        }

        return ChatThread.Project(
            title: title,
            summary: summary,
            tasks: tasks,
            files: files,
            sharedDriveURL: sharedDriveURL,
            allowsDownloads: allowsDownloads
        )
    }

    private func decodeParticipant(_ data: [String: Any]) -> ChatParticipant? {
        guard let id = data[Field.id] as? String else { return nil }
        guard let typeRaw = data[Field.type] as? String else { return nil }
        switch ParticipantType(rawValue: typeRaw) {
        case .user:
            let username = data[Field.username] as? String ?? ""
            let displayName = data[Field.displayName] as? String ?? username
            let accountTypeRaw = data[Field.accountType] as? String ?? AccountType.artist.rawValue
            let accountType = AccountType(rawValue: accountTypeRaw) ?? .artist
            let createdAt = (data[Field.createdAt] as? Timestamp)?.dateValue() ?? Date()
            let imageURL = (data[Field.profileImageURL] as? String).flatMap(URL.init(string:))
            let detailsRaw = data[Field.profileDetails] as? [String: Any] ?? [:]
            let drivePlanRaw = data[Field.drivePlan] as? String ?? UserProfile.DrivePlan.free.rawValue
            let drivePlan = UserProfile.DrivePlan(rawValue: drivePlanRaw) ?? .free
            let rawProjects = decodeProfileSpotlights(detailsRaw[Field.upcomingProjects], defaultCategory: .project)
            let rawEvents = decodeProfileSpotlights(detailsRaw[Field.upcomingEvents], defaultCategory: .event)
            let details = AccountProfileDetails(
                bio: detailsRaw[Field.bio] as? String ?? "",
                fieldOne: detailsRaw[Field.fieldOne] as? String ?? "",
                fieldTwo: detailsRaw[Field.fieldTwo] as? String ?? "",
                upcomingProjects: rawProjects.sanitized(),
                upcomingEvents: rawEvents.sanitized()
            )
            let profile = UserProfile(
                id: id,
                username: username,
                displayName: displayName,
                createdAt: createdAt,
                profileImageURL: imageURL,
                accountType: accountType,
                profileDetails: details,
                contact: UserContactInfo(),
                engineerSettings: EngineerSettings(),
                drivePlan: drivePlan
            )
            return ChatParticipant(user: profile)
        case .studio:
            let name = data[Field.displayName] as? String ?? ""
            let city = data[Field.city] as? String ?? ""
            let address = data[Field.address] as? String ?? ""
            let ownerId = data[Field.ownerId] as? String ?? ""
            let amenities = data[Field.amenities] as? [String] ?? []
            let logoURL = (data[Field.logoImageURL] as? String).flatMap(URL.init(string:))
            let coverURL = (data[Field.coverImageURL] as? String).flatMap(URL.init(string:))
            let studio = Studio(
                id: id,
                ownerId: ownerId,
                name: name,
                city: city,
                address: address,
                hourlyRate: nil,
                rooms: nil,
                amenities: amenities,
                coverImageURL: coverURL,
                logoImageURL: logoURL
            )
            return ChatParticipant(studio: studio)
        case .none:
            return nil
        }
    }

    private func decodeMedia(_ raw: Any?) -> ChatMedia? {
        guard let data = raw as? [String: Any] else { return nil }
        let url = (data[Field.remoteURL] as? String).flatMap(URL.init(string:))
        return ChatMedia(remoteURL: url)
    }

    private func decodeProfileSpotlights(
        _ raw: Any?,
        defaultCategory: ProfileSpotlight.Category
    ) -> [ProfileSpotlight] {
        guard let array = raw as? [[String: Any]] else { return [] }

        return array.compactMap { entry in
            let id = entry[Field.id] as? String ?? UUID().uuidString
            let categoryRaw = entry[Field.category] as? String ?? defaultCategory.rawValue
            let category = ProfileSpotlight.Category(rawValue: categoryRaw) ?? defaultCategory
            let title = entry[Field.title] as? String ?? ""
            let detail = entry[Field.detail] as? String ?? ""
            let location = entry[Field.location] as? String ?? ""
            let actionTitle = entry[Field.callToActionTitle] as? String ?? ""
            let actionURLString = entry[Field.callToActionURL] as? String
            let actionURL = actionURLString.flatMap(URL.init(string:))
            let timestamp = entry[Field.scheduledAt] as? Timestamp
            let scheduledAt = timestamp?.dateValue()

            return ProfileSpotlight(
                id: id,
                category: category,
                title: title,
                detail: detail,
                scheduledAt: scheduledAt,
                location: location,
                callToActionTitle: actionTitle,
                callToActionURL: actionURL
            )
        }
    }

    private func decodeMessage(from document: QueryDocumentSnapshot, threadId: String) -> ChatMessage? {
        decodeMessage(from: document.data(), fallbackThreadId: threadId, explicitId: document.documentID)
    }

    private func decodeMessage(from rawData: [String: Any], fallbackThreadId: String, explicitId: String? = nil) -> ChatMessage? {
        guard let typeRaw = rawData[Field.contentType] as? String,
              let sentAtTimestamp = rawData[Field.sentAt] as? Timestamp,
              let senderRaw = rawData[Field.sender] as? [String: Any],
              let sender = decodeParticipant(senderRaw)
        else { return nil }

        let type = MessageContentType(rawValue: typeRaw) ?? .text
        let payload = rawData
        let media = decodeMedia(rawData[Field.media])
        let content = decodeContent(type: type, payload: payload, media: media)
        let messageId = explicitId ?? rawData[Field.id] as? String ?? UUID().uuidString
        return ChatMessage(
            id: messageId,
            threadId: fallbackThreadId,
            sender: sender,
            sentAt: sentAtTimestamp.dateValue(),
            content: content
        )
    }

    private func ensureMediaUploaded(_ media: ChatMedia, conversationId: String, messageId: String) async throws -> ChatMedia {
        if let url = media.remoteURL {
            return ChatMedia(id: media.id, remoteURL: url, imageData: nil)
        }
        guard let data = media.imageData else {
            throw ChatServiceError.uploadFailed
        }

        let ref = storage.reference().child("chat-media/\(conversationId)/\(messageId)/photo.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        try await uploadData(data, to: ref, metadata: metadata)
        let url = try await downloadURL(from: ref)
        return ChatMedia(id: media.id, remoteURL: url)
    }

    private func uploadData(_ data: Data, to reference: StorageReference, metadata: StorageMetadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func downloadURL(from reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: ChatServiceError.uploadFailed)
                }
            }
        }
    }

    // MARK: - Firestore lookup helpers

    private func searchProfiles(matching query: String) async throws -> [ChatParticipant] {
        let collection = firestore.collection("users")
        let snapshot: QuerySnapshot
        if query.isEmpty {
            snapshot = try await collection.limit(to: 12).getDocuments()
        } else {
            do {
                snapshot = try await collection
                    .whereField("searchTokens", arrayContains: query)
                    .limit(to: 12)
                    .getDocuments()
            } catch {
                snapshot = try await collection.limit(to: 12).getDocuments()
            }
        }

        return snapshot.documents.compactMap { document -> ChatParticipant? in
            let data = document.data()
            let profile = mapProfile(id: document.documentID, data: data)
            return profile.map(ChatParticipant.init(user:))
        }
    }

    private func searchStudios(matching query: String) async throws -> [ChatParticipant] {
        let collection = firestore.collection("studios")
        let snapshot: QuerySnapshot
        if query.isEmpty {
            snapshot = try await collection.limit(to: 12).getDocuments()
        } else {
            do {
                snapshot = try await collection
                    .whereField("searchTokens", arrayContains: query)
                    .limit(to: 12)
                    .getDocuments()
            } catch {
                snapshot = try await collection.limit(to: 12).getDocuments()
            }
        }

        return snapshot.documents.compactMap { document -> ChatParticipant? in
            let data = document.data()
            let studio = mapStudio(documentID: document.documentID, data: data)
            return ChatParticipant(studio: studio)
        }
    }

    private func mapProfile(id: String, data: [String: Any]) -> UserProfile? {
        let createdAt = (data[Field.createdAt] as? Timestamp)?.dateValue() ?? Date()
        let username = data[Field.username] as? String ?? ""
        let displayName = data[Field.displayName] as? String ?? username
        let accountTypeRaw = data[Field.accountType] as? String ?? AccountType.artist.rawValue
        let accountType = AccountType(rawValue: accountTypeRaw) ?? .artist
        let imageURL = (data[Field.profileImageURL] as? String).flatMap(URL.init(string:))
        let detailsData = data[Field.profileDetails] as? [String: Any] ?? [:]
        let drivePlanRaw = data[Field.drivePlan] as? String ?? UserProfile.DrivePlan.free.rawValue
        let drivePlan = UserProfile.DrivePlan(rawValue: drivePlanRaw) ?? .free
        let rawProjects = decodeProfileSpotlights(detailsData[Field.upcomingProjects], defaultCategory: .project)
        let rawEvents = decodeProfileSpotlights(detailsData[Field.upcomingEvents], defaultCategory: .event)
        let details = AccountProfileDetails(
            bio: detailsData[Field.bio] as? String ?? "",
            fieldOne: detailsData[Field.fieldOne] as? String ?? "",
            fieldTwo: detailsData[Field.fieldTwo] as? String ?? "",
            upcomingProjects: rawProjects.sanitized(),
            upcomingEvents: rawEvents.sanitized()
        )

        return UserProfile(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt,
            profileImageURL: imageURL,
            accountType: accountType,
            profileDetails: details,
            contact: UserContactInfo(),
            engineerSettings: EngineerSettings(),
            drivePlan: drivePlan
        )
    }

    private func mapStudio(documentID: String, data: [String: Any]) -> Studio {
        Studio(
            id: documentID,
            ownerId: data[Field.ownerId] as? String ?? "",
            name: data[Field.displayName] as? String ?? data["name"] as? String ?? "",
            city: data[Field.city] as? String ?? "",
            address: data[Field.address] as? String ?? "",
            hourlyRate: data["hourlyRate"] as? Double,
            rooms: data["rooms"] as? Int,
            amenities: data[Field.amenities] as? [String] ?? [],
            coverImageURL: (data[Field.coverImageURL] as? String).flatMap(URL.init(string:)),
            logoImageURL: (data[Field.logoImageURL] as? String).flatMap(URL.init(string:))
        )
    }
}

enum ChatServiceError: LocalizedError {
    case threadNotFound
    case uploadFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .threadNotFound:
            return "Unable to locate this conversation."
        case .uploadFailed:
            return "We couldn't upload this file."
        case .unauthorized:
            return "You need to be signed in to manage this chat."
        }
    }
}
