import SwiftUI

extension View {
    func fullWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    func toast(message: Binding<String?>, bottomInset: CGFloat = 24) -> some View {
        modifier(ToastModifier(message: message, bottomInset: bottomInset))
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.6)
                    )
            )
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let bottomInset: CGFloat

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if let message {
                ToastView(message: message)
                    .padding(.bottom, bottomInset)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8, blendDuration: 0.2), value: message)
    }
}
