import Foundation

protocol ReportService {
    func submitReport(_ report: UserReport) async throws
    func submitMediaReport(_ report: MediaReport) async throws
}

struct DefaultReportService: ReportService {
    private let firestore: any FirestoreService

    init(firestore: any FirestoreService) {
        self.firestore = firestore
    }

    func submitReport(_ report: UserReport) async throws {
        try await firestore.submitUserReport(report)
    }

    func submitMediaReport(_ report: MediaReport) async throws {
        try await firestore.submitMediaReport(report)
    }
}

final class MockReportService: ReportService {
    private(set) var submittedReports: [UserReport] = []
    private(set) var submittedMediaReports: [MediaReport] = []

    func submitReport(_ report: UserReport) async throws {
        submittedReports.append(report)
    }

    func submitMediaReport(_ report: MediaReport) async throws {
        submittedMediaReports.append(report)
    }
}
