import Foundation

extension Date {
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func formattedShort() -> String {
        Self.shortFormatter.string(from: self)
    }
}
