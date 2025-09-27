import Foundation

@MainActor
final class EngineerRequestsViewModel: ObservableObject {
    struct RequestEntry: Identifiable, Equatable {
        var request: StudioEngineerRequest
        var profile: UserProfile?

        var id: String { request.id }
    }

    @Published private(set) var pending: [RequestEntry] = []
    @Published private(set) var processed: [RequestEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let studioId: String
    private let firestoreService: any FirestoreService
    @Published private var actionInFlightIDs: Set<String> = []

    init(studioId: String, firestoreService: any FirestoreService) {
        self.studioId = studioId
        self.firestoreService = firestoreService
    }

    func loadRequests(showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil

        do {
            let requests = try await firestoreService.fetchEngineerRequests(studioId: studioId)
            let profiles = try await firestoreService.fetchUserProfiles(for: requests.map(\.engineerId))
            let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            let entries = requests.map { request in
                RequestEntry(request: request, profile: profileLookup[request.engineerId])
            }

            pending = entries
                .filter { $0.request.status == .pending }
                .sorted { $0.request.createdAt < $1.request.createdAt }

            processed = entries
                .filter { $0.request.status != .pending }
                .sorted { $0.request.updatedAt > $1.request.updatedAt }
        } catch {
            pending = []
            processed = []
            errorMessage = error.localizedDescription
        }

        if showLoadingIndicator {
            isLoading = false
        }
    }

    func accept(_ entry: RequestEntry) async {
        await update(entry, to: .accepted)
    }

    func deny(_ entry: RequestEntry) async {
        await update(entry, to: .denied)
    }

    func isProcessing(_ entry: RequestEntry) -> Bool {
        actionInFlightIDs.contains(entry.id)
    }

    private func update(_ entry: RequestEntry, to status: StudioEngineerRequest.Status) async {
        guard !actionInFlightIDs.contains(entry.id) else { return }
        actionInFlightIDs.insert(entry.id)
        defer { actionInFlightIDs.remove(entry.id) }

        do {
            try await firestoreService.updateEngineerRequestStatus(
                studioId: studioId,
                engineerId: entry.request.engineerId,
                status: status
            )
            await loadRequests(showLoadingIndicator: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
