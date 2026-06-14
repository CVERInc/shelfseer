import Foundation
import ShelfseerCore

// Framework-free test runner: `swift run ShelfseerTests`.
// Exits non-zero on any failure so it can gate CI. Drives ShelfseerCore through
// chunking, cosine ordering, and an end-to-end retrieve on a tiny in-memory
// corpus. Uses the deterministic HashingEmbedder so results are stable offline
// and identical on every machine (no model download, no flaky CI).

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "  ✓ \(label)" : "  ✗ \(label)")
    if !condition { failures += 1 }
}

// MARK: - Chunking

print("Chunking")
do {
    let doc = Document(id: "/lib/a.md", title: "a",
                       text: "Para one.\n\nPara two.\n\nPara three.")
    let chunker = ParagraphChunker(targetChars: 12, maxChars: 40)
    let passages = chunker.chunk(doc)
    check(passages.count == 3, "blank-line split → 3 passages")
    check(passages.first?.documentTitle == "a", "passage carries document title")
    check(passages.map(\.index) == [0, 1, 2], "passages indexed in order")
    check(passages.first?.id == "/lib/a.md#0", "passage id is doc#index")
}
do {
    // Greedy packing: small paragraphs merge under the target budget.
    let doc = Document(id: "d", title: "d", text: "aa\n\nbb\n\ncc")
    let passages = ParagraphChunker(targetChars: 100, maxChars: 100).chunk(doc)
    check(passages.count == 1, "small paragraphs pack into one passage")
}
do {
    // An over-long single paragraph is hard-split below maxChars.
    let long = String(repeating: "word ", count: 60) // 300 chars
    let passages = ParagraphChunker(targetChars: 50, maxChars: 50).chunk(
        Document(id: "d", title: "d", text: long))
    check(passages.count > 1, "long paragraph hard-splits")
    check(passages.allSatisfy { $0.text.count <= 60 }, "no passage exceeds the budget")
}

// MARK: - Cosine similarity

print("Cosine similarity")
check(abs(Similarity.cosine([1, 0, 0], [1, 0, 0]) - 1.0) < 1e-9, "identical vectors → 1")
check(abs(Similarity.cosine([1, 0], [0, 1])) < 1e-9, "orthogonal vectors → 0")
check(Similarity.cosine([1, 0], [-1, 0]) < 0, "opposite vectors → negative")
check(Similarity.cosine([0, 0], [1, 1]) == 0, "zero vector → 0 (no NaN)")
do {
    // Ordering: a vector closer in angle scores higher.
    let q: [Double] = [1, 1, 0]
    let near = Similarity.cosine(q, [1, 0.9, 0])
    let far  = Similarity.cosine(q, [0, 0, 1])
    check(near > far, "nearer vector scores above farther one")
}

// MARK: - VectorIndex top-k ordering

print("VectorIndex")
do {
    let index = VectorIndex()
    func p(_ n: Int) -> Passage {
        Passage(id: "p\(n)", documentID: "d", documentTitle: "d", index: n, text: "p\(n)")
    }
    index.add(passage: p(1), vector: [1, 0, 0])
    index.add(passage: p(2), vector: [0.9, 0.1, 0])
    index.add(passage: p(3), vector: [0, 0, 1])
    let hits = index.search(queryVector: [1, 0, 0], topK: 2)
    check(hits.count == 2, "topK caps result count")
    check(hits.map { $0.passage.id } == ["p1", "p2"], "results ranked by similarity")
    check(hits[0].score >= hits[1].score, "scores are descending")
    check(VectorIndex().search(queryVector: [1, 0], topK: 3).isEmpty, "empty index → no hits")
}

// MARK: - End-to-end retrieval (Librarian)

print("End-to-end retrieval")
do {
    // Deterministic embedder so this is stable in CI / offline.
    let librarian = Librarian(chunker: ParagraphChunker(targetChars: 200, maxChars: 400),
                              embedder: HashingEmbedder(dimension: 512),
                              responder: ExtractiveResponder(maxPassages: 1),
                              topK: 3)
    let corpus = [
        Document(id: "cooking", title: "Cooking",
                 text: "To bake sourdough bread you need flour, water, salt and a wild yeast starter."),
        Document(id: "space", title: "Space",
                 text: "The planet Mars is the fourth planet from the Sun and is often called the red planet."),
        Document(id: "music", title: "Music",
                 text: "A violin is a wooden string instrument played with a bow held in the right hand."),
    ]
    librarian.index(documents: corpus)
    check(librarian.isReady, "librarian reports ready after indexing")
    check(librarian.passageCount == 3, "one passage per short document")

    let hits = librarian.retrieve("how do I make bread with flour and yeast?")
    check(hits.first?.passage.documentID == "cooking", "bread query retrieves the cooking doc first")

    let mars = librarian.retrieve("which planet is red?")
    check(mars.first?.passage.documentID == "space", "planet query retrieves the space doc first")

    let answer = librarian.ask("how do I make sourdough bread?")
    check(answer.text.contains("sourdough"), "answer is grounded in the source text")
    check(answer.sources.first?.passage.documentID == "cooking", "answer cites the right source")
}
do {
    // A query against an empty library degrades gracefully, no crash.
    let answer = Librarian(embedder: HashingEmbedder()).ask("anything?")
    check(answer.sources.isEmpty, "empty library → no sources")
    check(!answer.text.isEmpty, "empty library → a helpful message, not a crash")
}

print(failures == 0 ? "\n✅ all ShelfseerCore tests passed" : "\n❌ \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
