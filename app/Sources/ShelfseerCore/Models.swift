import Foundation

// The data the RAG pipeline moves around. Deliberately tiny and value-typed:
// a Document is one source file; a Passage is one retrievable chunk of it.

/// One source document from the user's library (a .txt / .md file today; an
/// EPUB chapter tomorrow — see the EPUB ingestion TODO seam in Ingestor).
public struct Document: Identifiable, Hashable, Sendable {
    public let id: String          // stable id — the file path, typically
    public let title: String       // display name (file stem, or EPUB chapter)
    public let text: String        // full plain-text body

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// One retrievable chunk of a Document. Carries enough back-reference to cite
/// its source in an answer.
public struct Passage: Identifiable, Hashable, Sendable {
    public let id: String          // "<documentID>#<index>"
    public let documentID: String
    public let documentTitle: String
    public let index: Int          // ordinal within the document
    public let text: String

    public init(id: String, documentID: String, documentTitle: String, index: Int, text: String) {
        self.id = id
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.index = index
        self.text = text
    }
}

/// A passage paired with its similarity score against a query (0...1, higher is
/// closer). What retrieval returns and what the App renders as "sources".
public struct ScoredPassage: Identifiable, Sendable {
    public var id: String { passage.id }
    public let passage: Passage
    public let score: Double

    public init(passage: Passage, score: Double) {
        self.passage = passage
        self.score = score
    }
}

/// The result of asking the librarian a question: the synthesized answer plus
/// the passages it was grounded in (for citation / transparency).
public struct Answer: Sendable {
    public let text: String
    public let sources: [ScoredPassage]
    /// A non-fatal diagnostic to surface to the user — e.g. that the on-device
    /// LLM failed and the answer fell back to verbatim passages. `nil` on the
    /// happy path. We never silently hide a generation failure: the query still
    /// succeeds (degraded), but the user is told why the answer looks different.
    public let note: String?

    public init(text: String, sources: [ScoredPassage], note: String? = nil) {
        self.text = text
        self.sources = sources
        self.note = note
    }
}
