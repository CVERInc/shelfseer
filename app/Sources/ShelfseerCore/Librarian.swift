import Foundation

// The façade that ties the pipeline together: ingest → chunk → embed → index,
// then ask → embed query → retrieve → respond. The App talks only to this; it
// never touches the individual stages, so every stage stays swappable.
//
// Everything runs on-device. There is no network call anywhere in this class
// or anything it depends on — that's the whole point.

public final class Librarian {
    private let chunker: Chunker
    private let embedder: Embedder
    private let responder: Responder
    private let ingestor: Ingestor
    private let index = VectorIndex()

    /// Number of passages retrieved per question before answering.
    public var topK: Int

    public init(chunker: Chunker = ParagraphChunker(),
                embedder: Embedder = EmbedderFactory.makeDefault(),
                responder: Responder = ExtractiveResponder(),
                ingestor: Ingestor = FileIngestor(),
                topK: Int = 4) {
        self.chunker = chunker
        self.embedder = embedder
        self.responder = responder
        self.ingestor = ingestor
        self.topK = max(1, topK)
    }

    /// Passages currently indexed.
    public var passageCount: Int { index.count }
    public var isReady: Bool { !index.isEmpty }

    // MARK: - Building the index

    /// Add already-loaded Documents to the index. `onProgress(done, total)` is
    /// called as embedding proceeds so the UI can show a progress bar.
    public func index(documents: [Document],
                      onProgress: ((Int, Int) -> Void)? = nil) {
        let passages = documents.flatMap(chunker.chunk)
        let total = passages.count
        for (i, passage) in passages.enumerated() {
            let vector = embedder.embed(passage.text)
            index.add(passage: passage, vector: vector)
            onProgress?(i + 1, total)
        }
    }

    /// Read a folder of the user's documents and index them in one call.
    /// Returns the documents that were ingested. Throws only on folder read
    /// errors; individual unreadable files are skipped.
    @discardableResult
    public func ingestAndIndex(folder: URL,
                               onProgress: ((Int, Int) -> Void)? = nil) throws -> [Document] {
        let documents = try ingestor.ingest(folder: folder)
        index(documents: documents, onProgress: onProgress)
        return documents
    }

    /// Drop everything currently indexed (e.g. before re-indexing a new folder).
    public func reset() {
        index.removeAll()
    }

    // MARK: - Asking

    /// Retrieve the most relevant passages for `question` without synthesizing
    /// an answer — useful for a "find passages" mode and for tests.
    public func retrieve(_ question: String, topK k: Int? = nil) -> [ScoredPassage] {
        guard !index.isEmpty else { return [] }
        let queryVector = embedder.embed(question)
        return index.search(queryVector: queryVector, topK: k ?? topK)
    }

    /// The full RAG round-trip: retrieve, then answer.
    public func ask(_ question: String) -> Answer {
        let passages = retrieve(question)
        return responder.respond(question: question, passages: passages)
    }
}
