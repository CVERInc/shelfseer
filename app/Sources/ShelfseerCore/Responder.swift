import Foundation

// Turns retrieved passages into an answer. This is the seam where a real local
// LLM will eventually live. For the scaffold we ship an EXTRACTIVE responder:
// it doesn't generate prose, it stitches the top retrieved passages together
// and presents them as the answer. That already delivers shelfseer's core
// promise — "find the right passages from my own library" — with zero model
// download, and it never hallucinates because every word is from the source.

public protocol Responder {
    /// Produce an answer to `question`, grounded in `passages` (already ranked,
    /// highest first).
    func respond(question: String, passages: [ScoredPassage]) -> Answer
}

/// The default, generation-free responder. Presents the top passages verbatim
/// as the answer, each labeled with its source document.
///
/// TODO(local-LLM seam): replace/augment this with a real on-device generator
/// that reads `question` + `passages` as context and writes a synthesized,
/// cited answer. Candidate backends, all on-device and owned-not-rented:
///   • Apple Foundation Models (the system LLM, macOS 26+) — zero download.
///   • MLX (Apple-silicon native) running a small instruct model.
///   • llama.cpp with a quantized GGUF (downloaded on first run — see
///     .gitignore: model weights are never committed).
/// Whatever the backend, it conforms to `Responder` and the rest of the
/// pipeline (ingest → index → retrieve) is unchanged. Keep retrieval as the
/// source of truth and constrain generation to the supplied passages so the
/// answer stays grounded in the user's own library.
public struct ExtractiveResponder: Responder {
    /// How many of the ranked passages to include in the stitched answer.
    public let maxPassages: Int

    public init(maxPassages: Int = 3) {
        self.maxPassages = max(1, maxPassages)
    }

    public func respond(question: String, passages: [ScoredPassage]) -> Answer {
        let used = Array(passages.prefix(maxPassages))
        guard !used.isEmpty else {
            return Answer(
                text: "I couldn't find anything in this library that answers that. Try rephrasing, or point shelfseer at a folder that contains relevant documents.",
                sources: []
            )
        }
        let body = used.map { scored in
            "From “\(scored.passage.documentTitle)”:\n\(scored.passage.text)"
        }.joined(separator: "\n\n— — —\n\n")

        let preamble = "Here is what your library says about that:\n\n"
        return Answer(text: preamble + body, sources: used)
    }
}
