//
//  Punch_InTests.swift
//  Punch-InTests
//
//  Created by Thraxton on 9/21/25.
//

import Testing
@testable import Punch_In

struct Punch_InTests {

    @Test func instantBookingConfirmsAutomatically() async throws {
        let firestore = MockFirestoreService()
        var studio = Studio.mock()
        studio.operatingSchedule = StudioOperatingSchedule(recurringHours: [])
        studio.autoApproveRequests = true

        var engineer = UserProfile.mockEngineer
        engineer.engineerSettings = EngineerSettings(
            isPremium: true,
            instantBookEnabled: true,
            mainStudioId: studio.id,
            allowOtherStudios: false,
            mainStudioSelectedAt: Date(),
            defaultSessionDurationMinutes: 120
        )

        studio.approvedEngineerIds = [engineer.id]

        try await firestore.upsertStudio(studio)
        try await firestore.saveUserProfile(engineer)

        let bookingService = DefaultBookingService(firestore: firestore)
        let artist = UserProfile.mock
        try await firestore.saveUserProfile(artist)

        let customRoom = Room(
            id: "control-room",
            studioId: studio.id,
            name: "Control Room",
            description: "Flagship space",
            hourlyRate: 120,
            capacity: 4,
            amenities: ["Neve desk"],
            isDefault: true
        )
        try await firestore.upsertRoom(customRoom)

        let rooms = try await firestore.fetchRooms(for: studio.id)
        #expect(rooms.isEmpty == false)
        let room = rooms.first(where: { $0.id == customRoom.id }) ?? rooms[0]

        let startDate = Date().addingTimeInterval(3600)
        let request = BookingRequestInput(
            artist: artist,
            studio: studio,
            engineer: engineer,
            room: room,
            startDate: startDate,
            durationMinutes: 120,
            notes: ""
        )

        let quote = try await bookingService.quote(for: request)
        #expect(quote.isInstant)

        let booking = try await bookingService.submit(request: request)
        #expect(booking.status == .confirmed)
    }

    @Test func nonPremiumEngineerRequiresApproval() async throws {
        let firestore = MockFirestoreService()
        var studio = Studio.mock()
        studio.operatingSchedule = StudioOperatingSchedule(recurringHours: [])
        studio.autoApproveRequests = true

        var engineer = UserProfile.mockEngineer
        engineer.engineerSettings = EngineerSettings(
            isPremium: false,
            instantBookEnabled: false,
            mainStudioId: nil,
            allowOtherStudios: false,
            mainStudioSelectedAt: nil,
            defaultSessionDurationMinutes: 120
        )

        studio.approvedEngineerIds = [engineer.id]

        try await firestore.upsertStudio(studio)
        try await firestore.saveUserProfile(engineer)

        let bookingService = DefaultBookingService(firestore: firestore)
        let artist = UserProfile.mock
        try await firestore.saveUserProfile(artist)

        let customRoom = Room(
            id: "mix-room",
            studioId: studio.id,
            name: "Mix Room",
            description: "C room",
            hourlyRate: 85,
            capacity: 2,
            amenities: ["Focal monitors"],
            isDefault: true
        )
        try await firestore.upsertRoom(customRoom)

        let rooms = try await firestore.fetchRooms(for: studio.id)
        #expect(rooms.isEmpty == false)
        let room = rooms.first(where: { $0.id == customRoom.id }) ?? rooms[0]
        let startDate = Date().addingTimeInterval(3600)
        let request = BookingRequestInput(
            artist: artist,
            studio: studio,
            engineer: engineer,
            room: room,
            startDate: startDate,
            durationMinutes: 120,
            notes: ""
        )

        let quote = try await bookingService.quote(for: request)
        #expect(quote.isInstant == false)

        let booking = try await bookingService.submit(request: request)
        #expect(booking.status == .pending)
    }

}
