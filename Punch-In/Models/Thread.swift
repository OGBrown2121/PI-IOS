import Foundation

struct ChatMedia: Identifiable, Equatable {
    let id: String
    var remoteURL: URL?
    var imageData: Data?

    init(id: String = UUID().uuidString, remoteURL: URL? = nil, imageData: Data? = nil) {
        self.id = id
        self.remoteURL = remoteURL
        self.imageData = imageData
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case photo(ChatMedia, caption: String?)
    }

    let id: String
    let threadId: String
    let sender: ChatParticipant
    let sentAt: Date
    var content: Content

    init(
        id: String = UUID().uuidString,
        threadId: String,
        sender: ChatParticipant,
        sentAt: Date = Date(),
        content: Content
    ) {
        self.id = id
        self.threadId = threadId
        self.sender = sender
        self.sentAt = sentAt
        self.content = content
    }

    var previewText: String {
        switch content {
        case let .text(text):
            return text
        case let .photo(_, caption):
            guard let caption, !caption.isEmpty else { return "Photo" }
            return "Photo: \(caption)"
        }
    }
}

struct ChatThread: Identifiable, Equatable {
    enum Kind: Equatable {
        case direct
        case group
        case project

        var isGroupLike: Bool {
            switch self {
            case .direct:
                return false
            case .group, .project:
                return true
            }
        }
    }

    struct Project: Equatable {
        struct Task: Identifiable, Equatable {
            let id: String
            var title: String
            var isComplete: Bool

            init(id: String = UUID().uuidString, title: String, isComplete: Bool = false) {
                self.id = id
                self.title = title
                self.isComplete = isComplete
            }
        }

        struct FileReference: Identifiable, Equatable {
            let id: String
            var name: String
            var url: URL?
            var storagePath: String?
            var contentType: String?
            var fileSize: Int?
            var uploadedAt: Date
            var uploadedBy: ChatParticipant

            init(
                id: String = UUID().uuidString,
                name: String,
                url: URL? = nil,
                storagePath: String? = nil,
                contentType: String? = nil,
                fileSize: Int? = nil,
                uploadedAt: Date = Date(),
                uploadedBy: ChatParticipant
            ) {
                self.id = id
                self.name = name
                self.url = url
                self.storagePath = storagePath
                self.contentType = contentType
                self.fileSize = fileSize
                self.uploadedAt = uploadedAt
                self.uploadedBy = uploadedBy
            }
        }

        var title: String
        var summary: String?
        var tasks: [Task]
        var files: [FileReference]
        var sharedDriveURL: URL?
        var allowsDownloads: Bool

        init(
            title: String,
            summary: String? = nil,
            tasks: [Task] = [],
            files: [FileReference] = [],
            sharedDriveURL: URL? = nil,
            allowsDownloads: Bool = true
        ) {
            self.title = title
            self.summary = summary
            self.tasks = tasks
            self.files = files
            self.sharedDriveURL = sharedDriveURL
            self.allowsDownloads = allowsDownloads
        }

        func updatingTask(_ task: Task) -> Project {
            var copy = self
            if let index = copy.tasks.firstIndex(where: { $0.id == task.id }) {
                copy.tasks[index] = task
            } else {
                copy.tasks.append(task)
            }
            return copy
        }

        func removingTask(withId id: String) -> Project {
            var copy = self
            copy.tasks.removeAll { $0.id == id }
            return copy
        }

        func appendingFile(_ file: FileReference) -> Project {
            var copy = self
            copy.files.append(file)
            return copy
        }

        func removingFile(withId id: String) -> Project {
            var copy = self
            copy.files.removeAll { $0.id == id }
            return copy
        }
    }

    struct GroupSettings: Equatable {
        var name: String
        var photo: ChatMedia?
        var allowsParticipantEditing: Bool

        static let `default` = GroupSettings(name: "Group", photo: nil, allowsParticipantEditing: true)
    }

    let id: String
    var creatorId: String
    var participants: [ChatParticipant]
    var kind: Kind
    var groupSettings: GroupSettings?
    var lastMessageAt: Date?
    var messages: [ChatMessage]
    var project: Project?
    var mutedParticipantIds: Set<String>
    var deletedParticipantIds: Set<String>

    init(
        id: String = UUID().uuidString,
        creatorId: String,
        participants: [ChatParticipant],
        kind: Kind,
        groupSettings: GroupSettings? = nil,
        lastMessageAt: Date? = nil,
        messages: [ChatMessage] = [],
        project: Project? = nil,
        mutedParticipantIds: Set<String> = [],
        deletedParticipantIds: Set<String> = []
    ) {
        self.id = id
        self.creatorId = creatorId
        self.participants = participants
        self.kind = kind
        self.groupSettings = groupSettings
        self.lastMessageAt = lastMessageAt
        self.messages = messages
        self.project = project
        self.mutedParticipantIds = mutedParticipantIds
        self.deletedParticipantIds = deletedParticipantIds
    }

    var isGroup: Bool { kind.isGroupLike }
    var isProject: Bool {
        if case .project = kind {
            return true
        }
        return false
    }

    var allowsParticipantEditing: Bool {
        groupSettings?.allowsParticipantEditing ?? false
    }

    func canParticipantEditSettings(_ participantId: String) -> Bool {
        guard isGroup else { return false }
        if participantId == creatorId { return true }
        return allowsParticipantEditing
    }

    func displayName(currentUserId: String? = nil) -> String {
        if let settings = groupSettings, !settings.name.isEmpty {
            return settings.name
        }
        let others = participants.filter { participant in
            guard let currentUserId else { return true }
            return participant.id != currentUserId
        }
        return others.first?.displayName ?? participants.first?.displayName ?? "Conversation"
    }

    func displayImage(currentUserId: String? = nil) -> ChatMedia? {
        if let photo = groupSettings?.photo {
            return photo
        }
        let targetParticipant = participants.first { participant in
            guard let currentUserId else { return true }
            return participant.id != currentUserId
        }
        if let url = targetParticipant?.avatarURL {
            return ChatMedia(remoteURL: url)
        }
        return nil
    }

    var lastMessagePreview: String? {
        messages.last?.previewText
    }

    func updating(messages: [ChatMessage]) -> ChatThread {
        var copy = self
        copy.messages = messages
        copy.lastMessageAt = messages.last?.sentAt ?? lastMessageAt
        return copy
    }

    func updating(groupSettings: GroupSettings) -> ChatThread {
        var copy = self
        copy.groupSettings = groupSettings
        return copy
    }

    func updating(project: Project?) -> ChatThread {
        var copy = self
        copy.project = project
        return copy
    }

    func isMuted(by participantId: String?) -> Bool {
        guard let participantId else { return false }
        return mutedParticipantIds.contains(participantId)
    }

    func isDeleted(by participantId: String?) -> Bool {
        guard let participantId else { return false }
        return deletedParticipantIds.contains(participantId)
    }

    func updatingMutedParticipantIds(_ ids: Set<String>) -> ChatThread {
        var copy = self
        copy.mutedParticipantIds = ids
        return copy
    }

    func updatingDeletedParticipantIds(_ ids: Set<String>) -> ChatThread {
        var copy = self
        copy.deletedParticipantIds = ids
        return copy
    }
}

extension ChatThread {
    static let mockList: [ChatThread] = makeMockThreads()

    private static func makeMockThreads() -> [ChatThread] {
        let participants = ChatParticipant.sampleUsers
        let studios = ChatParticipant.sampleStudios
        let currentUserId = participants.first?.id ?? UUID().uuidString

        let directThreadId = UUID().uuidString
        let directMessages = [
            ChatMessage(
                threadId: directThreadId,
                sender: participants[1],
                sentAt: Date().addingTimeInterval(-3_600),
                content: .text("Hey, are you free to work on the mix tomorrow?")
            ),
            ChatMessage(
                threadId: directThreadId,
                sender: participants[0],
                sentAt: Date().addingTimeInterval(-1_200),
                content: .text("Yes! Afternoon works best for me.")
            )
        ]

        let directThread = ChatThread(
            id: directThreadId,
            creatorId: currentUserId,
            participants: [participants[0], participants[1]],
            kind: .direct,
            lastMessageAt: directMessages.last?.sentAt,
            messages: directMessages
        )

        let groupThreadId = UUID().uuidString
        let groupMessages = [
            ChatMessage(
                threadId: groupThreadId,
                sender: participants[2],
                sentAt: Date().addingTimeInterval(-8_400),
                content: .text("Here's the reference track for the vibe.")
            ),
            ChatMessage(
                threadId: groupThreadId,
                sender: participants[3],
                sentAt: Date().addingTimeInterval(-7_400),
                content: .photo(ChatMedia(remoteURL: URL(string: "https://picsum.photos/400")), caption: "Studio inspo")
            ),
            ChatMessage(
                threadId: groupThreadId,
                sender: studios[0],
                sentAt: Date().addingTimeInterval(-6_000),
                content: .text("We can book the large room for Friday evening if that still works.")
            )
        ]

        let groupThread = ChatThread(
            id: groupThreadId,
            creatorId: participants[2].id,
            participants: [participants[0], participants[2], participants[3], studios[0]],
            kind: .group,
            groupSettings: .init(
                name: "Release Session",
                photo: ChatMedia(remoteURL: URL(string: "https://picsum.photos/seed/group/200")),
                allowsParticipantEditing: true
            ),
            lastMessageAt: groupMessages.last?.sentAt,
            messages: groupMessages
        )

        let studioThreadId = UUID().uuidString
        let studioThread = ChatThread(
            id: studioThreadId,
            creatorId: participants[0].id,
            participants: [participants[0], studios[1]],
            kind: .direct,
            lastMessageAt: Date().addingTimeInterval(-12_000),
            messages: [
                ChatMessage(
                    threadId: studioThreadId,
                    sender: participants[0],
                    sentAt: Date().addingTimeInterval(-12_600),
                    content: .text("Hi! I'm looking to book a vocal booth for next week.")
                ),
                ChatMessage(
                    threadId: studioThreadId,
                    sender: studios[1],
                    sentAt: Date().addingTimeInterval(-12_000),
                    content: .text("We have availability on Wednesday and Thursday afternoons.")
                )
            ]
        )

        let projectThreadId = UUID().uuidString
        let projectCreator = participants[0]
        let projectThread = ChatThread(
            id: projectThreadId,
            creatorId: projectCreator.id,
            participants: [projectCreator, participants[2], participants[3], studios[0]],
            kind: .project,
            groupSettings: .init(
                name: "Launch Campaign",
                photo: ChatMedia(remoteURL: URL(string: "https://picsum.photos/seed/project/200")),
                allowsParticipantEditing: true
            ),
            lastMessageAt: Date().addingTimeInterval(-3_000),
            messages: [
                ChatMessage(
                    threadId: projectThreadId,
                    sender: projectCreator,
                    sentAt: Date().addingTimeInterval(-4_200),
                    content: .text("Kicking off the project thread for the release roll-out.")
                ),
                ChatMessage(
                    threadId: projectThreadId,
                    sender: participants[3],
                    sentAt: Date().addingTimeInterval(-3_400),
                    content: .text("I'll upload the artwork concepts to the files tab.")
                )
            ],
            project: .init(
                title: "Launch Campaign",
                summary: "Coordinate assets and rollout tasks for the upcoming single release.",
                tasks: [
                    .init(title: "Finalize cover art"),
                    .init(title: "Schedule teaser posts", isComplete: true),
                    .init(title: "Upload mastered WAV to drive")
                ],
                files: [
                    .init(
                        name: "Creative Brief.pdf",
                        url: URL(string: "https://example.com/files/brief.pdf"),
                        storagePath: "project-files/\(projectThreadId)/brief/CreativeBrief.pdf",
                        contentType: "application/pdf",
                        fileSize: 1_048_576,
                        uploadedAt: Date().addingTimeInterval(-8_600),
                        uploadedBy: projectCreator
                    ),
                    .init(
                        name: "Teaser Story Cut.mp4",
                        url: URL(string: "https://example.com/files/teaser.mp4"),
                        storagePath: "project-files/\(projectThreadId)/teaser/TeaserStoryCut.mp4",
                        contentType: "video/mp4",
                        fileSize: 12_582_912,
                        uploadedAt: Date().addingTimeInterval(-7_200),
                        uploadedBy: participants[3]
                    )
                ],
                sharedDriveURL: URL(string: "https://drive.example.com/project/launch"),
                allowsDownloads: true
            )
        )

        return [projectThread, groupThread, studioThread, directThread]
    }
}

extension ChatThread: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
