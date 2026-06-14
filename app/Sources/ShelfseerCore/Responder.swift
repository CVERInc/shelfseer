import Foundation

// Turns retrieved passages into an answer. This is the seam where a real local
// LLM will eventually live. For the scaffold we ship an EXTRACTIVE responder:
// it doesn't generate prose, it stitches the top retrieved passages together
// and presents them as the answer. That already delivers shelfseer's core
// promise — "find the right passages from my own library" — with zero model
// download, and it never hallucinates because every word is from the source.

public protocol Responder {
    /// Produce an answer to `question`, grounded in `passages` (already ranked,
    /// highest first). Async because a real on-device generator (Apple
    /// Foundation Models) answers asynchronously; extractive responders simply
    /// return immediately.
    func respond(question: String, passages: [ScoredPassage]) async -> Answer
}

/// The default, generation-free responder. Presents the top passages verbatim
/// as the answer, each labeled with its source document.
///
/// The on-device generator seam is now filled by FoundationModelsResponder
/// (Apple Foundation Models, macOS 26+, zero download beyond the OS), selected
/// by ResponderFactory when Apple Intelligence is available and falling back to
/// this extractive responder otherwise. Other backends (MLX, or llama.cpp with
/// a quantized GGUF downloaded on first run — see .gitignore: model weights are
/// never committed) can swap in behind the same `Responder` protocol. Whatever
/// the backend, retrieval stays the source of truth and generation is
/// constrained to the supplied passages so the answer stays grounded in the
/// user's own library.
public struct ExtractiveResponder: Responder {
    /// How many of the ranked passages to include in the stitched answer.
    public let maxPassages: Int

    public init(maxPassages: Int = 3) {
        self.maxPassages = max(1, maxPassages)
    }

    public func respond(question: String, passages: [ScoredPassage]) async -> Answer {
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

public enum ResponderFactory {
    /// The best available on-device responder. If Apple's Foundation Models
    /// system LLM is present AND ready (macOS 26+, Apple Intelligence enabled,
    /// model downloaded), shelfseer generates a synthesized, cited answer
    /// grounded only in the retrieved passages. Otherwise it falls back to the
    /// extractive responder, which stitches the top passages verbatim — never
    /// crashing, never requiring Apple Intelligence, never downloading anything.
    public static func makeDefault() -> Responder {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let llm = FoundationModelsResponder() {
                return llm
            }
        }
        #endif
        return ExtractiveResponder()
    }
}
