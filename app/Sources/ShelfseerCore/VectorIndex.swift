import Foundation

// Cosine similarity, factored out so it can be tested in isolation. Cosine
// measures the angle between two vectors (orientation), ignoring magnitude —
// the standard closeness measure for embeddings.

public enum Similarity {
    /// Cosine similarity in [-1, 1]. Returns 0 if either vector is all-zero or
    /// empty. A length mismatch is a programmer error (two vectors from
    /// different embedders/dimensions can't be compared), not a "0 similarity"
    /// — we surface it as a precondition failure rather than silently degrading
    /// to 0, which would look identical to "orthogonal / unrelated". Callers
    /// that may legitimately receive ragged input should check first; inside
    /// shelfseer every vector in an index is the same dimension by construction.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        precondition(a.count == b.count,
                     "Similarity.cosine: vector length mismatch (\(a.count) vs \(b.count)) — embedding dimensions differ")
        guard !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Non-trapping cosine for callers that may legitimately compare ragged
    /// vectors and want to detect — not crash on — a dimension mismatch.
    /// Returns `nil` when the lengths differ, so the mismatch can't masquerade
    /// as a real "0" score.
    public static func cosineChecked(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count else { return nil }
        return cosine(a, b)
    }
}

// A brute-force in-memory vector store: keep every passage's embedding, and at
// query time score them all and return the top-k. O(n) per query, which is
// plenty for a personal library (thousands of passages); an ANN index (HNSW,
// IVF) can replace this later for very large corpora without changing callers.

public final class VectorIndex: @unchecked Sendable {
    private struct Entry {
        let passage: Passage
        let vector: [Double]
    }
    private var entries: [Entry] = []
    /// The dimension every stored vector must share, learned from the first
    /// `add`. A later vector of a different length is an embedding-dimension
    /// mismatch (e.g. two embedders mixed into one index) — caught at insert
    /// time rather than silently scoring 0 at query time.
    private var dimension: Int?
    /// Serializes all access to `entries`/`dimension`. The Librarian indexes on
    /// a background task while the UI may query concurrently, so the store must
    /// be safe under concurrent add/search/removeAll.
    private let lock = NSLock()

    public init() {}

    public var count: Int { lock.withLock { entries.count } }
    public var isEmpty: Bool { lock.withLock { entries.isEmpty } }
    /// The fixed vector dimension of this index (nil until the first vector is
    /// added). Exposed so callers can validate an embedder up front.
    public var vectorDimension: Int? { lock.withLock { dimension } }

    /// Add a passage's embedding. Precondition: non-empty, and the same
    /// dimension as everything already in the index — a mismatch is a
    /// programmer error (incompatible embedders), surfaced loudly here instead
    /// of degrading to meaningless 0 scores later.
    public func add(passage: Passage, vector: [Double]) {
        precondition(!vector.isEmpty, "VectorIndex.add: empty embedding vector")
        lock.withLock {
            if let d = dimension {
                precondition(vector.count == d,
                             "VectorIndex.add: embedding dimension mismatch (got \(vector.count), index is \(d))")
            } else {
                dimension = vector.count
            }
            entries.append(Entry(passage: passage, vector: vector))
        }
    }

    public func removeAll() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            dimension = nil
        }
    }

    /// Return the `k` passages most similar to `queryVector`, highest first.
    /// `k <= 0` yields no hits. The query vector must match the index dimension;
    /// a mismatch is caught here (precondition) rather than scoring everything 0.
    public func search(queryVector: [Double], topK k: Int) -> [ScoredPassage] {
        let snapshot: [Entry]
        let dim: Int?
        (snapshot, dim) = lock.withLock { (entries, dimension) }
        guard k > 0, !snapshot.isEmpty else { return [] }
        if let dim, queryVector.count != dim {
            preconditionFailure("VectorIndex.search: query dimension \(queryVector.count) != index dimension \(dim)")
        }
        let scored = snapshot.map {
            ScoredPassage(passage: $0.passage,
                          score: Similarity.cosine(queryVector, $0.vector))
        }
        // Sort by score desc; tie-break on passage id for determinism.
        return Array(scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id
        }.prefix(k))
    }
}

// Module-internal so both VectorIndex and Librarian can serialize their shared
// mutable state through the same small helper.
extension NSLock {
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
