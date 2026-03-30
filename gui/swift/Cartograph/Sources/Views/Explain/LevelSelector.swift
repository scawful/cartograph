import SwiftUI

// MARK: - Level Selector

struct LevelSelector: View {
    @Binding var level: String

    private let levels = ["beginner", "intermediate", "expert"]

    var body: some View {
        Picker("Level", selection: $level) {
            ForEach(levels, id: \.self) { lvl in
                Text(lvl.capitalized).tag(lvl)
            }
        }
        .pickerStyle(.segmented)
    }
}
