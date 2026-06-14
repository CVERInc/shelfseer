import Foundation

// Splits a Document's text into Passages. RAG quality starts here: chunks that
// are too big dilute the embedding; too small lose context. We split on
// paragraph boundaries (blank lines), then pack paragraphs greedily up to a
// target character budget so a passage stays a coherent unit of thought.
//
// This is intentionally simple and dependency-free. A smarter sentence- or
// token-aware splitter can replace it behind the same `Chunker` protocol.

public protocol Chunker {
    func chunk(_ document: Document) -> [Passage]
}

public struct ParagraphChunker: Chunker {
    /// Target characters per passage. Paragraphs are packed up to this budget.
    public let targetChars: Int
    /// A single paragraph longer than this is hard-split so no passage is huge.
    public let maxChars: Int

    public init(targetChars: Int = 800, maxChars: Int = 1_600) {
        self.targetChars = max(1, targetChars)
        self.maxChars = max(self.targetChars, maxChars)
    }

    public func chunk(_ document: Document) -> [Passage] {
        let paragraphs = Self.paragraphs(in: document.text)
        var packed: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { packed.append(trimmed) }
            current = ""
        }

        for paragraph in paragraphs {
            // Hard-split an over-long paragraph into max-sized slices.
            for slice in Self.slice(paragraph, max: maxChars) {
                if current.isEmpty {
                    current = slice
                } else if current.count + 1 + slice.count <= targetChars {
                    current += "\n" + slice
                } else {
                    flush()
                    current = slice
                }
            }
        }
        flush()

        return packed.enumerated().map { idx, text in
            Passage(id: "\(document.id)#\(idx)",
                    documentID: document.id,
                    documentTitle: document.title,
                    index: idx,
                    text: text)
        }
    }

    /// Split on one-or-more blank lines into paragraph blocks.
    static func paragraphs(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Slice a string into chunks of at most `max` characters, preferring to
    /// break on whitespace so words aren't cut in half.
    static func slice(_ s: String, max: Int) -> [String] {
        guard s.count > max else { return [s] }
        var out: [String] = []
        var remaining = Substring(s)
        while remaining.count > max {
            let hardEnd = remaining.index(remaining.startIndex, offsetBy: max)
            // Walk back to the last whitespace within the window, if any.
            var breakIdx = hardEnd
            if let ws = remaining[remaining.startIndex..<hardEnd].lastIndex(where: { $0 == " " || $0 == "\n" }) {
                breakIdx = ws
            }
            let piece = remaining[remaining.startIndex..<breakIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            remaining = remaining[breakIdx...].drop(while: { $0 == " " || $0 == "\n" })
        }
        let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}
