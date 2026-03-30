import SwiftUI

struct ProgressBarView: View {
    let current: Int
    let total: Int
    let label: String?

    init(current: Int, total: Int, label: String? = nil) {
        self.current = current
        self.total = total
        self.label = label
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(current) / Double(total), 1.0)
    }

    private var percentText: String {
        let pct = Int(fraction * 100)
        return "\(pct)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CartographTheme.Spacing.xs) {
            if let label {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percentText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: CartographTheme.Radius.sm)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: CartographTheme.Radius.sm)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * fraction, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 8)

            if label == nil {
                HStack {
                    Spacer()
                    Text(percentText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
