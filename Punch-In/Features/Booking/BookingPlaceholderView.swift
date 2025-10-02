import SwiftUI

struct BookingPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Booking Coming Soon",
            systemImage: "calendar.badge.clock",
            description: Text("We'll unlock booking after owners set up availability.")
        )
    }
}

#Preview {
    BookingPlaceholderView()
}
