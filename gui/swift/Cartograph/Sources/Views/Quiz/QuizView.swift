import SwiftUI

struct QuizView: View {
    @ObservedObject var reviewStore: ReviewStore

    @State private var dueItems: [ReviewItem] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var startTime = Date()

    private var currentItem: ReviewItem? {
        currentIndex < dueItems.count ? dueItems[currentIndex] : nil
    }

    var body: some View {
        VStack(spacing: CartographTheme.Spacing.xl) {
            if dueItems.isEmpty {
                emptyState
            } else if let item = currentItem {
                questionView(item)
            } else {
                completionView
            }
        }
        .padding(CartographTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshDue() }
    }

    // MARK: - Substates

    private var emptyState: some View {
        VStack(spacing: CartographTheme.Spacing.lg) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No reviews due")
                .font(.title3.bold())
            Text("Keep reading to discover new concepts!")
                .foregroundStyle(.secondary)
        }
    }

    private var completionView: some View {
        VStack(spacing: CartographTheme.Spacing.lg) {
            Image(systemName: "party.popper")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("All caught up!")
                .font(.title3.bold())
            if let days = reviewStore.daysUntilNextReview() {
                Text("Next review in \(days) day\(days == 1 ? "" : "s").")
                    .foregroundStyle(.secondary)
            }
            Button("Refresh") { refreshDue() }
                .buttonStyle(.bordered)
        }
    }

    private func questionView(_ item: ReviewItem) -> some View {
        VStack(spacing: CartographTheme.Spacing.xl) {
            Text("Question \(currentIndex + 1) of \(dueItems.count) due today")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: CartographTheme.Spacing.md) {
                    Text(item.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.question)
                        .font(.title3)
                }
                .padding(CartographTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showAnswer {
                GroupBox {
                    Text(item.answer)
                        .font(.body)
                        .padding(CartographTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))

                HStack(spacing: CartographTheme.Spacing.lg) {
                    Button("Missed it") { answer(correct: false) }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    Button("Got it") { answer(correct: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            } else {
                Button("Show Answer") {
                    withAnimation { showAnswer = true }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 500)
    }

    // MARK: - Actions

    private func answer(correct: Bool) {
        guard let item = currentItem else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        reviewStore.recordAnswer(itemId: item.id, correct: correct, responseTime: elapsed)
        showAnswer = false
        startTime = Date()
        withAnimation { currentIndex += 1 }
    }

    private func refreshDue() {
        dueItems = reviewStore.itemsDueForReview()
        currentIndex = 0
        showAnswer = false
        startTime = Date()
    }
}
