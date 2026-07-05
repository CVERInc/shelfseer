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

    /// How many passages to retrieve per question (exposed in the UI). Kept in
    /// the valid range and pushed straight through to the librarian.
    static let topKRange: ClosedRange<Int> = 1...10
    @Published var topK: Int = 4 {
        didSet {
            let clamped = min(max(Self.topKRange.lowerBound, topK), Self.topKRange.upperBound)
            if clamped != topK { topK = clamped; return }   // re-enter once, then settle
            librarian.topK = clamped
        }
    }

    private let librarian = Librarian()

    var isIndexing: Bool {
        if case .indexing = phase { return true }
        return false
    }

    /// True while either an index build or a question is in flight. Both
    /// user-triggered actions (folder picker, ask) must check this together —
    /// otherwise starting one while the other is running hands the user a
    /// stale answer or an index built out from under an in-flight question.
    var isBusy: Bool { isIndexing || isAnswering }

    var canAsk: Bool {
        !isBusy && librarianReady && !question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var librarianReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Pick a folder and (re)build the index from it.
    func openLibrary(at folder: URL) {
        guard !isBusy else { return }
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
        guard !q.isEmpty, librarianReady, !isBusy else { return }
        isAnswering = true
        Task.detached { [librarian] in
            let result = await librarian.ask(q)
            await MainActor.run {
                self.answer = result
                self.isAnswering = false
            }
        }
    }
}
