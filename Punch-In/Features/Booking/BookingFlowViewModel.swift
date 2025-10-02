import Foundation
import FirebaseAuth

@MainActor
final class BookingFlowViewModel: ObservableObject {
    @Published var context: BookingContext?
    @Published var isLoading = false
    @Published var loadErrorMessage: String?
    @Published var quote: BookingQuote?
    @Published var quoteErrorMessage: String?
    @Published var selectedEngineer: UserProfile?
    @Published var selectedRoom: Room?
    @Published var startDate: Date
    @Published var durationMinutes: Int
    @Published var notes: String = ""
    @Published var isSubmitting = false
    @Published var submissionErrorMessage: String?
    @Published var submittedBooking: Booking?

    let studio: Studio
    let preferredEngineerId: String?

    private let bookingService: any BookingService
    private let currentUserProvider: () -> UserProfile?

    init(
        studio: Studio,
        preferredEngineerId: String?,
        bookingService: any BookingService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.studio = studio
        self.preferredEngineerId = preferredEngineerId
        self.bookingService = bookingService
        self.currentUserProvider = currentUserProvider
        self.startDate = BookingFlowViewModel.defaultStartDate()
        self.durationMinutes = 120
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        do {
            let context = try await bookingService.loadContext(for: studio, preferredEngineerId: preferredEngineerId)
            let rooms: [Room]
            if context.rooms.isEmpty {
                if let declaredCount = studio.rooms, declaredCount > 0 {
                    rooms = (1...declaredCount).map { index in
                        Room(
                            studioId: studio.id,
                            name: "Room \(index)",
                            hourlyRate: studio.hourlyRate,
                            isDefault: index == 1
                        )
                    }
                } else {
                    rooms = [Room(
                        studioId: studio.id,
                        name: "Main Room",
                        hourlyRate: studio.hourlyRate,
                        isDefault: true
                    )]
                }
            } else {
                rooms = context.rooms
            }

            let resolvedContext = BookingContext(
                studio: context.studio,
                rooms: rooms,
                engineers: context.engineers,
                studioAvailability: context.studioAvailability
            )

            self.context = resolvedContext

            if let engineer = context.engineers.first(where: { $0.id == preferredEngineerId }) ?? context.engineers.first {
                selectedEngineer = engineer
            }
            if let firstRoom = rooms.first {
                selectedRoom = firstRoom
            }
            loadErrorMessage = nil
            await refreshQuote()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refreshQuote() async {
        guard let artist = currentUserProvider() else { return }
        guard let engineer = selectedEngineer else {
            quote = nil
            quoteErrorMessage = BookingFlowError.missingEngineer.errorDescription
            return
        }
        guard let room = selectedRoom else {
            quote = nil
            quoteErrorMessage = BookingFlowError.missingRoom.errorDescription
            return
        }

        do {
            let request = BookingRequestInput(
                artist: artist,
                studio: studio,
                engineer: engineer,
                room: room,
                startDate: startDate,
                durationMinutes: durationMinutes,
                notes: notes
            )
            let newQuote = try await bookingService.quote(for: request)
            quoteErrorMessage = nil
            quote = newQuote
        } catch {
            quote = nil
            quoteErrorMessage = error.localizedDescription
        }
    }

    func submit() async {
        guard isSubmitting == false else { return }
        guard let artist = currentUserProvider() else {
            submissionErrorMessage = "You need an account to book."
            return
        }
        guard let engineer = selectedEngineer else {
            submissionErrorMessage = BookingFlowError.missingEngineer.errorDescription
            return
        }
        guard let room = selectedRoom else {
            submissionErrorMessage = BookingFlowError.missingRoom.errorDescription
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let request = BookingRequestInput(
                artist: artist,
                studio: studio,
                engineer: engineer,
                room: room,
                startDate: startDate,
                durationMinutes: durationMinutes,
                notes: notes
            )
            #if DEBUG
            let currentUid = Auth.auth().currentUser?.uid ?? "(nil)"
            print("[BookingFlow] submit artistId=\(artist.id) currentUser=\(currentUid)")
            #endif
            let booking = try await bookingService.submit(request: request)
            submittedBooking = booking
            submissionErrorMessage = nil
        } catch {
            submissionErrorMessage = error.localizedDescription
        }
    }

    func durationOptions() -> [Int] {
        stride(from: 60, through: 6 * 60, by: 30).map { $0 }
    }

    private static func defaultStartDate() -> Date {
        let now = Date()
        let calendar = Calendar.current
        if let nextHour = calendar.date(bySettingHour: calendar.component(.hour, from: now) + 1, minute: 0, second: 0, of: now) {
            return nextHour
        }
        return now.addingTimeInterval(3600)
    }
}
