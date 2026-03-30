import SwiftUI

struct QuickNoteSheet: View {
    @Binding var isPresented: Bool
    let symbolName: String?
    @State private var noteText = ""

    private var notesDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cartograph")
    }

    var body: some View {
        VStack(spacing: CartographTheme.Spacing.lg) {
            HStack {
                Text("Quick Note")
                    .font(.headline)
                Spacer()
                Button("Discard") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(CartographTheme.Spacing.sm)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: CartographTheme.Radius.md))

            HStack {
                Spacer()
                Button("Save") {
                    saveNote()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(CartographTheme.Spacing.xl)
        .frame(width: 400, height: 260)
        .onAppear {
            if let name = symbolName {
                noteText = "While reading \(name): "
            }
        }
    }

    private func saveNote() {
        let fm = FileManager.default
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let file = notesDir.appendingPathComponent("notes.md")

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        let entry = "\n## \(fmt.string(from: Date()))\n\n\(noteText)\n"

        if fm.fileExists(atPath: file.path) {
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            }
        } else {
            try? ("# Cartograph Notes\n" + entry).write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
