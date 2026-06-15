import Foundation

// The real on-device generator: Apple's Foundation Models system LLM (macOS 26+,
// shipped with the OS, zero download beyond the OS model assets which live in
// the OS — never in this repo). It reads the retrieved passages + the question
// and writes a synthesized, cited answer that is grounded ONLY in those
// passages. Retrieval stays the source of truth; generation is constrained to
// the supplied passages so the answer never wanders outside the user's own
// library, and the model is instructed to say so when the passages don't
// contain the answer.
//
// Everything runs on-device — no network call, consistent with shelfseer's
// whole premise. If the system model is unavailable (older OS, Apple
// Intelligence off, or model not yet downloaded), the factory falls back to the
// ExtractiveResponder and this type is never constructed; even so, respond()
// degrades to extractive at call time if a generation error occurs, so a
// transient failure can never crash a query.

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
public struct FoundationModelsResponder: Responder {
    /// How many of the ranked passages to feed the model as grounding context.
    public let maxPassages: Int
    /// Extractive responder used as the in-call degradation path.
    private let fallback: ExtractiveResponder

    /// Fails (returns nil) when the system language model is not available, so
    /// the factory can fall back cleanly. Checking availability up front avoids
    /// constructing a session that can never answer.
    public init?(maxPassages: Int = 4) {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }
        self.maxPassages = max(1, maxPassages)
        self.fallback = ExtractiveResponder(maxPassages: maxPassages)
    }

    public func respond(question: String, passages: [ScoredPassage]) async -> Answer {
        let used = Array(passages.prefix(maxPassages))
        guard !used.isEmpty else {
            // No passages retrieved — same honest message as the extractive path.
            return await fallback.respond(question: question, passages: [])
        }

        let instructions = Self.instructions
        let prompt = Self.buildPrompt(question: question, passages: used)

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return Self.degraded(reason: "the on-device model returned an empty answer",
                                     await fallback.respond(question: question, passages: passages))
            }
            // Cite the same passages we grounded the generation in.
            return Answer(text: text, sources: used)
        } catch {
            // Guardrail trip, context overflow, or any transient model error:
            // degrade to the extractive answer rather than failing the query —
            // but SURFACE the failure (note) instead of silently hiding it, so
            // the user knows the answer is verbatim passages, not a synthesis.
            return Self.degraded(reason: Self.reason(for: error),
                                 await fallback.respond(question: question, passages: passages))
        }
    }

    /// Tag an extractive fallback answer with why generation was skipped, so the
    /// degradation is visible to the user rather than masquerading as a normal
    /// synthesized answer.
    private static func degraded(reason: String, _ answer: Answer) -> Answer {
        Answer(text: answer.text,
               sources: answer.sources,
               note: "Showing the most relevant passages verbatim: \(reason).")
    }

    /// A short, user-facing reason string for a generation error, without
    /// leaking internal detail. Context-overflow is the common one worth naming.
    public static func reason(for error: Error) -> String {
        let desc = String(describing: error).lowercased()
        if desc.contains("context") || desc.contains("exceed") || desc.contains("token") {
            return "the question and passages were too long for the on-device model"
        }
        if desc.contains("guard") || desc.contains("safety") || desc.contains("unsafe") {
            return "the on-device model declined to answer (safety guardrail)"
        }
        return "the on-device model was unavailable for this question"
    }

    /// System instructions: answer ONLY from the provided passages, cite them by
    /// number, and admit when they don't contain the answer.
    static let instructions = """
    You are shelfseer, a librarian that answers questions using ONLY the passages \
    provided from the user's own book library. Follow these rules strictly:
    - Base your answer solely on the numbered passages given. Do not use outside \
    knowledge.
    - If the passages do not contain the answer, say so plainly — do not guess.
    - Cite the passages you used by their number, e.g. "(passage 1)".
    - Be concise and quote or paraphrase faithfully; never invent facts, titles, \
    or details that are not in the passages.
    """

    /// Build the user prompt: the numbered passages (with their source titles)
    /// followed by the question.
    static func buildPrompt(question: String, passages: [ScoredPassage]) -> String {
        var lines = ["Passages from the library:\n"]
        for (i, scored) in passages.enumerated() {
            lines.append("Passage \(i + 1) — from “\(scored.passage.documentTitle)”:")
            lines.append(scored.passage.text)
            lines.append("")
        }
        lines.append("Question: \(question)")
        lines.append("\nAnswer using only the passages above, and cite the passage numbers you used.")
        return lines.joined(separator: "\n")
    }
}
#endif
