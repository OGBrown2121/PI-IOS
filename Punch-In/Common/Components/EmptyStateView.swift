import SwiftUI

struct EmptyStateView: View {
    let systemImageName: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.spacingSmall) {
            Image(systemName: systemImageName)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty State") {
    EmptyStateView(systemImageName: "tray", message: "No items yet.")
        .background(Color(uiColor: .systemGroupedBackground))
}
