import Foundation

protocol ReportService {
    func submitReport(_ report: UserReport) async throws
}

struct DefaultReportService: ReportService {
    private let firestore: any FirestoreService

    init(firestore: any FirestoreService) {
        self.firestore = firestore
    }

    func submitReport(_ report: UserReport) async throws {
        try await firestore.submitUserReport(report)
    }
}

final class MockReportService: ReportService {
    private(set) var submittedReports: [UserReport] = []

    func submitReport(_ report: UserReport) async throws {
        submittedReports.append(report)
    }
}
