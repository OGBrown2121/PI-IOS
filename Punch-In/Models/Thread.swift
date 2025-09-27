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

    init(
        id: String = UUID().uuidString,
        creatorId: String,
        participants: [ChatParticipant],
        kind: Kind,
        groupSettings: GroupSettings? = nil,
        lastMessageAt: Date? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.creatorId = creatorId
        self.participants = participants
        self.kind = kind
        self.groupSettings = groupSettings
        self.lastMessageAt = lastMessageAt
        self.messages = messages
    }

    var isGroup: Bool { kind == .group }

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

        return [groupThread, studioThread, directThread]
    }
}
