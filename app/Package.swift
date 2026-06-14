// swift-tools-version: 5.9
import PackageDescription

// shelfseer's native macOS app — 100% offline local RAG: "talk to the library
// you already own". Layout mirrors the CVER family convention (cf. snapsift,
// reepub): a pure-logic library (ShelfseerCore: chunking, embedding, vector
// index, retrieval, answer synthesis — all protocol-seamed so a better local
// model can swap in later), the SwiftUI app on top (ShelfseerApp, reef-themed
// via Signet), and a framework-free test runner (ShelfseerTests) that drives
// Core through a real ingest → index → ask round-trip. Pinned to swift-tools
// 5.9 / macOS 13.
let package = Package(
    name: "shelfseer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShelfseerCore", targets: ["ShelfseerCore"]),
        .executable(name: "ShelfseerApp", targets: ["ShelfseerApp"]),
        .executable(name: "ShelfseerTests", targets: ["ShelfseerTests"]),
    ],
    dependencies: [
        // Signet — CVER's shared design system. Pinned to main / latest per the
        // in-house dep convention, so design improvements land everywhere.
        .package(url: "https://github.com/CVERInc/signet", branch: "main"),
    ],
    targets: [
        // Pure RAG pipeline: models, chunker, ingestor, embedder, vector index,
        // responder, librarian. No UI. NaturalLanguage is the only system dep.
        .target(name: "ShelfseerCore"),
        // SwiftUI app over Core, reef-themed via Signet.
        .executableTarget(name: "ShelfseerApp", dependencies: [
            "ShelfseerCore",
            .product(name: "Signet", package: "signet"),
        ]),
        // Framework-free test runner (real ingest → index → ask round-trip).
        .executableTarget(name: "ShelfseerTests", dependencies: ["ShelfseerCore"]),
    ]
)
