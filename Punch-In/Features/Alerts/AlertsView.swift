import SwiftUI

struct AlertsView: View {
    @EnvironmentObject private var alertsCenter: AlertsCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        List {
            if alertsCenter.isLoading && alertsCenter.alerts.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if alertsCenter.alerts.isEmpty {
                ContentUnavailableView(
                    "You're all caught up",
                    systemImage: "bell.slash",
                    description: Text("We’ll notify you when something needs your attention.")
                )
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(alertsCenter.alerts) { alert in
                        Button {
                            handleAlertTap(alert)
                        } label: {
                            AlertRow(alert: alert, relativeFormatter: relativeFormatter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let errorMessage = alertsCenter.lastError {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.appBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if alertsCenter.unreadCount > 0 {
                    Button("Mark all read") {
                        Task { await alertsCenter.markAllAsRead() }
                    }
                }
            }
        }
        .task {
            if let userId = alertsCenter.currentUserId {
                alertsCenter.start(for: userId)
            }
        }
    }

    private func handleAlertTap(_ alert: AppAlert) {
        Task { await alertsCenter.markAlertAsRead(alert) }
        guard let deeplink = alert.deeplink, let url = URL(string: deeplink) else { return }
        openURL(url)
    }
}

private struct AlertRow: View {
    let alert: AppAlert
    let relativeFormatter: RelativeDateTimeFormatter

    private var relativeDateText: String {
        relativeFormatter.localizedString(for: alert.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMedium) {
            icon

            VStack(alignment: .leading, spacing: 6) {
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(relativeDateText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if alert.isUnread {
                Circle()
                    .fill(Theme.primaryColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, Theme.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: alert.category.iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.primaryGradientStart.opacity(0.9))
            )
    }
}

#if DEBUG
struct AlertsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AlertsView()
        }
        .environmentObject(AlertsCenter.preview())
    }
}
#endif
