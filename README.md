# shelfseer

> Talk to the library you already own — your notes, your documents, the books you bound yourself — entirely on your Mac, 100% offline.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-black?logo=apple)](https://www.apple.com/macos/)
[![Status: early](https://img.shields.io/badge/status-early%20development-orange)](#status)

**No API keys · No subscriptions · No internet · Your library never leaves your machine.**

> ⚠️ **Status.** shelfseer is at the early scaffold stage — a working skeleton, not yet the full experience. This README describes the intended product. Watch the repo for the first feature-complete build.

## What shelfseer is

shelfseer points a small, **on-device** language model at a folder of documents **you own** — and lets you ask it questions, find passages, and get answers grounded in *your own* texts. Nothing is uploaded; there is no pipe to the outside world.

It is the companion to **[reepub](https://github.com/CVERInc/reepub)**, which turns the paper you own into a personal library of clean, reflowable EPUBs. Together they tell one story:

> **reepub binds your paper into a library you own. shelfseer lets you talk to it. First you own the books — then you own the librarian.**

## Why on-device

The intelligence here lives mostly in **retrieval** — finding the right passages from your own library — so a small local model is enough. That means the whole thing can run on your Mac, which buys you what no cloud service can sell:

- **Ownership, not rental.** A capability that lives on your shelf — no one can reprice it, gate it, or switch it off.
- **Privacy that's structural, not a promise.** Your most private text (journals, letters, manuscripts) never leaves the machine. There is no pipe.
- **Offline & permanent.** Works with no network, no account, and keeps working regardless of any vendor.

## Intended use

shelfseer is for querying documents **you own or have the right to read** — your own writing, notes and correspondence, public-domain works, or books you physically own. Everything is processed locally; nothing is ever uploaded. Please respect copyright and the rights of authors and publishers.

## Architecture

A native macOS SwiftUI app (SwiftPM, no Xcode required), themed with CVER's shared design system [Signet](https://github.com/CVERInc/signet). The RAG pipeline lives in a pure-logic `ShelfseerCore` library, built as clean protocol seams so each stage can be upgraded independently:

| Stage | Today | Seam for later |
|---|---|---|
| **Ingest** | `.txt` / `.md` from a folder | EPUB chapters (from sister tool [reepub](https://github.com/CVERInc/reepub)) |
| **Chunk** | paragraph-packing splitter | sentence/token-aware splitter |
| **Embed** | Apple `NLEmbedding`, on-device, zero download (deterministic hashing fallback when no model is present) | a stronger local model (e.g. MLX sentence-transformer) |
| **Index** | in-memory cosine top-k | ANN index (HNSW/IVF) for very large libraries |
| **Answer** | **extractive** — stitches the top retrieved passages, cited, never hallucinated | a real **on-device LLM** (Apple Foundation Models / MLX / llama.cpp) constrained to the retrieved passages |

The intelligence is in the **retrieval**; generation is a swappable final step. Nothing downloads a multi-GB model by default, and nothing ever leaves your Mac.

```
app/
├── Package.swift              # ShelfseerCore + ShelfseerApp + ShelfseerTests, depends on Signet
├── Sources/ShelfseerCore/     # Models, Chunker, Ingestor, Embedder, VectorIndex, Responder, Librarian
├── Sources/ShelfseerApp/      # SwiftUI window (pick folder → index → ask → answer + sources)
├── Sources/ShelfseerTests/    # framework-free runner: swift run ShelfseerTests
└── scripts/build-app.sh       # bundle a double-clickable shelfseer.app
```

Build: `cd app && swift build` · Test: `swift run ShelfseerTests` · Bundle: `./scripts/build-app.sh`

## Status

Early scaffold. The name and concept are locked; the pipeline is wired end-to-end with simple working defaults, and the real on-device answer generator is the next step. See the repo for progress.

## License

MIT — see [LICENSE](LICENSE). © 2026 CVER Inc.
