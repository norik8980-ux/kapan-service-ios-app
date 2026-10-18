import SwiftUI

/// Bottom-bar slide control for field status actions (start / finished; arrival is automatic).
struct SlideToActControl: View {
    let title: String
    var tint: Color = KapanTheme.orange
    var systemImage: String = "chevron.right.2"
    var disabled: Bool = false
    let action: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0
    @State private var completing = false
    @State private var resetToken = 0

    private let thumbSize: CGFloat = 52
    private let inset: CGFloat = 4

    private var maxOffset: CGFloat {
        max(0, trackWidth - thumbSize - inset * 2)
    }

    private var progress: CGFloat {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, dragOffset / maxOffset))
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(tint.opacity(disabled || completing ? 0.35 : 0.92))

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.92 - Double(progress) * 0.55))
                .padding(.horizontal, thumbSize + 8)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack {
                ZStack {
                    Circle()
                        .fill(.white)
                        .shadow(color: KapanTheme.ink.opacity(0.18), radius: 6, y: 2)
                    if completing {
                        ProgressView()
                            .tint(tint)
                    } else {
                        Image(systemName: systemImage)
                            .font(.body.weight(.bold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .offset(x: dragOffset)
                .gesture(disabled || completing ? nil : drag)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
        }
        .frame(height: thumbSize + inset * 2)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { trackWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in trackWidth = w }
            }
        )
        .opacity(disabled ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? "Unavailable" : "Swipe right to confirm")
        .accessibilityAction {
            guard !disabled, !completing else { return }
            Task { await complete() }
        }
        .id(resetToken)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !disabled, !completing else { return }
                dragOffset = min(maxOffset, max(0, value.translation.width))
            }
            .onEnded { _ in
                guard !disabled, !completing else { return }
                if progress >= 0.82 {
                    dragOffset = maxOffset
                    Task { await complete() }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func complete() async {
        completing = true
        await action()
        completing = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            dragOffset = 0
        }
        resetToken += 1
    }
}
