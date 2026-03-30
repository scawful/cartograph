import Foundation

// MARK: - Model

struct ReviewItem: Identifiable, Codable {
    let id: UUID
    let symbolId: String
    let symbolName: String
    let question: String
    let answer: String
    var intervalIndex: Int = 0
    var nextReview: Date
    var lastReview: Date?
    var correctCount: Int = 0
    var totalCount: Int = 0
}

// MARK: - Spaced Repetition Logic

struct SpacedRepetitionService {
    static let intervals = [1, 3, 7, 14, 30, 90]

    static func nextReviewDate(afterReview date: Date, intervalIndex: Int) -> Date {
        let days = intervalIndex < intervals.count ? intervals[intervalIndex] : intervals.last!
        return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func reviewQuality(correct: Bool, responseTime: TimeInterval) -> Int {
        if !correct { return 0 }
        return responseTime < 10 ? 2 : 1
    }
}

// MARK: - Persistent Store

class ReviewStore: ObservableObject {
    @Published var items: [ReviewItem] = []

    private var fileURL: URL {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cartograph")
        #else
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("cartograph")
        #endif
        return dir.appendingPathComponent("reviews.json")
    }

    init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.cartograph.decode([ReviewItem].self, from: data)
        else { return }
        items = decoded
    }

    func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.cartograph.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func addItem(symbolId: String, symbolName: String, question: String, answer: String) {
        let item = ReviewItem(
            id: UUID(),
            symbolId: symbolId,
            symbolName: symbolName,
            question: question,
            answer: answer,
            nextReview: Date()
        )
        items.append(item)
        save()
    }

    func itemsDueForReview() -> [ReviewItem] {
        let now = Date()
        return items.filter { $0.nextReview <= now }
    }

    func recordAnswer(itemId: UUID, correct: Bool, responseTime: TimeInterval) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].totalCount += 1
        items[idx].lastReview = Date()
        if correct {
            items[idx].correctCount += 1
            items[idx].intervalIndex += 1
        } else {
            items[idx].intervalIndex = 0
        }
        items[idx].nextReview = SpacedRepetitionService.nextReviewDate(
            afterReview: Date(),
            intervalIndex: items[idx].intervalIndex
        )
        save()
    }

    func daysUntilNextReview() -> Int? {
        let future = items.filter { $0.nextReview > Date() }
        guard let earliest = future.min(by: { $0.nextReview < $1.nextReview }) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: earliest.nextReview).day
    }
}

// MARK: - JSON Coding Helpers

private extension JSONDecoder {
    static let cartograph: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let cartograph: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
