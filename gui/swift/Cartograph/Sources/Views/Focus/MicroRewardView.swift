import SwiftUI

struct MicroRewardView: View {
    let message: String
    let streak: Int
    @Binding var isPresented: Bool

    @State private var particles: [(id: Int, x: CGFloat, y: CGFloat, color: Color)] = []
    @State private var animate = false

    private var streakLabel: String {
        if streak >= 10 { return "\(streak) in a row! \u{1F680}" }
        if streak >= 5 { return "\(streak) in a row! \u{1F525}" }
        if streak > 1 { return "\(streak) in a row!" }
        return ""
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            ForEach(particles, id: \.id) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: animate ? p.x * 2.5 : 0,
                        y: animate ? p.y * 2.5 : 0
                    )
                    .opacity(animate ? 0 : 1)
            }

            VStack(spacing: CartographTheme.Spacing.md) {
                Text(message)
                    .font(.title2.bold())
                if !streakLabel.isEmpty {
                    Text(streakLabel)
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(CartographTheme.Spacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CartographTheme.Radius.lg))
            .scaleEffect(animate ? 1 : 0.5)
            .opacity(animate ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear {
            seedParticles()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { animate = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dismiss() }
        }
    }

    private func seedParticles() {
        let colors: [Color] = [.orange, .yellow, .green, .blue, .purple, .pink]
        particles = (0..<20).map { i in
            (id: i,
             x: CGFloat.random(in: -80...80),
             y: CGFloat.random(in: -80...80),
             color: colors[i % colors.count])
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}
