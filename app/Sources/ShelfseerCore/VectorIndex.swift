import Foundation

// Cosine similarity, factored out so it can be tested in isolation. Cosine
// measures the angle between two vectors (orientation), ignoring magnitude —
// the standard closeness measure for embeddings.

public enum Similarity {
    /// Cosine similarity in [-1, 1]. Returns 0 if either vector is all-zero.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}

// A brute-force in-memory vector store: keep every passage's embedding, and at
// query time score them all and return the top-k. O(n) per query, which is
// plenty for a personal library (thousands of passages); an ANN index (HNSW,
// IVF) can replace this later for very large corpora without changing callers.

public final class VectorIndex {
    private struct Entry {
        let passage: Passage
        let vector: [Double]
    }
    private var entries: [Entry] = []

    public init() {}

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public func add(passage: Passage, vector: [Double]) {
        entries.append(Entry(passage: passage, vector: vector))
    }

    public func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Return the `k` passages most similar to `queryVector`, highest first.
    public func search(queryVector: [Double], topK k: Int) -> [ScoredPassage] {
        guard k > 0, !entries.isEmpty else { return [] }
        let scored = entries.map {
            ScoredPassage(passage: $0.passage,
                          score: Similarity.cosine(queryVector, $0.vector))
        }
        // Sort by score desc; tie-break on passage id for determinism.
        return Array(scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id
        }.prefix(k))
    }
}
