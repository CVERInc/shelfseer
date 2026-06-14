import Foundation
import NaturalLanguage

// Turns text into a fixed-length vector so we can measure semantic closeness.
// The protocol is the seam: today we use Apple's on-device NLEmbedding (zero
// model download, ships with macOS — fits "use an existing local model"); a
// stronger local embedder (a sentence-transformer via MLX, say) can swap in
// later without touching the rest of the pipeline.

public protocol Embedder {
    /// The dimensionality of vectors this embedder produces.
    var dimension: Int { get }
    /// Embed a single string. Implementations must return a vector of `dimension`.
    func embed(_ text: String) -> [Double]
}

public extension Embedder {
    /// Embed many strings. Override for batch acceleration if available.
    func embed(_ texts: [String]) -> [[Double]] { texts.map(embed) }
}

/// Apple's built-in word embedding, mean-pooled over tokens into a sentence
/// vector. `NLEmbedding.wordEmbedding(for:)` ships with the OS, needs no
/// download, and runs fully on-device. If the model is unavailable for the
/// requested language (some locales lack one, and CI runners can be sparse),
/// this initializer returns nil so callers can fall back gracefully.
public struct NLWordEmbedder: Embedder {
    private let embedding: NLEmbedding
    public let dimension: Int

    public init?(language: NLLanguage = .english) {
        guard let embedding = NLEmbedding.wordEmbedding(for: language) else { return nil }
        self.embedding = embedding
        self.dimension = embedding.dimension
    }

    public func embed(_ text: String) -> [Double] {
        var sum = [Double](repeating: 0, count: dimension)
        var count = 0
        // Tokenize into words; average each word's vector (mean pooling).
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vec = embedding.vector(for: word) {
                for i in 0..<min(dimension, vec.count) { sum[i] += vec[i] }
                count += 1
            }
            return true
        }
        guard count > 0 else { return sum }   // all-OOV → zero vector
        for i in 0..<dimension { sum[i] /= Double(count) }
        return sum
    }
}

/// A deterministic, dependency-free fallback embedder: a hashed bag-of-words
/// projected into a fixed-dimension vector. It is NOT semantic — it captures
/// lexical (term) overlap only — but it is stable, offline, and identical on
/// every machine, which makes it the right default for tests/CI and a safe
/// floor when no on-device language model is available. Same protocol, so the
/// rest of the pipeline can't tell the difference.
public struct HashingEmbedder: Embedder {
    public let dimension: Int

    public init(dimension: Int = 256) {
        self.dimension = max(1, dimension)
    }

    public func embed(_ text: String) -> [Double] {
        var vec = [Double](repeating: 0, count: dimension)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            guard !token.isEmpty else { return true }
            let bucket = Int(Self.fnv1a(token) % UInt64(dimension))
            // Signed contribution so different terms don't all push one way.
            let sign: Double = (Self.fnv1a("§" + token) & 1) == 0 ? 1 : -1
            vec[bucket] += sign
            return true
        }
        return vec
    }

    /// FNV-1a — a tiny, stable, non-cryptographic hash (same on every platform).
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

public enum EmbedderFactory {
    /// The best available on-device embedder: Apple's NLEmbedding if present,
    /// otherwise the deterministic hashing fallback. Never throws, never
    /// downloads — shelfseer always has *some* working embedder.
    public static func makeDefault(language: NLLanguage = .english) -> Embedder {
        NLWordEmbedder(language: language) ?? HashingEmbedder()
    }
}
