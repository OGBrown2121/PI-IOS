import SwiftUI

struct BookingPlaceholderView: View {
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Bookings coming soon")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("We are building the booking experience. Check back again soon.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
            .padding(.bottom, 80)
        }
        .refreshable {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { showToast("Stay tuned!") }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toast(message: $toastMessage, bottomInset: 100)
        .onDisappear { toastDismissTask?.cancel() }
    }

    @MainActor
    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

#Preview {
    BookingPlaceholderView()
}
