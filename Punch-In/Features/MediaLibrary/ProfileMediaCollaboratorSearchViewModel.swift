import Foundation
import SwiftUI

@MainActor
final class ProfileMediaCollaboratorSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var collaboratorResults: [ProfileMediaCollaborator] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let firestoreService: any FirestoreService
    private var cachedStudios: [Studio] = []

    init(firestoreService: any FirestoreService) {
        self.firestoreService = firestoreService
    }

    func prepare() async {
        await refreshStudiosIfNeeded()
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            collaboratorResults = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let profiles = try await firestoreService.searchUserProfiles(matching: trimmed, limit: 16)
            var matches = profiles.map { profile in
                ProfileMediaCollaborator(
                    id: profile.id,
                    displayName: profile.displayName.isEmpty ? profile.username : profile.displayName,
                    kind: .user,
                    accountType: profile.accountType
                )
            }

            let studioMatches = cachedStudios.filter { studio in
                studio.name.lowercased().contains(trimmed.lowercased())
            }.map { studio in
                ProfileMediaCollaborator(
                    id: studio.id,
                    displayName: studio.name,
                    kind: .studio,
                    accountType: .studioOwner
                )
            }

            matches.append(contentsOf: studioMatches)
            collaboratorResults = matches
            errorMessage = nil
        } catch {
            collaboratorResults = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshStudiosIfNeeded() async {
        guard cachedStudios.isEmpty else { return }
        do {
            cachedStudios = try await firestoreService.fetchStudios()
        } catch {
            Logger.log("Failed to warm collaborator studio cache: \(error.localizedDescription)")
        }
    }
}
