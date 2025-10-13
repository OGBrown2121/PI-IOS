import SwiftUI

struct AlertsButton: View {
    @EnvironmentObject private var alertsCenter: AlertsCenter
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: alertsCenter.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(alertsCenter.unreadCount > 0 ? Theme.primaryColor : Color.primary)

                if alertsCenter.unreadCount > 0 {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, alertsCenter.unreadCount > 9 ? 5 : 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .offset(x: 10, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alertsCenter.unreadCount > 0 ? "\(alertsCenter.unreadCount) unread alerts" : "Notifications")
    }

    private var badgeText: String {
        let count = alertsCenter.unreadCount
        return count > 99 ? "99+" : "\(count)"
    }
}

#if DEBUG
struct AlertsButton_Previews: PreviewProvider {
    static var previews: some View {
        AlertsButton(action: {})
            .environmentObject(AlertsCenter.preview())
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
#endif
