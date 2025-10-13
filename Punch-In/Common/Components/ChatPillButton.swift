import SwiftUI

struct ChatPillButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                appState.isShowingChat = true
            }
        } label: {
            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 18, height: 18)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.cardBackground)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open messages")
    }
}

#if DEBUG
struct ChatPillButton_Previews: PreviewProvider {
    static var previews: some View {
        ChatPillButton()
            .environmentObject(AppState())
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
