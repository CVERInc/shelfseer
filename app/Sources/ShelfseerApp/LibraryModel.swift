import Foundation
import SwiftUI
import ShelfseerCore

// The App's view model: owns a Librarian, drives indexing off the main thread,
// and publishes state the UI binds to. Everything stays on-device — the model
// holds no credentials and opens no connections.

@MainActor
final class LibraryModel: ObservableObject {
    enum Phase: Equatable {
        case empty                       // no library chosen yet
        case indexing(done: Int, total: Int)
        case ready(documents: Int, passages: Int)
        case failed(String)
    }

    @Published var phase: Phase = .empty
    @Published var folderName: String = ""
    @Published var question: String = ""
    @Published var answer: Answer?
    @Published var isAnswering = false

    private let librarian = Librarian()

    var isIndexing: Bool {
        if case .indexing = phase { return true }
        return false
    }

    var canAsk: Bool {
        librarianReady && !question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var librarianReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Pick a folder and (re)build the index from it.
    func openLibrary(at folder: URL) {
        folderName = folder.lastPathComponent
        answer = nil
        phase = .indexing(done: 0, total: 0)

        Task.detached { [librarian] in
            do {
                librarian.reset()
                let documents = try librarian.ingestAndIndex(folder: folder) { done, total in
                    Task { @MainActor in self.phase = .indexing(done: done, total: total) }
                }
                let passages = librarian.passageCount
                await MainActor.run {
                    if documents.isEmpty {
                        self.phase = .failed("No .txt or .md files found in that folder.")
                    } else {
                        self.phase = .ready(documents: documents.count, passages: passages)
                    }
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Ask the current question against the indexed library.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, librarianReady else { return }
        isAnswering = true
        Task.detached { [librarian] in
            let result = librarian.ask(q)
            await MainActor.run {
                self.answer = result
                self.isAnswering = false
            }
        }
    }
}
