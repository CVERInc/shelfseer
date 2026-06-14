import Foundation
import ShelfseerCore
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    // Use the deterministic extractive responder explicitly so the assertion is
    // stable (LLM output is non-deterministic — see the guarded smoke below).
    let answer = await librarian.ask("how do I make sourdough bread?")
    check(answer.text.contains("sourdough"), "answer is grounded in the source text")
    check(answer.sources.first?.passage.documentID == "cooking", "answer cites the right source")
}
do {
    // A query against an empty library degrades gracefully, no crash.
    let answer = await Librarian(embedder: HashingEmbedder(),
                                 responder: ExtractiveResponder()).ask("anything?")
    check(answer.sources.isEmpty, "empty library → no sources")
    check(!answer.text.isEmpty, "empty library → a helpful message, not a crash")
}

// MARK: - EPUB ingestion

print("EPUB ingestion")
do {
    // Helper parsers tested directly (no zip needed): XHTML → text + title.
    let xhtml = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head><title>Chapter One</title></head>
    <body>
      <h1>The Beginning</h1>
      <p>Call me Ishmael.</p>
      <p>Some years ago — never mind how long precisely.</p>
      <script>var hidden = "should not appear";</script>
    </body>
    </html>
    """
    let parsed = EpubIngestor.xhtmlToText(xhtml)
    check(parsed.title == "Chapter One", "XHTML <title> extracted")
    check(parsed.text.contains("Call me Ishmael."), "XHTML body text extracted")
    check(parsed.text.contains("Some years ago"), "second paragraph extracted")
    check(!parsed.text.contains("should not appear"), "<script> body is dropped")
    check(parsed.text.contains("Call me Ishmael.\n\n") || parsed.text.contains("Ishmael.\n"),
          "paragraph break preserved between <p> blocks")
}
do {
    // OPF spine parsing: idrefs resolved through the manifest, in order;
    // linear="no" items skipped.
    let opf = """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <manifest>
        <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
        <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"/>
        <item id="css" href="style.css" media-type="text/css"/>
      </manifest>
      <spine>
        <itemref idref="c1"/>
        <itemref idref="c2"/>
        <itemref idref="nav" linear="no"/>
      </spine>
    </package>
    """
    let hrefs = try! EpubIngestor.parseOPF(Data(opf.utf8),
                                           opfURL: URL(fileURLWithPath: "/tmp/content.opf"))
    check(hrefs == ["ch1.xhtml", "ch2.xhtml"],
          "spine resolves idref→href in order, skipping linear=no")
}
do {
    // container.xml → OPF path discovery.
    let container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """
    // ContainerParser is private; exercise it through a real on-disk EPUB below.
    _ = container
}
do {
    // End-to-end: build a minimal real EPUB on disk and ingest it.
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("shelfseer-test-epub-\(UUID().uuidString)")
    let oebps = root.appendingPathComponent("OEBPS")
    let metaInf = root.appendingPathComponent("META-INF")
    try! fm.createDirectory(at: oebps, withIntermediateDirectories: true)
    try! fm.createDirectory(at: metaInf, withIntermediateDirectories: true)

    try! "application/epub+zip".write(to: root.appendingPathComponent("mimetype"),
                                      atomically: true, encoding: .utf8)
    try! """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)
    try! """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Test Book</dc:title>
      </metadata>
      <manifest>
        <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="ch1"/>
      </spine>
    </package>
    """.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
    try! """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head><title>First Chapter</title></head>
    <body><h1>Whales</h1><p>The whale is a magnificent creature of the deep ocean.</p></body>
    </html>
    """.write(to: oebps.appendingPathComponent("ch1.xhtml"), atomically: true, encoding: .utf8)

    // Zip it into a real .epub (mimetype stored first, uncompressed, per spec).
    let epubURL = fm.temporaryDirectory.appendingPathComponent("shelfseer-test-\(UUID().uuidString).epub")
    func zip(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = root
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try! p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
    _ = zip(["-X", epubURL.path, "mimetype"])                 // store mimetype first
    _ = zip(["-rX", epubURL.path, "META-INF", "OEBPS"])       // add the rest

    let docs = try! EpubIngestor().ingest(epub: epubURL)
    check(docs.count == 1, "one Document per spine item")
    check(docs.first?.text.contains("magnificent creature") == true,
          "EPUB chapter text ingested")
    check(docs.first?.title == "First Chapter", "chapter title from XHTML <title>")
    check(docs.first?.id.hasSuffix("#0") == true, "document id is <epubPath>#<spineIndex>")

    // Folder-level ingestion (the Ingestor protocol surface the App uses).
    let folderDocs = try! EpubIngestor().ingest(folder: fm.temporaryDirectory)
    check(folderDocs.contains { $0.text.contains("magnificent creature") },
          "folder ingest finds the .epub")

    try? fm.removeItem(at: root)
    try? fm.removeItem(at: epubURL)
}
do {
    // Malformed EPUB throws a clear error rather than crashing.
    var threw = false
    do {
        _ = try EpubIngestor().ingest(epub: URL(fileURLWithPath: "/nonexistent/not-a.epub"))
    } catch {
        threw = true
    }
    check(threw, "missing EPUB file throws instead of crashing")
}

// MARK: - FoundationModels responder (guarded smoke)

print("FoundationModels responder")
do {
    let used = [ScoredPassage(
        passage: Passage(id: "fm#0", documentID: "fm", documentTitle: "Ocean Facts",
                         index: 0, text: "The blue whale is the largest animal known to have ever existed."),
        score: 0.99)]
    // Always: the factory returns SOME responder and it answers without crashing.
    let responder = ResponderFactory.makeDefault()
    let answer = await responder.respond(question: "What is the largest animal?", passages: used)
    check(!answer.text.isEmpty, "default responder returns a non-empty answer")
    check(!answer.sources.isEmpty, "default responder cites the grounding passages")

    // Live smoke: ONLY if Apple Intelligence is available on this machine, run a
    // real FoundationModels generation and assert it returns text. This proves
    // the on-device LLM path works here without making CI depend on it.
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        if case .available = SystemLanguageModel.default.availability,
           let fm = FoundationModelsResponder() {
            let gen = await fm.respond(question: "What is the largest animal?", passages: used)
            check(!gen.text.isEmpty, "FoundationModels generated a non-empty answer (live)")
            check(!gen.sources.isEmpty, "FoundationModels answer cites passages (live)")
            print("  → FoundationModels live output: \(gen.text.prefix(280))")
        } else {
            print("  ⓘ Apple Intelligence not available — skipping live FoundationModels smoke")
        }
    } else {
        print("  ⓘ macOS < 26 — FoundationModels path not compiled in")
    }
    #else
    print("  ⓘ FoundationModels not importable in this SDK — extractive fallback only")
    #endif
}

print(failures == 0 ? "\n✅ all ShelfseerCore tests passed" : "\n❌ \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
