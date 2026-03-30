import SwiftUI

struct SessionResumeCard: View {
    let session: SessionRecord
    var onContinue: () -> Void = {}

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: CartographTheme.Spacing.md) {
                HStack {
                    Label("Continue Where You Left Off", systemImage: "bookmark.fill")
                        .font(.headline)
                    Spacer()
                    if let lastActive = session.lastActive {
                        Text(formattedTimestamp(lastActive))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(session.pathName ?? "Reading Path")
                    .font(.title3.bold())

                if let strategy = session.pathStrategy {
                    Text(strategy.capitalized)
                        .font(.caption)
                        .padding(.horizontal, CartographTheme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

                // Progress
                VStack(alignment: .leading, spacing: CartographTheme.Spacing.xs) {
                    ProgressView(value: session.progressPercent / 100.0)
                        .tint(progressColor)

                    HStack {
                        Text("Step \(session.currentStep) of \(session.totalSteps ?? 0)")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(String(format: "%.0f", session.progressPercent))%")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(progressColor)
                    }
                    .foregroundStyle(.secondary)
                }

                // Time estimate
                if let total = session.totalSteps, total > 0 {
                    let remaining = total - session.currentStep
                    let estimatedMinutes = remaining * 5  // ~5 min per step
                    HStack(spacing: CartographTheme.Spacing.xs) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("~\(formatDuration(minutes: estimatedMinutes)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onContinue) {
                    Label("Continue", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(CartographTheme.Spacing.sm)
        }
    }

    private var progressColor: Color {
        let pct = session.progressPercent
        if pct >= 75 { return .green }
        if pct >= 40 { return .orange }
        return .accentColor
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    private func formattedTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
