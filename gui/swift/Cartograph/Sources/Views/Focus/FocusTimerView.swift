import SwiftUI

struct FocusTimerView: View {
    @State private var duration: TimeInterval = 15 * 60
    @State private var remaining: TimeInterval = 15 * 60
    @State private var isRunning = false
    @State private var showCompletionAlert = false
    @State private var sessionsCompleted = 0

    private let durations: [TimeInterval] = [5, 10, 15, 25, 30].map { $0 * 60 }
    private var progress: Double { duration > 0 ? remaining / duration : 0 }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private var sessionKey: String { "cartograph.focusSessions.\(dateString)" }

    var body: some View {
        VStack(spacing: CartographTheme.Spacing.xl) {
            Text("Focus Timer")
                .font(.title2.bold())

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)

                VStack(spacing: CartographTheme.Spacing.xs) {
                    Text(timeString(remaining))
                        .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                    Text(isRunning ? "Stay focused" : "Ready when you are")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)

            Picker("Duration", selection: $duration) {
                ForEach(durations, id: \.self) { d in
                    Text("\(Int(d / 60))m").tag(d)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .disabled(isRunning)
            .onChange(of: duration) { _, newVal in
                if !isRunning { remaining = newVal }
            }

            HStack(spacing: CartographTheme.Spacing.lg) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Reset") {
                    isRunning = false
                    remaining = duration
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if sessionsCompleted > 0 {
                Text("\(sessionsCompleted) session\(sessionsCompleted == 1 ? "" : "s") today")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(CartographTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { sessionsCompleted = UserDefaults.standard.integer(forKey: sessionKey) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning else { return }
            if remaining > 0 {
                remaining -= 1
            } else {
                isRunning = false
                sessionsCompleted += 1
                UserDefaults.standard.set(sessionsCompleted, forKey: sessionKey)
                showCompletionAlert = true
            }
        }
        .alert("Good stopping point!", isPresented: $showCompletionAlert) {
            Button("Continue") {
                remaining = duration
            }
        } message: {
            Text("You've completed \(sessionsCompleted) focus session\(sessionsCompleted == 1 ? "" : "s") today. Nice work!")
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
